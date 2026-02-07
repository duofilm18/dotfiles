#!/bin/bash
# notify.sh - 單一通知入口（DRY）
# 用法: notify.sh <event_type> [title] [body]
#
# 透過 MQTT 發佈到 rpi5b，由 subscriber 各自處理：
#   claude/notify → mqtt-ntfy → ntfy（手機推播）
#   claude/led    → mqtt-led  → GPIO（燈效）

EVENT_TYPE="$1"
TITLE="$2"
BODY="$3"

if [ -z "$EVENT_TYPE" ]; then
    exit 0
fi

SCRIPT_DIR="$(dirname "$0")"
EFFECTS_FILE="$SCRIPT_DIR/../wsl/led-effects.json"
MQTT_HOST="${MQTT_HOST:-192.168.88.10}"
MQTT_PORT="${MQTT_PORT:-1883}"

# 發送手機通知（如果有 title 和 body）
if [ -n "$TITLE" ] && [ -n "$BODY" ]; then
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "claude/notify" \
        -m "$(jq -n --arg title "$TITLE" --arg body "$BODY" '{title: $title, body: $body}')" \
        2>/dev/null &
fi

# 發送 LED 燈效（如果有對應設定）
if [ -f "$EFFECTS_FILE" ]; then
    EFFECT=$(jq -c --arg event "$EVENT_TYPE" '.[$event] // empty' "$EFFECTS_FILE")
    if [ -n "$EFFECT" ]; then
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
            -t "claude/led" \
            -m "$EFFECT" \
            2>/dev/null &
    fi
fi

exit 0
