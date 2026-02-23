#!/bin/bash
# notify.sh - 手動 MQTT LED 測試工具
# 用法: notify.sh <state> [project]
#   例: notify.sh running dotfiles
#
# ⚠️ 已不再被 hook 系統呼叫。
# 正式資料流改由 State Publisher (tmux-mqtt-colors.sh) 負責：
#   Hook → tmux @claude_state → State Publisher → MQTT
#
# 保留此腳本供手動測試 MQTT LED 燈效。

STATE="$1"
PROJECT="${2:-default}"

if [ -z "$STATE" ]; then
    exit 0
fi

SCRIPT_DIR="$(dirname "$0")"
EFFECTS_FILE="$SCRIPT_DIR/../wsl/led-effects.json"
MQTT_HOST="${MQTT_HOST:-192.168.88.10}"
MQTT_PORT="${MQTT_PORT:-1883}"

if [ ! -f "$EFFECTS_FILE" ]; then
    exit 0
fi

EFFECT=$(jq -c --arg state "$STATE" --arg project "$PROJECT" \
    '.[$state] // empty | . + {state: $state, project: $project}' "$EFFECTS_FILE")

if [ -n "$EFFECT" ]; then
    # 發送 LED 燈效（-r retain：RPi5 重連後自動取得最新狀態）
    # 同時發到通用 topic（RPi5B LED）和專案 topic（Stream Deck）
    mosquitto_pub -r -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "claude/led" \
        -m "$EFFECT" \
        2>/dev/null &
    mosquitto_pub -r -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "claude/led/$PROJECT" \
        -m "$EFFECT" \
        2>/dev/null &
fi

exit 0
