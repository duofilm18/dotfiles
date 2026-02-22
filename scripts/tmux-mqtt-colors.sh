#!/bin/bash
# tmux-mqtt-colors.sh - MQTT 訂閱者，自動更新 tmux tab 狀態指示器
#
# 訂閱 claude/led/+ topic，根據 Claude Code 狀態
# 更新對應 tmux window 的 @claude_state 選項。
# 搭配 .tmux.conf 的 window-status-format 顯示彩色 tab。
#
# 功能:
#   1. MQTT 訂閱：接收狀態變更，設定 @claude_state
#   2. 閃爍 timer：idle/waiting 時每秒切換 @claude_blink（橘白互跳）
#
# 用法: 由 .tmux.conf run-shell -b 自動啟動

# 防止重複啟動
PIDFILE="/tmp/tmux-mqtt-colors.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/../wsl/claude-hooks.json"

if [ -f "$CONFIG" ]; then
    MQTT_HOST=$(jq -r '.MQTT_HOST // "192.168.88.10"' "$CONFIG")
    MQTT_PORT=$(jq -r '.MQTT_PORT // "1883"' "$CONFIG")
else
    MQTT_HOST="192.168.88.10"
    MQTT_PORT="1883"
fi

# ── 閃爍 timer（背景）──
# idle/waiting 狀態時，每秒切換 @claude_blink on/off
blink_loop() {
    while true; do
        tmux list-windows -F '#{window_index} #{@claude_state} #{@claude_blink}' 2>/dev/null | while read -r idx state blink; do
            case "$state" in
                idle|waiting)
                    if [ "$blink" = "on" ]; then
                        tmux set-window-option -t ":$idx" @claude_blink "off" 2>/dev/null
                    else
                        tmux set-window-option -t ":$idx" @claude_blink "on" 2>/dev/null
                    fi
                    ;;
                *)
                    [ -n "$blink" ] && tmux set-window-option -t ":$idx" @claude_blink "" 2>/dev/null
                    ;;
            esac
        done
        sleep 1
    done
}

blink_loop &
BLINK_PID=$!
trap 'rm -f "$PIDFILE"; kill $BLINK_PID 2>/dev/null' EXIT

# ── MQTT 訂閱 ──
mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "claude/led/+" -v 2>/dev/null | while IFS= read -r line; do
    # -v 格式: "claude/led/project {json}"
    topic="${line%% *}"
    payload="${line#* }"
    project="${topic##*/}"
    state=$(echo "$payload" | jq -r '.state // empty' 2>/dev/null)

    [ -z "$project" ] || [ -z "$state" ] && continue

    # 找 @project 匹配的 tmux window，更新 @claude_state
    tmux list-windows -F '#{window_index} #{@project}' 2>/dev/null | while read -r idx proj; do
        if [ "$proj" = "$project" ]; then
            tmux set-window-option -t ":$idx" @claude_state "$state" 2>/dev/null
        fi
    done
done
