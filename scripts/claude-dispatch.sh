#!/bin/bash
# claude-dispatch.sh - 事件分發器（<1ms 返回）
# 所有 handler 背景平行執行，互不阻塞
#
# 用法: claude-dispatch.sh <event> [matcher]

EVENT="$1"
MATCHER="${2:-}"
SCRIPT_DIR="$(dirname "$0")"

# 從 stdin 讀取 hook JSON（非阻塞，可能為空）
INPUT=$(timeout 1 cat 2>/dev/null || true)

# ── LED 狀態機（背景） ──
echo "$INPUT" | (timeout 5 "$SCRIPT_DIR/claude-hook.sh" "$EVENT" "$MATCHER" || true) &>/dev/null &

# ── 音效決策（所有音效邏輯集中於此） ──
MELODY=""
case "$EVENT/$MATCHER" in
    UserPromptSubmit/)              MELODY="short_running" ;;
    PreToolUse/AskUserQuestion)     MELODY="nokia" ;;
    Notification/permission_prompt) MELODY="nokia" ;;
    Notification/idle_prompt)       MELODY="minimal_double" ;;
    Stop/)                          MELODY="star_wars" ;;
esac

# Git 操作音效（PostToolUse Bash|Edit|Write|Read）
if [ -z "$MELODY" ] && [ "$EVENT" = "PostToolUse" ] && [ -n "$INPUT" ]; then
    GIT_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    case "${GIT_CMD:-}" in
        *"git push"*)   MELODY="windows_xp" ;;
        *"git commit"*) MELODY="short_success" ;;
        *"git add"*)    MELODY="minimal_double" ;;
    esac
fi

if [ -n "$MELODY" ]; then
    nohup "$SCRIPT_DIR/play-melody.sh" "$MELODY" </dev/null &>/dev/null &
fi

exit 0
