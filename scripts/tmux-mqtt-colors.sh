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

# 防止重複啟動（殺舊進程組，確保乾淨接管）
PIDFILE="/tmp/tmux-mqtt-colors.pid"
if [ -f "$PIDFILE" ]; then
    OLD_PID="$(cat "$PIDFILE")"
    if [ "$$" != "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill -- -"$OLD_PID" 2>/dev/null   # 殺整個舊進程組
        sleep 0.2
    fi
fi
echo $$ > "$PIDFILE"

# 確保退出時清理所有子進程（blink_loop + mosquitto_sub）
cleanup() {
    rm -f "$PIDFILE"
    kill 0 2>/dev/null   # 殺整個進程組
}
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/../wsl/claude-hooks.json"

if [ -f "$CONFIG" ]; then
    MQTT_HOST=$(jq -r '.MQTT_HOST // "192.168.88.10"' "$CONFIG")
    MQTT_PORT=$(jq -r '.MQTT_PORT // "1883"' "$CONFIG")
else
    MQTT_HOST="192.168.88.10"
    MQTT_PORT="1883"
fi

# ── 閃爍 timer + 清理過期 retained（背景）──
# idle/waiting 狀態時，每秒切換 @claude_blink on/off
# 同時追蹤活躍 @project，window 關閉時清掉 MQTT retained 訊息
blink_loop() {
    local prev_projects=""
    local tick=0
    while true; do
        # 閃爍邏輯
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
        tmux refresh-client -S 2>/dev/null

        # 每 5 秒檢查一次：清理已關閉 window 的 MQTT retained 訊息
        tick=$(( (tick + 1) % 5 ))
        if [ "$tick" -eq 0 ]; then
            current_projects=$(tmux list-windows -F '#{@project}' 2>/dev/null | grep -v '^$' | sort -u)
            for proj in $prev_projects; do
                if ! echo "$current_projects" | grep -qx "$proj"; then
                    mosquitto_pub -r -h "$MQTT_HOST" -p "$MQTT_PORT" -t "claude/led/$proj" -n 2>/dev/null &
                fi
            done
            prev_projects="$current_projects"
        fi

        sleep 1
    done
}

blink_loop &

# ── MQTT 訂閱 ──
mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "claude/led/+" -t "ime/state" -v 2>/dev/null | while IFS= read -r line; do
    topic="${line%% *}"
    payload="${line#* }"

    # IME 狀態 → tmux 全域變數（事件驅動，零讀取成本）
    if [ "$topic" = "ime/state" ]; then
        tmux set -g @ime_state "$payload" 2>/dev/null
        tmux refresh-client -S 2>/dev/null
        continue
    fi

    # Claude 狀態 → 對應 window
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
