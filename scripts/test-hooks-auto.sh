#!/bin/bash
# test-hooks-auto.sh - 全自動 Hook 測試 Agent（無需人工觀察）
#
# 自動驗證三個維度：
#   1. 狀態檔 /tmp/claude-led-state
#   2. MQTT LED 指令（透過 mosquitto_sub 攔截）
#   3. play-melody 呼叫記錄（透過 log 檔）
#
# 用法: test-hooks-auto.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EFFECTS_FILE="$SCRIPT_DIR/../wsl/led-effects.json"
MQTT_HOST="${MQTT_HOST:-192.168.88.10}"
MQTT_PORT="${MQTT_PORT:-1883}"

# 測試用暫存檔
STATE_FILE="/tmp/claude-led-state"
DEDUP_FILE="/tmp/claude-led-dedup"
IDLE_PENDING="/tmp/claude-idle-pending"
MQTT_LOG="/tmp/test-mqtt-capture.log"
MELODY_LOG="/tmp/test-melody-capture.log"

# 顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { ((PASS++)); echo -e "  ${GREEN}✓${NC} $1"; }
fail() { ((FAIL++)); echo -e "  ${RED}✗${NC} $1"; }
warn() { ((WARN++)); echo -e "  ${YELLOW}⚠${NC} $1"; }
header() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
dim() { echo -e "  ${DIM}$1${NC}"; }

# ══════════════════════════════════════════════════════════
# 環境準備
# ══════════════════════════════════════════════════════════
setup() {
    header "環境準備"

    # 清除狀態
    rm -f "$STATE_FILE" "$DEDUP_FILE" "$IDLE_PENDING" "$MQTT_LOG" "$MELODY_LOG"
    pass "清除舊狀態檔"

    # 安裝 melody log 模式 flag（讓 play-melody.sh 寫 log 而不是真的播音）
    touch /tmp/test-melody-log-mode
    pass "啟用 melody log 模式（flag file）"

    # 啟動 MQTT 監聽
    MQTT_OK=false
    if command -v mosquitto_sub &>/dev/null; then
        mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "claude/led" -C 100 --timeout 30 > "$MQTT_LOG" 2>/dev/null &
        MQTT_SUB_PID=$!
        sleep 0.5
        if kill -0 "$MQTT_SUB_PID" 2>/dev/null; then
            MQTT_OK=true
            pass "MQTT 監聽啟動 (PID=$MQTT_SUB_PID)"
        else
            warn "MQTT 監聽啟動失敗（LED 驗證將跳過）"
        fi
    else
        warn "mosquitto_sub 未安裝（LED 驗證將跳過）"
    fi
}

cleanup() {
    # 停止 MQTT 監聽
    if [ -n "${MQTT_SUB_PID:-}" ]; then
        kill "$MQTT_SUB_PID" 2>/dev/null
        wait "$MQTT_SUB_PID" 2>/dev/null
    fi
    # 清除 melody log 模式 flag
    rm -f /tmp/test-melody-log-mode
}
trap cleanup EXIT

# ══════════════════════════════════════════════════════════
# 驗證函式
# ══════════════════════════════════════════════════════════

# 驗證狀態檔
assert_state() {
    local expected="$1"
    local label="$2"
    local actual
    actual=$(cat "$STATE_FILE" 2>/dev/null | head -1)
    if [ "$actual" = "$expected" ]; then
        pass "$label → 狀態 $expected ✓"
    else
        fail "$label → 狀態 '$actual'（預期 $expected）"
    fi
}

# 驗證 MQTT 收到的最後一筆 LED 指令
assert_mqtt_led() {
    local expected_pattern="$1"
    local label="$2"

    if [ "$MQTT_OK" != "true" ]; then
        dim "跳過 MQTT 驗證: $label"
        return
    fi

    sleep 0.5  # 等 MQTT 訊息到達
    local last_msg
    last_msg=$(tail -1 "$MQTT_LOG" 2>/dev/null)

    if [ -z "$last_msg" ]; then
        fail "$label → MQTT 沒收到訊息"
        return
    fi

    if echo "$last_msg" | jq -e "$expected_pattern" &>/dev/null; then
        pass "$label → LED 指令正確 ✓"
    else
        fail "$label → LED 指令不符: $last_msg"
    fi
}

