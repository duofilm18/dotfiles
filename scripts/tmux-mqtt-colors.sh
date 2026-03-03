#!/bin/bash
# tmux-mqtt-colors.sh - State Publisher（tmux → MQTT 單向資料流）
#
# 以 tmux @claude_state 為 single source of truth，
# 輪詢 tmux window 狀態並發佈到 MQTT，取代舊的 MQTT→tmux 反向流。
#
# 資料流:
#   Hook → tmux @claude_state → [本腳本] → MQTT → { Stream Deck, LED }
#
# 功能:
#   1. 啟動清理：清除所有 MQTT retained 訊息，從 tmux 重建
#   2. 主迴圈：每秒輪詢 tmux，偵測變化 → 發 MQTT retained（Claude domain only）
#   3. 閃爍 timer：idle/waiting 時每秒切換 @claude_blink
#   4. IME 讀檔：輪詢 /mnt/c/Temp/ime_state → tmux @ime_state（tmux status bar 用）
#
# IME→MQTT 由獨立的 ime-mqtt-publisher.sh 負責（不依賴 tmux）
#
# 用法: 由 .tmux.conf run-shell -b 自動啟動

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/pidfile.sh"
source "$SCRIPT_DIR/lib/mqtt.sh"

pidfile_acquire "/tmp/tmux-mqtt-colors.pid"
load_mqtt_config

# ── 啟動清理：清除所有 MQTT retained 訊息 ──
# 訂閱 claude/led/+ 取得所有 retained topic，逐一清除
# State Publisher 隨即從 tmux 重建正確狀態
startup_cleanup() {
    # 清除全域 topic
    mosquitto_pub -r -h "$MQTT_HOST" -p "$MQTT_PORT" -t "claude/led" -n 2>/dev/null || true

    # 收集所有 retained 的專案 topic 並清除
    mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "claude/led/+" -W 2 -v 2>/dev/null | while IFS= read -r line; do
        topic="${line%% *}"
        mosquitto_pub -r -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$topic" -n 2>/dev/null || true
    done
}
# 同步執行清理，完成後再進入主迴圈（避免與主迴圈的 publish 競爭）
startup_cleanup

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
        tmux refresh-client -S 2>/dev/null
        sleep 1
    done
}
blink_loop &

# ── IME 讀檔（背景）──
# 輪詢 IME_STATE_FILE（來自 lib/mqtt.sh）→ tmux @ime_state
# 不依賴 MQTT，install.ps1 更新 IME_Indicator 不影響 tmux
ime_loop() {
    local prev=""
    while true; do
        cur=$(cat "$IME_STATE_FILE" 2>/dev/null || echo "")
        if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then
            tmux set -g @ime_state "$cur" 2>/dev/null
            tmux refresh-client -S 2>/dev/null
            prev="$cur"
        fi
        sleep 0.2
    done
}
ime_loop &

# build_payload() 來自 lib/mqtt.sh

# ── 狀態優先序（同名專案取最需關注的） ──
state_priority() {
    case "$1" in
        waiting)   echo 6 ;;
        error)     echo 5 ;;
        idle)      echo 4 ;;
        running)   echo 3 ;;
        completed) echo 2 ;;
        off)       echo 1 ;;
        *)         echo 0 ;;
    esac
}

# ── 主迴圈：輪詢 tmux → 發 MQTT（Claude domain only）──
# IME→MQTT 由獨立的 ime-mqtt-publisher.sh 負責
declare -A prev_states
declare -A prev_projects

while true; do
    # 收集當前所有 window 的狀態
    declare -A current_states
    declare -A current_projects

    while read -r idx project state; do
        if [ -n "$project" ] && [ -n "$state" ]; then
            existing="${current_states[$project]:-}"
            if [ -z "$existing" ] || [ "$(state_priority "$state")" -gt "$(state_priority "$existing")" ]; then
                current_states["$project"]="$state"
                current_projects["$project"]="$idx"
            fi
        fi
    done < <(tmux list-windows -F '#{window_index} #{@project} #{@claude_state}' 2>/dev/null)

    # 偵測狀態變化 → 發 MQTT
    for project in "${!current_states[@]}"; do
        state="${current_states[$project]}"
        if [ "${prev_states[$project]:-}" != "$state" ]; then
            payload=$(build_payload "claude" "$state" "$project")
            if [ -n "$payload" ]; then
                # 發到專案 topic（Stream Deck）+ 全域 topic（RPi5B LED）
                mosquitto_pub -r -h "$MQTT_HOST" -p "$MQTT_PORT" \
                    -t "claude/led/$project" -m "$payload" 2>/dev/null &
                mosquitto_pub -r -h "$MQTT_HOST" -p "$MQTT_PORT" \
                    -t "claude/led" -m "$payload" 2>/dev/null &
            fi
        fi
    done

    # 偵測 window 消失 → 清除 MQTT retained
    for project in "${!prev_states[@]}"; do
        if [ -z "${current_states[$project]:-}" ]; then
            mosquitto_pub -r -h "$MQTT_HOST" -p "$MQTT_PORT" \
                -t "claude/led/$project" -n 2>/dev/null &
        fi
    done

    # 更新前一次狀態
    unset prev_states
    declare -A prev_states
    for project in "${!current_states[@]}"; do
        prev_states["$project"]="${current_states[$project]}"
    done

    unset prev_projects
    declare -A prev_projects
    for project in "${!current_projects[@]}"; do
        prev_projects["$project"]="${current_projects[$project]}"
    done

    unset current_states
    unset current_projects

    sleep 1
done
