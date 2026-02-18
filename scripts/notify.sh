#!/bin/bash
# notify.sh - 純 MQTT LED + 旋律發送器（無狀態邏輯）
# 用法: notify.sh <state>
#
# 從 led-effects.json 查詢燈效與旋律設定，透過 MQTT 發佈到 RPi5。
# 所有狀態邏輯由 claude-hook.sh 管理。

STATE="$1"

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

EFFECT=$(jq -c --arg state "$STATE" '.[$state] // empty' "$EFFECTS_FILE")

if [ -n "$EFFECT" ]; then
    # 發送 LED 燈效
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "claude/led" \
        -m "$EFFECT" \
        2>/dev/null &

    # 在 HP 電腦播放旋律（如果有設定）
    MELODY=$(echo "$EFFECT" | jq -r '.melody // empty')
    if [ -n "$MELODY" ]; then
        "$SCRIPT_DIR/play-melody.sh" "$MELODY" &
    fi
fi

exit 0