# 驗證 melody 有被呼叫
assert_melody() {
    local expected_melody="$1"
    local label="$2"

    sleep 1  # 等 setsid + play-melody 寫 log
    local last_melody
    last_melody=$(tail -1 "$MELODY_LOG" 2>/dev/null)

    if [ -z "$last_melody" ]; then
        fail "$label → play-melody 沒有被呼叫"
        return
    fi

    if echo "$last_melody" | grep -q "$expected_melody"; then
        pass "$label → 旋律 $expected_melody ✓"
    else
        fail "$label → 旋律不符: '$last_melody'（預期含 $expected_melody）"
    fi
}

# 觸發 hook 事件
fire() {
    local event="$1"
    local matcher="${2:-}"
    local json="${3:-\{\}}"
    echo "$json" | "$SCRIPT_DIR/claude-hook.sh" "$event" $matcher 2>/dev/null || true
}

# ══════════════════════════════════════════════════════════
# 測試案例
# ══════════════════════════════════════════════════════════

test_state_transitions() {
    header "狀態轉換測試"

    # T1: UserPromptSubmit → RUNNING
    rm -f "$STATE_FILE" "$DEDUP_FILE"
    fire UserPromptSubmit
    assert_state "RUNNING" "T1 UserPromptSubmit"
    assert_mqtt_led '.pattern == "pulse" and .g == 255' "T1 LED=green pulse"
    assert_melody "short_running" "T1 旋律"

    sleep 2.5  # 過去重

    # T2: PreToolUse AskUserQuestion → WAITING
    fire PreToolUse AskUserQuestion
    assert_state "WAITING" "T2 PreToolUse Ask"
    assert_mqtt_led '.pattern == "blink" and .r == 255' "T2 LED=red blink"
    assert_melody "short_waiting" "T2 旋律"

    sleep 2.5

    # T3: PostToolUse AskUserQuestion → RUNNING
    fire PostToolUse AskUserQuestion
    assert_state "RUNNING" "T3 PostToolUse Ask"
    assert_melody "short_running" "T3 旋律"

    sleep 2.5

    # T4: Notification idle_prompt → IDLE
    fire Notification idle_prompt
    assert_state "IDLE" "T4 idle_prompt"
    assert_mqtt_led '.pattern == "pulse" and .r == 255' "T4 LED=orange pulse"
    assert_melody "minimal_double" "T4 旋律"

    sleep 2.5

    # T5: Notification permission_prompt → WAITING
    fire Notification permission_prompt
    assert_state "WAITING" "T5 permission_prompt"
    assert_melody "short_waiting" "T5 旋律"

    sleep 2.5

    # T6: Stop → COMPLETED（先重設 RUNNING）
    rm -f "$STATE_FILE" "$DEDUP_FILE"
    echo "RUNNING" > "$STATE_FILE"
    fire Stop
    assert_state "COMPLETED" "T6 Stop"
    assert_mqtt_led '.pattern == "rainbow"' "T6 LED=rainbow"
    assert_melody "zelda_secret" "T6 旋律"
}

test_suppression() {
    header "智慧抑制測試"

    # T7: WAITING 中收 Stop → 維持 WAITING
    rm -f "$STATE_FILE" "$DEDUP_FILE"
    fire PreToolUse AskUserQuestion
    sleep 2.5
    local before
    before=$(cat "$MELODY_LOG" 2>/dev/null | wc -l)
    fire Stop
    local after
    after=$(cat "$MELODY_LOG" 2>/dev/null | wc -l)
    assert_state "WAITING" "T7 WAITING→Stop 被抑制"
    if [ "$before" = "$after" ]; then
        pass "T7 Stop 沒有觸發旋律 ✓"
    else
        fail "T7 Stop 不該觸發旋律但觸發了"
    fi
}

test_dedup() {
    header "去重測試"

    rm -f "$STATE_FILE" "$DEDUP_FILE"

    # T8: 連續兩次 RUNNING，第二次被去重
    fire UserPromptSubmit
    sleep 1  # 等第一次 melody 寫入 log
    local count1
    count1=$(cat "$MELODY_LOG" 2>/dev/null | wc -l)
    fire UserPromptSubmit  # 2 秒內再發
    sleep 1
    local count2
    count2=$(cat "$MELODY_LOG" 2>/dev/null | wc -l)
    if [ "$count1" = "$count2" ]; then
        pass "T8 去重：2 秒內相同狀態不重複觸發 ✓"
    else
        fail "T8 去重失敗：melody 被重複呼叫"
    fi

    # T9: 超過 2 秒後觸發
    sleep 2.5
    fire UserPromptSubmit
    sleep 1
    local count3
    count3=$(cat "$MELODY_LOG" 2>/dev/null | wc -l)
    if [ "$count3" -gt "$count2" ]; then
        pass "T9 超過 2 秒後重新觸發 ✓"
    else
        fail "T9 超過 2 秒仍被去重"
    fi
}

