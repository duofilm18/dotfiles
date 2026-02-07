#!/bin/bash
# test-mqtt.sh - 測試 MQTT 通知系統（LED + ntfy）
# 用法: test-mqtt.sh [led|ntfy|buzzer|all]

MQTT_HOST="${MQTT_HOST:-192.168.88.10}"
MQTT_PORT="${MQTT_PORT:-1883}"

case "${1:-all}" in
    led)
        echo "🟢 測試 LED（綠燈持續閃爍，Ctrl+C 停止）..."
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t claude/led \
            -m '{"r":0,"g":255,"b":0,"pattern":"blink","times":999}'
        ;;
    ntfy)
        echo "📱 測試手機通知..."
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t claude/notify \
            -m '{"title":"測試通知","body":"MQTT ntfy 正常運作"}'
        ;;
    buzzer)
        echo "🔔 測試蜂鳴器..."
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t claude/buzzer \
            -m '{"frequency":1000,"duration":500}'
        ;;
    off)
        echo "⬛ 關燈..."
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t claude/led \
            -m '{"r":0,"g":0,"b":0,"pattern":"solid","duration":1}'
        ;;
    all)
        echo "=== MQTT 通知系統測試 ==="
        echo "MQTT: $MQTT_HOST:$MQTT_PORT"
        echo ""
        "$0" ntfy
        sleep 1
        "$0" led
        echo "（5 秒後關燈）"
        sleep 5
        "$0" off
        echo ""
        echo "✅ 測試完成"
        ;;
    *)
        echo "用法: $0 [led|ntfy|buzzer|off|all]"
        exit 1
        ;;
esac
