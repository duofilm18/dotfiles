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
#   2. 主迴圈：每秒輪詢 tmux，偵測變化 → 發 MQTT retained
#   3. 閃爍 timer：idle/waiting 時每秒切換 @claude_blink
#   4. IME 訂閱：localhost:1883 ime/state → tmux @ime_state（本機 HUB，不依賴 RPi5B）
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

# 確保退出時清理所有子進程
cleanup() {
    rm -f "$PIDFILE"
    kill 0 2>/dev/null   # 殺整個進程組
}
trap cleanup EXIT
trap 'true' USR1    # ime_loop 用 USR1 喚醒主迴圈的 sleep

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/../wsl/claude-hooks.json"
EFFECTS_FILE="$SCRIPT_DIR/../wsl/led-effects.json"
IME_INTERRUPT_SECS=2

if [ -f "$CONFIG" ]; then
    MQTT_HOST=$(jq -r '.MQTT_HOST // "192.168.88.10"' "$CONFIG")
    MQTT_PORT=$(jq -r '.MQTT_PORT // "1883"' "$CONFIG")
else
    MQTT_HOST="192.168.88.10"
    MQTT_PORT="1883"
fi

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

# ── IME 訂閱（背景）──
# 純 subscriber → tmux bridge：localhost:1883 ime/state → tmux @ime_state
# 不發 LED、不寫 file，主迴圈是 claude/led 的唯一 publisher
ime_loop() {
    while true; do
        while IFS= read -r payload; do
            tmux set -g @ime_state "$payload" 2>/dev/null
            tmux refresh-client -S 2>/dev/null
            kill -USR1 $$ 2>/dev/null   # 喚醒主迴圈，立即處理 IME 變化
        done < <(mosquitto_sub -h "localhost" -p 1883 -t "ime/state" 2>/dev/null)
        sleep 3
    done
}
ime_loop &

# ── 建構 MQTT payload ──
build_payload() {
    local state="$1"
    local project="$2"
    if [ -f "$EFFECTS_FILE" ]; then
        jq -c --arg state "$state" --arg project "$project" \
            '.[$state] // empty | . + {state: $state, project: $project}' "$EFFECTS_FILE" 2>/dev/null
    fi
}

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

# ── 主迴圈：輪詢 tmux → 發 MQTT（唯一 publisher）──
# @ime_state 變化由主迴圈偵測（同 thread），epoch-based 無 race
declare -A prev_states
declare -A prev_projects
prev_ime=""
ime_interrupt_epoch=0
ime_was_active=false

while true; do
    now=$(date +%s)

    # ── 偵測 @ime_state 變化（主迴圈內，無 race）──
    cur_ime=$(tmux show -gv @ime_state 2>/dev/null || true)
    if [ -n "$cur_ime" ] && [ "$cur_ime" != "$prev_ime" ]; then
        # 首次讀取（startup guard）不觸發 LED
        if [ -n "$prev_ime" ]; then
            ime_interrupt_epoch=$now
            led_payload=$(build_payload "ime_$cur_ime" "")
            if [ -n "$led_payload" ]; then
                mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
                    -t "claude/led" -m "$led_payload" 2>/dev/null &
            fi
        fi
        prev_ime="$cur_ime"
    fi

    # IME 中斷活躍？
    ime_active=$(( now - ime_interrupt_epoch < IME_INTERRUPT_SECS ))

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

    if [ "$ime_active" -eq 1 ]; then
        # IME 中斷活躍：跳過 Claude publish，保留 prev_states 不更新
        ime_was_active=true
    else
        # IME 中斷剛過期：清 prev_states 強制重發 Claude 狀態
        if [ "$ime_was_active" = true ]; then
            unset prev_states
            declare -A prev_states
            ime_was_active=false
        fi
        # 偵測狀態變化 → 發 MQTT
        for project in "${!current_states[@]}"; do
            state="${current_states[$project]}"
            if [ "${prev_states[$project]:-}" != "$state" ]; then
                payload=$(build_payload "$state" "$project")
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
    fi

    unset current_states
    unset current_projects

    sleep 1 & wait $! 2>/dev/null || true   # USR1 可中斷，IME 即時喚醒
done
