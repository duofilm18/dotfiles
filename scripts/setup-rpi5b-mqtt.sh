#!/bin/bash
# setup-rpi5b-mqtt.sh - 部署 MQTT 服務到 rpi5b
# 安裝 mosquitto + mqtt-led + mqtt-ntfy
#
# 已驗證環境：Armbian 25.11.2 trixie (Debian 13) / RPi5 / Python 3.13
#
# 注意事項：
#   - lgpio 需從原始碼編譯（Armbian 套件庫沒有 python3-lgpio）
#   - gpiozero 需升級到 2.0.1+（apt 版 1.6.2 與編譯的 lgpio 不相容）
#   - RPi5 用 RP1 晶片，舊的 RPi.GPIO 不支援，必須用 lgpio 後端

set -e

RPI_HOST="${RPI_HOST:-192.168.88.10}"
RPI_USER="${RPI_USER:-root}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES="$SCRIPT_DIR/.."

echo "=== 部署 MQTT 服務到 $RPI_USER@$RPI_HOST ==="

# 取得遠端 home 目錄（root 的 home 是 /root 不是 /home/root）
REMOTE_HOME=$(ssh "$RPI_USER@$RPI_HOST" "echo \$HOME")
echo "遠端 HOME: $REMOTE_HOME"

# 1. 安裝系統套件
echo ""
echo "📦 安裝系統套件..."
ssh "$RPI_USER@$RPI_HOST" "sudo apt-get update -qq && sudo apt-get install -y -qq \
    mosquitto mosquitto-clients \
    python3-pip python3-dev python3-setuptools \
    python3-paho-mqtt python3-requests python3-gpiozero \
    gpiod \
    swig cmake build-essential git"

# 設定 mosquitto 允許區網連線
ssh "$RPI_USER@$RPI_HOST" "sudo tee /etc/mosquitto/conf.d/local.conf > /dev/null" <<'MQTTCONF'
listener 1883
allow_anonymous true
MQTTCONF

ssh "$RPI_USER@$RPI_HOST" "sudo systemctl enable mosquitto && sudo systemctl restart mosquitto"
echo "✅ mosquitto 已啟動 (port 1883)"

# 2. 編譯安裝 lgpio（Armbian 沒有 python3-lgpio 套件）
echo ""
echo "🔧 編譯 lgpio（RPi5 GPIO 支援）..."
ssh "$RPI_USER@$RPI_HOST" "cd /tmp && rm -rf lg && git clone --depth 1 https://github.com/joan2937/lg.git && cd lg && make && sudo make install"
echo "✅ lgpio C 函式庫 + Python 綁定已安裝"

# 升級 gpiozero 到 2.0.1+（apt 版 1.6.2 與 lgpio 常數不相容）
echo ""
echo "📦 升級 gpiozero 到相容版本..."
ssh "$RPI_USER@$RPI_HOST" "pip3 install --break-system-packages --upgrade gpiozero"

# 3. 部署 mqtt-led
echo ""
echo "📁 部署 mqtt-led..."
REMOTE_LED="$REMOTE_HOME/mqtt-led"
ssh "$RPI_USER@$RPI_HOST" "mkdir -p $REMOTE_LED"
scp "$DOTFILES/rpi5b/mqtt-led/mqtt_led.py" "$DOTFILES/rpi5b/mqtt-led/requirements.txt" "$RPI_USER@$RPI_HOST:$REMOTE_LED/"

if [ -f "$DOTFILES/rpi5b/mqtt-led/config.json" ]; then
    scp "$DOTFILES/rpi5b/mqtt-led/config.json" "$RPI_USER@$RPI_HOST:$REMOTE_LED/"
else
    scp "$DOTFILES/rpi5b/mqtt-led/config.json.example" "$RPI_USER@$RPI_HOST:$REMOTE_LED/config.json"
    echo "⚠️  使用預設 LED config，請到 rpi5b 確認 GPIO 接線"
fi

ssh "$RPI_USER@$RPI_HOST" "cd $REMOTE_LED && pip3 install --break-system-packages -r requirements.txt"

# 4. 部署 mqtt-ntfy
echo ""
echo "📁 部署 mqtt-ntfy..."
REMOTE_NTFY="$REMOTE_HOME/mqtt-ntfy"
ssh "$RPI_USER@$RPI_HOST" "mkdir -p $REMOTE_NTFY"
scp "$DOTFILES/rpi5b/mqtt-ntfy/mqtt_ntfy.py" "$DOTFILES/rpi5b/mqtt-ntfy/requirements.txt" "$RPI_USER@$RPI_HOST:$REMOTE_NTFY/"

if [ -f "$DOTFILES/rpi5b/mqtt-ntfy/config.json" ]; then
    scp "$DOTFILES/rpi5b/mqtt-ntfy/config.json" "$RPI_USER@$RPI_HOST:$REMOTE_NTFY/"
else
    scp "$DOTFILES/rpi5b/mqtt-ntfy/config.json.example" "$RPI_USER@$RPI_HOST:$REMOTE_NTFY/config.json"
    echo "⚠️  使用預設 ntfy config，請到 rpi5b 確認 ntfy URL"
fi

ssh "$RPI_USER@$RPI_HOST" "cd $REMOTE_NTFY && pip3 install --break-system-packages -r requirements.txt"

# 5. 設定 systemd services
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
Environment=GPIOZERO_PIN_FACTORY=lgpio
Environment=PYTHONUNBUFFERED=1
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
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 $REMOTE_NTFY/mqtt_ntfy.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 6. 啟動
ssh "$RPI_USER@$RPI_HOST" "sudo systemctl daemon-reload && sudo systemctl enable mqtt-led mqtt-ntfy && sudo systemctl restart mqtt-led mqtt-ntfy"

# 7. 檢查狀態
echo ""
echo "=== 服務狀態 ==="
ssh "$RPI_USER@$RPI_HOST" "sudo systemctl status mosquitto mqtt-led mqtt-ntfy --no-pager -l" || true

echo ""
echo "✅ 部署完成！"
echo ""
echo "測試指令（在 WSL 執行）："
echo "  ~/dotfiles/scripts/test-mqtt.sh"
