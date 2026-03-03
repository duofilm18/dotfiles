#!/usr/bin/env bats
# timeout.bats - 背景 timeout 邏輯 + flock 釋放驗證
#
# 補強 claude-hook.sh 的：
#   - RUNNING 60 秒無活動 → auto IDLE
#   - Stop 22 秒後 → auto IDLE（idle-pending 機制）
#   - 背景進程釋放 flock（exec 200>&-）

setup() {
    load test_helper
    common_setup
}

teardown() {
    common_teardown
    # 清除可能殘留的背景進程
    pkill -f "claude-hook.sh.*${TEST_PROJECT}" 2>/dev/null || true
    sleep 0.2
}

# ── RUNNING timeout ────────────────────────────────────

@test "T-TO1: RUNNING 後 activity file 被寫入" {
    fire UserPromptSubmit
    [ -f "$ACTIVITY_FILE" ]
    local ts now diff
    ts=$(head -1 "$ACTIVITY_FILE")
    now=$(date +%s)
    diff=$((now - ${ts:-0}))
    [ "$diff" -le 2 ]
}

@test "T-TO2: RUNNING → activity 更新 → 不會 timeout" {
    fire UserPromptSubmit
    assert_state "RUNNING"
    # 模擬持續活動：更新 activity file
    date +%s > "$ACTIVITY_FILE"
    sleep 1
    assert_state "RUNNING"
}

@test "T-TO3: RUNNING 中收到新事件 → 清除 idle-pending" {
    fire Stop
    [ -f "$IDLE_PENDING" ]
    sleep 0.3
    fire UserPromptSubmit
    [ ! -f "$IDLE_PENDING" ]
    assert_state "RUNNING"
}

# ── Stop → idle-pending ───────────────────────────────

@test "T-TO4: Stop → 建立 idle-pending 檔案" {
    fire UserPromptSubmit
    fire Stop
    assert_state "COMPLETED"
    [ -f "$IDLE_PENDING" ]
}

@test "T-TO5: idle-pending 被移除 → 不回 IDLE" {
    fire UserPromptSubmit
    fire Stop
    assert_state "COMPLETED"
    # 模擬新事件移除 idle-pending
    rm -f "$IDLE_PENDING"
    sleep 1
    # 短時間內不應改變（22 秒 timer 尚未觸發）
    assert_state "COMPLETED"
}

# ── flock 釋放 ─────────────────────────────────────────

@test "T-TO6: 背景進程不占住 flock" {
    fire UserPromptSubmit
    sleep 0.3  # 等背景進程啟動

    # 嘗試取得鎖 — 如果背景進程正確釋放了，這裡能拿到
    run flock -n "$LOCK_FILE" echo "lock acquired"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lock acquired"* ]]
}

@test "T-TO7: Stop 背景進程不占住 flock" {
    fire UserPromptSubmit
    fire Stop
    sleep 0.3

    run flock -n "$LOCK_FILE" echo "lock acquired"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lock acquired"* ]]
}

# ── 多事件交互 ─────────────────────────────────────────

@test "T-TO8: 快速 UserPromptSubmit → Stop → UserPromptSubmit → 狀態正確" {
    fire UserPromptSubmit
    assert_state "RUNNING"
    fire Stop
    assert_state "COMPLETED"
    sleep 2.5  # 過去重
    fire UserPromptSubmit
    assert_state "RUNNING"
    # idle-pending 應被清除
    [ ! -f "$IDLE_PENDING" ]
}
