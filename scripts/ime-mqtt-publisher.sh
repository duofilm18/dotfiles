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

# 防止重複啟動（殺舊進程組，確保乾淨接管）
PIDFILE="/tmp/ime-mqtt-publisher.pid"
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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/../wsl/claude-hooks.json"

if [ -f "$CONFIG" ]; then
    MQTT_HOST=$(jq -r '.MQTT_HOST // "192.168.88.10"' "$CONFIG")
    MQTT_PORT=$(jq -r '.MQTT_PORT // "1883"' "$CONFIG")
else
    MQTT_HOST="192.168.88.10"
    MQTT_PORT="1883"
fi

IME_STATE_FILE="/mnt/c/Temp/ime_state"

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
            payload=$(jq -cn --arg state "$cur" '{domain: "ime", state: $state, project: ""}')
            mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
                -t "claude/led" -m "$payload" 2>/dev/null || true
        fi
        prev="$cur"
    fi
    sleep 0.2
done
