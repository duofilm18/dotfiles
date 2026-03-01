#!/bin/bash
# claude-dispatch.sh - 事件分發器（<1ms 返回）
# 所有 handler 背景平行執行，互不阻塞
#
# 用法: claude-dispatch.sh <event> [matcher]

EVENT="$1"
MATCHER="${2:-}"
# git repo root 取名，不怕 cd 子目錄
# 注意：basename "" 回傳空字串但 exit=0，所以不能用 || fallback
PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)"
PROJECT="$(basename "${PROJECT:-$PWD}")"

# 從 stdin 讀取 hook JSON（非阻塞，可能為空）
INPUT=$(timeout 1 cat 2>/dev/null || true)

# ── 手機通知（Stop 事件） ──
if [ "$EVENT" = "Stop" ]; then
    curl -s -X POST "https://ntfy.sh/claude-notify-rpi5b" \
        -H "Title: $PROJECT" -d "Claude Code 完成" &>/dev/null &
fi

exit 0
