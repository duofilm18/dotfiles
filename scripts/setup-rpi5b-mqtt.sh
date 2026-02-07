#!/bin/bash
# setup-rpi5b-mqtt.sh - 部署 MQTT 服務到 rpi5b
# 安裝 mosquitto + mqtt-led + mqtt-ntfy

set -e

RPI_HOST="${RPI_HOST:-192.168.88.10}"
RPI_USER="${RPI_USER:-duofilm}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES="$SCRIPT_DIR/.."

echo "=== 部署 MQTT 服務到 $RPI_USER@$RPI_HOST ==="

# 1. 安裝 mosquitto
echo "📦 安裝 mosquitto MQTT broker..."
ssh "$RPI_USER@$RPI_HOST" "sudo apt-get update -qq && sudo apt-get install -y -qq mosquitto mosquitto-clients"

# 設定 mosquitto 允許區網連線
ssh "$RPI_USER@$RPI_HOST" "sudo tee /etc/mosquitto/conf.d/local.conf > /dev/null" <<'MQTTCONF'
listener 1883
allow_anonymous true
MQTTCONF

ssh "$RPI_USER@$RPI_HOST" "sudo systemctl enable mosquitto && sudo systemctl restart mosquitto"
echo "✅ mosquitto 已啟動 (port 1883)"

# 2. 部署 mqtt-led
echo ""
echo "📁 部署 mqtt-led..."
REMOTE_LED="/home/$RPI_USER/mqtt-led"
ssh "$RPI_USER@$RPI_HOST" "mkdir -p $REMOTE_LED"
scp "$DOTFILES/rpi5b/mqtt-led/mqtt_led.py" "$DOTFILES/rpi5b/mqtt-led/requirements.txt" "$RPI_USER@$RPI_HOST:$REMOTE_LED/"

if [ -f "$DOTFILES/rpi5b/mqtt-led/config.json" ]; then
    scp "$DOTFILES/rpi5b/mqtt-led/config.json" "$RPI_USER@$RPI_HOST:$REMOTE_LED/"
else
    scp "$DOTFILES/rpi5b/mqtt-led/config.json.example" "$RPI_USER@$RPI_HOST:$REMOTE_LED/config.json"
    echo "⚠️  使用預設 LED config，請到 rpi5b 確認 GPIO 接線"
fi

ssh "$RPI_USER@$RPI_HOST" "cd $REMOTE_LED && pip3 install -r requirements.txt --break-system-packages 2>/dev/null || pip3 install -r requirements.txt"

# 3. 部署 mqtt-ntfy
echo ""
echo "📁 部署 mqtt-ntfy..."
REMOTE_NTFY="/home/$RPI_USER/mqtt-ntfy"
ssh "$RPI_USER@$RPI_HOST" "mkdir -p $REMOTE_NTFY"
scp "$DOTFILES/rpi5b/mqtt-ntfy/mqtt_ntfy.py" "$DOTFILES/rpi5b/mqtt-ntfy/requirements.txt" "$RPI_USER@$RPI_HOST:$REMOTE_NTFY/"

if [ -f "$DOTFILES/rpi5b/mqtt-ntfy/config.json" ]; then
    scp "$DOTFILES/rpi5b/mqtt-ntfy/config.json" "$RPI_USER@$RPI_HOST:$REMOTE_NTFY/"
else
    scp "$DOTFILES/rpi5b/mqtt-ntfy/config.json.example" "$RPI_USER@$RPI_HOST:$REMOTE_NTFY/config.json"
    echo "⚠️  使用預設 ntfy config，請到 rpi5b 確認 ntfy URL"
fi

ssh "$RPI_USER@$RPI_HOST" "cd $REMOTE_NTFY && pip3 install -r requirements.txt --break-system-packages 2>/dev/null || pip3 install -r requirements.txt"

# 4. 設定 systemd services
echo ""
echo "⚙️  設定 systemd services..."

ssh "$RPI_USER@$RPI_HOST" "sudo tee /etc/systemd/system/mqtt-led.service > /dev/null" <<EOF
[Unit]
Description=MQTT LED Service - GPIO Control
After=mosquitto.service
Requires=mosquitto.service

[Service]
Type=simple
User=$RPI_USER
WorkingDirectory=$REMOTE_LED
ExecStart=/usr/bin/python3 $REMOTE_LED/mqtt_led.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

ssh "$RPI_USER@$RPI_HOST" "sudo tee /etc/systemd/system/mqtt-ntfy.service > /dev/null" <<EOF
[Unit]
Description=MQTT ntfy Bridge
After=mosquitto.service
Requires=mosquitto.service

[Service]
Type=simple
User=$RPI_USER
WorkingDirectory=$REMOTE_NTFY
ExecStart=/usr/bin/python3 $REMOTE_NTFY/mqtt_ntfy.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 5. 啟動
ssh "$RPI_USER@$RPI_HOST" "sudo systemctl daemon-reload && sudo systemctl enable mqtt-led mqtt-ntfy && sudo systemctl restart mqtt-led mqtt-ntfy"

# 6. 檢查狀態
echo ""
echo "=== 服務狀態 ==="
ssh "$RPI_USER@$RPI_HOST" "sudo systemctl status mosquitto mqtt-led mqtt-ntfy --no-pager -l" || true

echo ""
echo "✅ 部署完成！"
echo ""
echo "測試指令（在 WSL 執行）："
echo "  # 測試 LED"
echo "  mosquitto_pub -h $RPI_HOST -t claude/led -m '{\"r\":0,\"g\":255,\"b\":0,\"pattern\":\"blink\",\"times\":2}'"
echo "  # 測試通知"
echo "  mosquitto_pub -h $RPI_HOST -t claude/notify -m '{\"title\":\"測試\",\"body\":\"MQTT 通知正常\"}'"
