#!/usr/bin/env bats
# melody.bats - 旋律維度: 事件 dispatch 音效 + git 音效

setup() {
    load test_helper
    common_setup
}

teardown() {
    common_teardown
}

# ── 事件 dispatch 音效 ──────────────────────────

@test "T1 melody: SessionStart → windows_xp" {
    fire SessionStart
    assert_melody "windows_xp"
}

@test "T2 melody: UserPromptSubmit → minimal_beep" {
    fire UserPromptSubmit
    assert_melody "minimal_beep"
}

@test "T3 melody: PreToolUse AskUserQuestion → nokia" {
    fire PreToolUse AskUserQuestion
    assert_melody "nokia"
}

@test "T4 melody: PermissionRequest → question" {
    fire PermissionRequest
    assert_melody "question"
}

@test "T5 melody: PostToolUseFailure → short_error" {
    fire PostToolUseFailure
    assert_melody "short_error"
}

@test "T6 melody: Notification idle_prompt → soft_chime" {
    fire Notification idle_prompt
    assert_melody "soft_chime"
}

@test "T7 melody: Notification permission_prompt → alert_ping" {
    fire Notification permission_prompt
    assert_melody "alert_ping"
}

@test "T8 melody: SubagentStart → minimal_double" {
    fire SubagentStart
    assert_melody "minimal_double"
}

@test "T9 melody: Stop → default_completed" {
    fire Stop
    assert_melody "default_completed"
}

@test "T10 melody: TaskCompleted → short_success" {
    fire TaskCompleted
    assert_melody "short_success"
}

@test "T11 melody: SessionEnd → star_wars" {
    fire SessionEnd
    assert_melody "star_wars"
}

@test "T12 melody: TeammateIdle → minimal_triple" {
    fire TeammateIdle
    assert_melody "minimal_triple"
}

@test "T13 melody: PostToolUse AskUserQuestion → no melody" {
    local before
    before=$(melody_line_count)
    fire PostToolUse AskUserQuestion
    assert_no_melody "$before"
}

# ── git 音效 ─────────────────────────────────

@test "T14: git add → short_running" {
    > "$MELODY_LOG"
    fire PostToolUse Bash '{"tool_input":{"command":"git add file.txt"}}'
    assert_melody "short_running"
}

@test "T15: git commit → tetris" {
    > "$MELODY_LOG"
    fire PostToolUse Bash '{"tool_input":{"command":"git commit -m \"test\""}}'
    assert_melody "tetris"
}

@test "T16: git push → super_mario" {
    > "$MELODY_LOG"
    fire PostToolUse Bash '{"tool_input":{"command":"git push origin main"}}'
    assert_melody "super_mario"
}

@test "T17: non-git command → no melody" {
    > "$MELODY_LOG"
    fire PostToolUse Bash '{"tool_input":{"command":"ls -la"}}'
    local count
    count=$(melody_line_count)
    [ "$count" -eq 0 ]
}
