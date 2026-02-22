#!/bin/bash
# claude-hook.sh - 單一入口狀態機（對齊 ESP32 5 狀態）
#
# 用法: claude-hook.sh <event> [matcher]
#   由 settings.json hooks 統一呼叫，stdin 接收 Claude hook JSON
#
# 5 狀態: IDLE / RUNNING / WAITING / COMPLETED / ERROR
# 功能: 事件→狀態映射 · 2 秒去重 · 智慧抑制 · LED 發送

set -euo pipefail

# 檔案鎖：防止多個 Hook 同時讀寫狀態檔造成競爭
exec 200>/tmp/claude-led.lock
flock -n 200 || exit 0

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
