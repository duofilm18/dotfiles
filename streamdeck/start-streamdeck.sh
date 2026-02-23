#!/usr/bin/env bash
# Stream Deck MQTT Monitor 啟動腳本（WSL 用）
# 自動處理：usbipd attach → hidraw 權限 → 啟動腳本
set -euo pipefail

USBIPD="/mnt/c/Program Files/usbipd-win/usbipd.exe"
BUSID="2-1"  # Stream Deck XL
VENV="/home/duofilm/StreamController/.venv/bin/python3"
SCRIPT="/home/duofilm/dotfiles/streamdeck/streamdeck_mqtt.py"

# 1. USB attach（已 attached 就跳過）
if ! ls /dev/hidraw0 &>/dev/null; then
    echo "Attaching Stream Deck USB (busid=$BUSID)..."
    "$USBIPD" attach --wsl --busid "$BUSID" 2>&1 || true
    # 等待 hidraw 裝置出現
    for i in {1..10}; do
        ls /dev/hidraw0 &>/dev/null && break
        sleep 1
    done
    if ! ls /dev/hidraw0 &>/dev/null; then
        echo "ERROR: /dev/hidraw0 not found after attach"
        exit 1
    fi
fi

# 2. 修正權限（udev 規則生效後可移除此段）
if [ ! -w /dev/hidraw0 ]; then
    echo "Fixing /dev/hidraw0 permissions..."
    sudo chmod 666 /dev/hidraw0
fi

# 3. 殺掉舊的 instance
pkill -f "streamdeck_mqtt.py" 2>/dev/null || true
sleep 1

# 4. 啟動
echo "Starting Stream Deck MQTT Monitor..."
exec "$VENV" -u "$SCRIPT"
