#!/bin/bash
# ime-mqtt-publisher.sh - 獨立 IME→MQTT Publisher（不依賴 tmux）
#
# 輪詢 /mnt/c/Temp/ime_state 每 200ms，變化時 publish
# {domain:"ime", state:"zh/en"} 到 MQTT claude/led（non-retained）。
#
# 資料流:
#   Windows IME_Indicator → /mnt/c/Temp/ime_state → [本腳本] → MQTT → RPi5B LED
#
# 用法: systemd user service 自動啟動（不需要 tmux）

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/pidfile.sh"
source "$SCRIPT_DIR/lib/mqtt.sh"

pidfile_acquire "/tmp/ime-mqtt-publisher.pid"
load_mqtt_config

# ── 主迴圈：輪詢 IME 狀態檔 → MQTT ──
prev=""
first_read=true

while true; do
    cur=$(cat "$IME_STATE_FILE" 2>/dev/null || echo "")
    if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then
        # Startup guard：首次讀取不 publish（避免啟動瞬間誤觸）
        if [ "$first_read" = true ]; then
            first_read=false
        else
            payload=$(build_payload "ime" "$cur" "")
            mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
                -t "claude/led" -m "$payload" 2>/dev/null || true
        fi
        prev="$cur"
    fi
    sleep 0.2
done
