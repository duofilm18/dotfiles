#!/usr/bin/env bats
# state_machine.bats - T1-T7: 狀態轉換 + 智慧抑制
#
# 每個 @test 獨立隔離，不需要 sleep 去重間隔

setup() {
    load test_helper
    common_setup
}

teardown() {
    common_teardown
}

@test "T1: UserPromptSubmit → RUNNING" {
    fire UserPromptSubmit
    assert_state "RUNNING"
}

@test "T2: PreToolUse AskUserQuestion → WAITING" {
    fire UserPromptSubmit
    fire PreToolUse AskUserQuestion
    assert_state "WAITING"
}

@test "T3: PostToolUse AskUserQuestion → RUNNING" {
    fire PreToolUse AskUserQuestion
    fire PostToolUse AskUserQuestion
    assert_state "RUNNING"
}

@test "T4: Notification idle_prompt → IDLE" {
    fire UserPromptSubmit
    fire Notification idle_prompt
    assert_state "IDLE"
}

@test "T5: Notification permission_prompt → WAITING" {
    fire UserPromptSubmit
    fire Notification permission_prompt
    assert_state "WAITING"
}

@test "T6: Stop → COMPLETED" {
    fire UserPromptSubmit
    fire Stop
    assert_state "COMPLETED"
}

@test "T7: WAITING 中收 Stop → 狀態被抑制" {
    fire PreToolUse AskUserQuestion
    fire Stop
    assert_state "WAITING"
}
