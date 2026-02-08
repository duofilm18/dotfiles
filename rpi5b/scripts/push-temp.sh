#!/bin/bash
# ============================================
# 推送系統狀態到 Uptime Kuma（三個監控）
# ============================================
#
# 監控項目：
#   - 溫度 > 70°C → 警報
#   - CPU  > 80%  → 警報
#   - RAM  > 90%  → 警報
#
# 自動執行：
#   crontab -e
#   * * * * * /root/dotfiles/rpi5b/scripts/push-temp.sh
#
# ⚠️ Push URLs 包含 API token，部署後請更新！
#
# ============================================

# === Push URLs（部署後請更新） ===
URL_TEMP="${UPTIME_KUMA_URL_TEMP:-http://192.168.88.10:3001/api/push/CHANGE_ME}"
URL_CPU="${UPTIME_KUMA_URL_CPU:-http://192.168.88.10:3001/api/push/CHANGE_ME}"
URL_RAM="${UPTIME_KUMA_URL_RAM:-http://192.168.88.10:3001/api/push/CHANGE_ME}"

# === 警報閾值 ===
TEMP_WARN=70    # 溫度超過 70°C
CPU_WARN=80     # CPU 超過 80%
RAM_WARN=90     # RAM 超過 90%

# === 讀取溫度 ===
TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
TEMP=$((TEMP_RAW / 1000))

# === 讀取 CPU 使用率 ===
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}')

# === 讀取 RAM 使用率 ===
RAM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
RAM_USED=$((RAM_TOTAL - RAM_AVAIL))
RAM_PCT=$((RAM_USED * 100 / RAM_TOTAL))

# === 讀取 CPU 頻率 (附加資訊) ===
FREQ_RAW=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo "0")
FREQ=$((FREQ_RAW / 1000))

# === 推送溫度 ===
if [ "$TEMP" -ge "$TEMP_WARN" ]; then
    STATUS_TEMP="down"
else
    STATUS_TEMP="up"
fi
curl -s "${URL_TEMP}?status=${STATUS_TEMP}&msg=${TEMP}C&ping=${TEMP}" > /dev/null

# === 推送 CPU ===
if [ "$CPU" -ge "$CPU_WARN" ]; then
    STATUS_CPU="down"
else
    STATUS_CPU="up"
fi
curl -s "${URL_CPU}?status=${STATUS_CPU}&msg=${CPU}%&ping=${CPU}" > /dev/null

# === 推送 RAM ===
if [ "$RAM_PCT" -ge "$RAM_WARN" ]; then
    STATUS_RAM="down"
else
    STATUS_RAM="up"
fi
curl -s "${URL_RAM}?status=${STATUS_RAM}&msg=${RAM_PCT}%&ping=${RAM_PCT}" > /dev/null
