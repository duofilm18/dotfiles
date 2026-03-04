#!/usr/bin/env bats
# melody.bats - 旋律維度: T1-T6 dispatch 音效 + T10-T13 git 音效

setup() {
    load test_helper
    common_setup
}

teardown() {
    common_teardown
}

# ── T1-T6 事件 dispatch 音效 ──────────────────────────

@test "T1 melody: UserPromptSubmit → short_running" {
    fire UserPromptSubmit
    assert_melody "short_running"
}

@test "T2 melody: PreToolUse AskUserQuestion → nokia" {
    fire PreToolUse AskUserQuestion
    assert_melody "nokia"
}

@test "T3 melody: PostToolUse AskUserQuestion → 無音效" {
    local before
    before=$(melody_line_count)
    fire PostToolUse AskUserQuestion
    assert_no_melody "$before"
}

@test "T4 melody: Notification idle_prompt → minimal_double" {
    fire Notification idle_prompt
    assert_melody "minimal_double"
}

@test "T5 melody: Notification permission_prompt → nokia" {
    fire Notification permission_prompt
    assert_melody "nokia"
}

@test "T6 melody: Stop → star_wars" {
    fire Stop
    assert_melody "star_wars"
}

# ── T10-T13 git 音效 ─────────────────────────────────

@test "T10: git add → minimal_double" {
    > "$MELODY_LOG"
    fire PostToolUse Bash '{"tool_input":{"command":"git add file.txt"}}'
    assert_melody "minimal_double"
}

@test "T11: git commit → short_success" {
    > "$MELODY_LOG"
    fire PostToolUse Bash '{"tool_input":{"command":"git commit -m \"test\""}}'
    assert_melody "short_success"
}

@test "T12: git push → windows_xp" {
    > "$MELODY_LOG"
    fire PostToolUse Bash '{"tool_input":{"command":"git push origin main"}}'
    assert_melody "windows_xp"
}

@test "T13: 非 git 指令不觸發旋律" {
    > "$MELODY_LOG"
    fire PostToolUse Bash '{"tool_input":{"command":"ls -la"}}'
    local count
    count=$(melody_line_count)
    [ "$count" -eq 0 ]
}
