#!/usr/bin/env bats
# flock.bats - T-B1, T-B2: activity 在 flock 之前更新

setup() {
    load test_helper
    common_setup
}

teardown() {
    common_teardown
}

@test "T-B1: 鎖被占住但 activity 仍更新" {
    # 手動占住鎖，模擬 catch-all hook 搶鎖
    exec 201>"$LOCK_FILE"
    flock -n 201

    fire UserPromptSubmit

    # activity file 應已更新（在鎖之前寫入）
    [ -f "$ACTIVITY_FILE" ]
    local ts now diff
    ts=$(head -1 "$ACTIVITY_FILE")
    now=$(date +%s)
    diff=$((now - ${ts:-0}))
    [ "$diff" -le 2 ]

    flock -u 201
    exec 201>&-
}

@test "T-B2: 拿不到鎖 → 狀態未切換" {
    exec 201>"$LOCK_FILE"
    flock -n 201

    fire UserPromptSubmit

    # 狀態檔不該被更新（因為拿不到鎖，hook 直接 exit 0）
    [ ! -f "$STATE_FILE" ]

    flock -u 201
    exec 201>&-
}
