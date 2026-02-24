#!/bin/bash
# ============================================
# RPi5B 系統狀態 → MQTT publisher
# ============================================
#
# 每 5 秒讀取 CPU 溫度 + RAM 用量，publish 到 system/stats (retained)
#
# 手動測試：
#   bash /root/dotfiles/rpi5b/scripts/mqtt-sysstat.sh
#   mosquitto_sub -h 192.168.88.10 -t "system/stats" -C 1
#
# ============================================

BROKER="${MQTT_BROKER:-localhost}"
TOPIC="system/stats"
INTERVAL=5

while true; do
    # 溫度（整數 °C）
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP=$((TEMP_RAW / 1000))

    # RAM 用量（整數 %）
    RAM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    RAM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    RAM_PCT=$(( (RAM_TOTAL - RAM_AVAIL) * 100 / RAM_TOTAL ))

    mosquitto_pub -h "$BROKER" -t "$TOPIC" -r \
        -m "{\"temp\":${TEMP},\"ram\":${RAM_PCT}}"

    sleep "$INTERVAL"
done
