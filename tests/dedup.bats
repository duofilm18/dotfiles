#!/usr/bin/env bats
# dedup.bats - T8-T9: 2 秒去重

setup() {
    load test_helper
    common_setup
}

teardown() {
    common_teardown
}

@test "T8: 2 秒內重複狀態被去重（dedup 時間戳不更新）" {
    fire UserPromptSubmit
    local ts1
    ts1=$(head -1 "$DEDUP_FILE")
    fire UserPromptSubmit
    local ts2
    ts2=$(head -1 "$DEDUP_FILE")
    [ "$ts1" = "$ts2" ]
}

@test "T9: 超過 2 秒後 dedup 放行（時間戳更新）" {
    fire UserPromptSubmit
    local ts1
    ts1=$(head -1 "$DEDUP_FILE")
    sleep 2.5
    fire UserPromptSubmit
    local ts2
    ts2=$(head -1 "$DEDUP_FILE")
    [ "$ts1" != "$ts2" ]
}
