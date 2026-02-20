#!/bin/bash
# claude-hook.sh - 單一入口狀態機（對齊 ESP32 5 狀態）
#
# 用法: claude-hook.sh <event> [matcher]
#   由 settings.json hooks 統一呼叫，stdin 接收 Claude hook JSON
#
# 5 狀態: IDLE / RUNNING / WAITING / COMPLETED / ERROR
# 功能: 事件→狀態映射 · 2 秒去重 · 智慧抑制 · LED + 音效

set -euo pipefail

EVENT="$1"
MATCHER="${2:-}"
SCRIPT_DIR="$(dirname "$0")"

STATE_FILE="/tmp/claude-led-state"
IDLE_PENDING="/tmp/claude-idle-pending"

# 從 stdin 讀取 JSON（非阻塞，可能為空）
INPUT=$(cat)

# ─── 事件→狀態映射 ───────────────────────────────────

resolve_state() {
    case "$EVENT" in
        UserPromptSubmit)
            echo "RUNNING"
            ;;
        PreToolUse)
            case "$MATCHER" in
                AskUserQuestion) echo "WAITING" ;;
                *) echo "" ;;
            esac
            ;;
        PostToolUse)
            case "$MATCHER" in
                AskUserQuestion) echo "RUNNING" ;;
                *) echo "" ;;
            esac
            ;;
        Notification)
            case "$MATCHER" in
                idle_prompt)       echo "IDLE" ;;
                permission_prompt) echo "WAITING" ;;
                *) echo "" ;;
            esac
            ;;
        Stop)
            echo "COMPLETED"
            ;;
        *)
            echo ""
            ;;
    esac
}

NEW_STATE=$(resolve_state)

# ─── 無狀態變更的事件：只做 side effect ────────────────

# PostToolUse(Bash|Edit|Write|Read) → Git 操作音效
if [ "$EVENT" = "PostToolUse" ] && [[ "$MATCHER" =~ ^(Bash|Edit|Write|Read)$ ]]; then
    GIT_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    if [ -n "$GIT_CMD" ]; then
        GIT_MELODY=""
        case "$GIT_CMD" in
            *"git add"*)    GIT_MELODY="minimal_double" ;;
            *"git commit"*) GIT_MELODY="short_success" ;;
            *"git push"*)   GIT_MELODY="windows_xp" ;;
        esac
        if [ -n "$GIT_MELODY" ]; then
            setsid "$SCRIPT_DIR/play-melody.sh" "$GIT_MELODY" &>/dev/null &
            disown
        fi
    fi
fi

# 無需狀態切換則退出
if [ -z "$NEW_STATE" ]; then
    exit 0
fi

# ─── 智慧抑制 ─────────────────────────────────────────

CURRENT_STATE=""
if [ -f "$STATE_FILE" ]; then
    CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null | head -1)
fi

# WAITING 中收到 COMPLETED → 忽略（使用者還沒回應，不該切走）
if [ "$CURRENT_STATE" = "WAITING" ] && [ "$NEW_STATE" = "COMPLETED" ]; then
    exit 0
fi

# ─── 2 秒去重 ─────────────────────────────────────────

DEDUP_FILE="/tmp/claude-led-dedup"
NOW=$(date +%s)

if [ "$CURRENT_STATE" = "$NEW_STATE" ] && [ -f "$DEDUP_FILE" ]; then
    LAST_TIME=$(cat "$DEDUP_FILE" 2>/dev/null | head -1)
    if [ -n "$LAST_TIME" ]; then
        DIFF=$((NOW - LAST_TIME))
        if [ "$DIFF" -lt 2 ]; then
            exit 0
        fi
    fi
fi

# 更新去重時間戳
echo "$NOW" > "$DEDUP_FILE"

# ─── 狀態切換 ─────────────────────────────────────────

echo "$NEW_STATE" > "$STATE_FILE"

# RUNNING 時清除 idle-pending（新訊息進來，取消回 idle 計時）
if [ "$NEW_STATE" = "RUNNING" ]; then
    rm -f "$IDLE_PENDING"
fi

# 發送 LED 燈效（狀態名轉小寫作為 notify.sh 的 key）
LED_KEY=$(echo "$NEW_STATE" | tr '[:upper:]' '[:lower:]')
"$SCRIPT_DIR/notify.sh" "$LED_KEY"

# ─── Stop 後自動回 IDLE ──────────────────────────────

if [ "$EVENT" = "Stop" ]; then
    (
        # Rainbow 3輪×7色×1秒=21秒，等 22 秒後自動切 IDLE
        touch "$IDLE_PENDING"
        sleep 22
        if [ -f "$IDLE_PENDING" ]; then
            echo "IDLE" > "$STATE_FILE"
            "$SCRIPT_DIR/notify.sh" idle
        fi
    ) &
    disown
fi

exit 0