test_git_melody() {
    header "Git 音效測試"

    rm -f "$STATE_FILE" "$DEDUP_FILE"
    echo "RUNNING" > "$STATE_FILE"

    # T10: git add
    > "$MELODY_LOG"  # 清空
    fire PostToolUse Bash '{"tool_input":{"command":"git add file.txt"}}'
    sleep 1
    assert_melody "minimal_double" "T10 git add"

    # T11: git commit
    > "$MELODY_LOG"
    fire PostToolUse Bash '{"tool_input":{"command":"git commit -m \"test\""}}'
    sleep 1
    assert_melody "short_success" "T11 git commit"

    # T12: git push
    > "$MELODY_LOG"
    fire PostToolUse Bash '{"tool_input":{"command":"git push origin main"}}'
    sleep 1
    assert_melody "windows_xp" "T12 git push"

    # T13: 非 git 不觸發
    > "$MELODY_LOG"
    fire PostToolUse Bash '{"tool_input":{"command":"ls -la"}}'
    sleep 1
    local count
    count=$(cat "$MELODY_LOG" 2>/dev/null | wc -l)
    if [ "$count" -eq 0 ]; then
        pass "T13 非 git 指令不觸發旋律 ✓"
    else
        fail "T13 非 git 指令不該觸發但觸發了"
    fi
}

test_led_colors() {
    header "LED 燈色驗證"

    if [ "$MQTT_OK" != "true" ]; then
        warn "MQTT 不可用，跳過 LED 燈色測試"
        return
    fi

    local states="idle running waiting completed error"
    for state in $states; do
        local expected
        expected=$(jq -c --arg s "$state" '.[$s]' "$EFFECTS_FILE")

        # 清空 MQTT log 取最新
        > "$MQTT_LOG"
        "$SCRIPT_DIR/notify.sh" "$state"
        sleep 1

        local received
        received=$(tail -1 "$MQTT_LOG" 2>/dev/null)

        if [ -z "$received" ]; then
            fail "LED $state → MQTT 沒收到"
            continue
        fi

        # 比對 RGB + pattern
        local exp_r exp_g exp_b exp_pattern
        exp_r=$(echo "$expected" | jq '.r')
        exp_g=$(echo "$expected" | jq '.g')
        exp_b=$(echo "$expected" | jq '.b')
        exp_pattern=$(echo "$expected" | jq -r '.pattern')

        local got_r got_g got_b got_pattern
        got_r=$(echo "$received" | jq '.r')
        got_g=$(echo "$received" | jq '.g')
        got_b=$(echo "$received" | jq '.b')
        got_pattern=$(echo "$received" | jq -r '.pattern')

        if [ "$exp_r" = "$got_r" ] && [ "$exp_g" = "$got_g" ] && [ "$exp_b" = "$got_b" ] && [ "$exp_pattern" = "$got_pattern" ]; then
            pass "LED $state → R=$got_r G=$got_g B=$got_b pattern=$got_pattern ✓"
        else
            fail "LED $state → 預期 R=$exp_r G=$exp_g B=$exp_b $exp_pattern，收到 R=$got_r G=$got_g B=$got_b $got_pattern"
        fi
    done
}

# ══════════════════════════════════════════════════════════
# 主程式
# ══════════════════════════════════════════════════════════

echo -e "${CYAN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Hook 全自動測試 Agent                    ║${NC}"
echo -e "${CYAN}║  狀態 + MQTT LED + 旋律 三維度驗證        ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════╝${NC}"

setup
test_state_transitions
test_suppression
test_dedup
test_git_melody
test_led_colors

# ── 總結 ──
header "測試結果"
echo -e "  ${GREEN}通過: $PASS${NC}"
echo -e "  ${RED}失敗: $FAIL${NC}"
echo -e "  ${YELLOW}警告: $WARN${NC}"

if [ "$FAIL" -gt 0 ]; then
    echo -e "\n${RED}有 $FAIL 項失敗${NC}"
    exit 1
else
    echo -e "\n${GREEN}全部通過${NC}"
    exit 0
fi
