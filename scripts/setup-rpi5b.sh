#!/bin/bash
# ============================================
# setup-rpi5b.sh - RPi5B 一鍵部署
# ============================================
#
# 從零開始部署 RPi5B 所有服務：
#   系統設定 → Pi-hole → Docker → MQTT → Tailscale → crontab
#
# 用法：~/dotfiles/scripts/setup-rpi5b.sh
#
# 需要互動的步驟會暫停提示，不會跳過。
#
# ============================================

set -e

RPI_HOST="${RPI_HOST:-192.168.88.10}"
RPI_USER="${RPI_USER:-root}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES="$SCRIPT_DIR/.."
RPI5B="$DOTFILES/rpi5b"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo ""; echo -e "${GREEN}=== $1 ===${NC}"; }

pause() {
    echo ""
    echo -e "${YELLOW}⏸️  $1${NC}"
    echo "   按 Enter 繼續，或 Ctrl+C 中斷..."
    read -r
}

# 取得遠端 home 目錄
REMOTE_HOME=$(ssh -o ConnectTimeout=5 "$RPI_USER@$RPI_HOST" "echo \$HOME")
if [ -z "$REMOTE_HOME" ]; then
    error "無法連線到 $RPI_USER@$RPI_HOST"
    exit 1
fi
info "連線成功，遠端 HOME: $REMOTE_HOME"

REMOTE_DOTFILES="$REMOTE_HOME/dotfiles"

# ============================================
# Step 1: 系統設定
# ============================================
step "Step 1/10: 系統設定（boot, fstab, log2ram, sysctl, journald, MOTD）"

# 同步 rpi5b 目錄到遠端
info "同步設定檔到 $REMOTE_DOTFILES/rpi5b/..."
ssh "$RPI_USER@$RPI_HOST" "mkdir -p $REMOTE_DOTFILES/rpi5b"
rsync -avz --delete "$RPI5B/" "$RPI_USER@$RPI_HOST:$REMOTE_DOTFILES/rpi5b/"

# 套用系統設定
info "套用 boot/config.txt..."
ssh "$RPI_USER@$RPI_HOST" "sudo cp $REMOTE_DOTFILES/rpi5b/system/boot/config.txt /boot/firmware/config.txt"

info "套用 fstab（tmpfs /tmp）..."
ssh "$RPI_USER@$RPI_HOST" "
    if ! grep -q 'tmpfs /tmp' /etc/fstab; then
        echo 'tmpfs /tmp tmpfs defaults,nosuid 0 0' | sudo tee -a /etc/fstab
    fi
"

warn "fstab 的 noatime,commit=3600 需手動修改根目錄掛載選項"
warn "參考 rpi5b/system/etc/fstab.append 的說明"

info "套用 log2ram.conf..."
ssh "$RPI_USER@$RPI_HOST" "
    if [ -f /etc/log2ram.conf ]; then
        sudo cp $REMOTE_DOTFILES/rpi5b/system/etc/log2ram.conf /etc/log2ram.conf
    else
        echo '  log2ram 未安裝，跳過'
    fi
"

info "套用 sysctl.conf..."
ssh "$RPI_USER@$RPI_HOST" "
    if ! grep -q 'vm.swappiness=100' /etc/sysctl.conf; then
        echo 'vm.swappiness=100' | sudo tee -a /etc/sysctl.conf
        sudo sysctl -p
    fi
"

info "套用 journald.conf..."
ssh "$RPI_USER@$RPI_HOST" "sudo cp $REMOTE_DOTFILES/rpi5b/system/etc/systemd/journald.conf /etc/systemd/journald.conf && sudo systemctl restart systemd-journald"

info "套用 armbian-ramlog / armbian-zram-config..."
ssh "$RPI_USER@$RPI_HOST" "
    [ -f /etc/default/armbian-ramlog ] && sudo cp $REMOTE_DOTFILES/rpi5b/system/etc/default/armbian-ramlog /etc/default/armbian-ramlog
    [ -f /etc/default/armbian-zram-config ] && sudo cp $REMOTE_DOTFILES/rpi5b/system/etc/default/armbian-zram-config /etc/default/armbian-zram-config
"

info "套用 MOTD..."
ssh "$RPI_USER@$RPI_HOST" "sudo cp $REMOTE_DOTFILES/rpi5b/system/etc/update-motd.d/36-services /etc/update-motd.d/36-services && sudo chmod +x /etc/update-motd.d/36-services"

info "Step 1 完成 ✅"

# ============================================
# Step 2: Pi-hole（需互動）
# ============================================
step "Step 2/10: Pi-hole"

if ssh "$RPI_USER@$RPI_HOST" "command -v pihole" &>/dev/null; then
    info "Pi-hole 已安裝，跳過"
else
    warn "Pi-hole 需要互動安裝"
    echo "請在 RPi 上執行："
    echo "  ssh $RPI_USER@$RPI_HOST"
    echo "  curl -sSL https://install.pi-hole.net | bash"
    pause "Pi-hole 安裝完成後按 Enter 繼續"
fi

# ============================================
# Step 3: Docker
# ============================================
step "Step 3/10: Docker"

if ssh "$RPI_USER@$RPI_HOST" "command -v docker" &>/dev/null; then
    info "Docker 已安裝，跳過"
else
    info "安裝 Docker..."
    ssh "$RPI_USER@$RPI_HOST" "curl -fsSL https://get.docker.com | sh"
fi

# ============================================
# Step 4: Docker Compose（uptime-kuma + ntfy）
# ============================================
step "Step 4/10: Docker Compose 服務（uptime-kuma + ntfy）"

info "部署 docker-compose..."
ssh "$RPI_USER@$RPI_HOST" "cd $REMOTE_DOTFILES/rpi5b/docker && docker compose up -d"
info "Step 4 完成 ✅"

# ============================================
# Step 5: Mosquitto + lgpio
# ============================================
step "Step 5/10: Mosquitto + lgpio 編譯"

info "安裝系統套件..."
ssh "$RPI_USER@$RPI_HOST" "sudo apt-get update -qq && sudo apt-get install -y -qq \
    mosquitto mosquitto-clients \
    python3-pip python3-dev python3-setuptools \
    python3-paho-mqtt python3-requests python3-gpiozero \
    gpiod \
    swig cmake build-essential git"

info "設定 mosquitto 允許區網連線..."
ssh "$RPI_USER@$RPI_HOST" "sudo tee /etc/mosquitto/conf.d/local.conf > /dev/null" <<'MQTTCONF'
listener 1883
allow_anonymous true
MQTTCONF

ssh "$RPI_USER@$RPI_HOST" "sudo systemctl enable mosquitto && sudo systemctl restart mosquitto"
info "mosquitto 已啟動 (port 1883)"

info "編譯 lgpio（RPi5 GPIO 支援）..."
ssh "$RPI_USER@$RPI_HOST" "cd /tmp && rm -rf lg && git clone --depth 1 https://github.com/joan2937/lg.git && cd lg && make && sudo make install"

info "升級 gpiozero 到 2.0.1+..."
ssh "$RPI_USER@$RPI_HOST" "pip3 install --break-system-packages --upgrade gpiozero"

info "Step 5 完成 ✅"

# ============================================
# Step 6: mqtt-led + mqtt-ntfy + systemd
# ============================================
step "Step 6/10: MQTT 服務部署（mqtt-led + mqtt-ntfy）"

REMOTE_LED="$REMOTE_HOME/mqtt-led"
REMOTE_NTFY_SVC="$REMOTE_HOME/mqtt-ntfy"

# mqtt-led
info "部署 mqtt-led..."
ssh "$RPI_USER@$RPI_HOST" "mkdir -p $REMOTE_LED"
scp "$RPI5B/mqtt-led/mqtt_led.py" "$RPI5B/mqtt-led/requirements.txt" "$RPI_USER@$RPI_HOST:$REMOTE_LED/"

if [ -f "$RPI5B/mqtt-led/config.json" ]; then
    scp "$RPI5B/mqtt-led/config.json" "$RPI_USER@$RPI_HOST:$REMOTE_LED/"
else
    scp "$RPI5B/mqtt-led/config.json.example" "$RPI_USER@$RPI_HOST:$REMOTE_LED/config.json"
    warn "使用預設 LED config，請到 rpi5b 確認 GPIO 接線"
fi

ssh "$RPI_USER@$RPI_HOST" "cd $REMOTE_LED && pip3 install --break-system-packages -r requirements.txt"

# mqtt-ntfy
info "部署 mqtt-ntfy..."
ssh "$RPI_USER@$RPI_HOST" "mkdir -p $REMOTE_NTFY_SVC"
scp "$RPI5B/mqtt-ntfy/mqtt_ntfy.py" "$RPI5B/mqtt-ntfy/requirements.txt" "$RPI_USER@$RPI_HOST:$REMOTE_NTFY_SVC/"

if [ -f "$RPI5B/mqtt-ntfy/config.json" ]; then
    scp "$RPI5B/mqtt-ntfy/config.json" "$RPI_USER@$RPI_HOST:$REMOTE_NTFY_SVC/"
else
    scp "$RPI5B/mqtt-ntfy/config.json.example" "$RPI_USER@$RPI_HOST:$REMOTE_NTFY_SVC/config.json"
    warn "使用預設 ntfy config，請到 rpi5b 確認 ntfy URL"
fi

ssh "$RPI_USER@$RPI_HOST" "cd $REMOTE_NTFY_SVC && pip3 install --break-system-packages -r requirements.txt"

# systemd services
info "設定 systemd services..."

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
WorkingDirectory=$REMOTE_NTFY_SVC
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 $REMOTE_NTFY_SVC/mqtt_ntfy.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

ssh "$RPI_USER@$RPI_HOST" "sudo systemctl daemon-reload && sudo systemctl enable mqtt-led mqtt-ntfy && sudo systemctl restart mqtt-led mqtt-ntfy"

info "Step 6 完成 ✅"

# ============================================
# Step 7: Tailscale（需手動登入）
# ============================================
step "Step 7/10: Tailscale"

if ssh "$RPI_USER@$RPI_HOST" "command -v tailscale" &>/dev/null; then
    info "Tailscale 已安裝"
    ssh "$RPI_USER@$RPI_HOST" "tailscale status" || true
else
    info "安裝 Tailscale..."
    ssh "$RPI_USER@$RPI_HOST" "curl -fsSL https://tailscale.com/install.sh | sh"
    warn "請手動執行 tailscale up 登入："
    echo "  ssh $RPI_USER@$RPI_HOST tailscale up --advertise-routes=192.168.88.0/24"
    pause "Tailscale 設定完成後按 Enter 繼續"
fi

# ============================================
# Step 8: Crontab
# ============================================
step "Step 8/10: Crontab"

info "設定 crontab..."
ssh "$RPI_USER@$RPI_HOST" "crontab -" <<'CRON'
# 每分鐘推送系統狀態到 Uptime Kuma
* * * * * /root/dotfiles/rpi5b/scripts/push-temp.sh

# 每天凌晨 2 點更新 Pi-hole 阻擋列表
0 2 * * * pihole -g

# 每週一凌晨 3 點更新 Pi-hole
0 3 * * 1 pihole -up
CRON

info "Step 8 完成 ✅"

# ============================================
# Step 9: 停用 unblock-rfkill
# ============================================
step "Step 9/10: 停用 unblock-rfkill"

ssh "$RPI_USER@$RPI_HOST" "
    if systemctl is-enabled unblock-rfkill &>/dev/null; then
        sudo systemctl disable unblock-rfkill
        sudo systemctl stop unblock-rfkill 2>/dev/null || true
        echo '已停用 unblock-rfkill'
    else
        echo 'unblock-rfkill 已停用或不存在，跳過'
    fi
"

info "Step 9 完成 ✅"

# ============================================
# Step 10: 清理舊 repo
# ============================================
step "Step 10/10: 清理舊 repo"

ssh "$RPI_USER@$RPI_HOST" "
    for dir in /root/rpi-config /root/uptime-kuma; do
        if [ -d \"\$dir\" ]; then
            echo \"移除 \$dir...\"
            rm -rf \"\$dir\"
        fi
    done
    # 舊的 /root/dotfiles（如果是不同 repo）
    if [ -d /root/dotfiles ] && [ ! -f /root/dotfiles/rpi5b/system/boot/config.txt ]; then
        echo '移除舊 /root/dotfiles...'
        rm -rf /root/dotfiles
    fi
"

info "Step 10 完成 ✅"

# ============================================
# 完成
# ============================================
echo ""
echo "============================================"
echo -e "${GREEN} 🎉 RPi5B 部署完成！${NC}"
echo "============================================"
echo ""
echo "服務狀態："
ssh "$RPI_USER@$RPI_HOST" "
    echo '--- systemd ---'
    for svc in mosquitto mqtt-led mqtt-ntfy pihole-FTL; do
        status=\$(systemctl is-active \$svc 2>/dev/null || echo 'inactive')
        printf '  %-15s %s\n' \$svc \$status
    done
    echo ''
    echo '--- docker ---'
    docker ps --format '  {{.Names}}\t{{.Status}}' 2>/dev/null
" || true

echo ""
echo "⚠️  手動檢查事項："
echo "  1. push-temp.sh 的 Uptime Kuma Push URLs（含 API token）"
echo "  2. mqtt-led/config.json 的 GPIO 接線設定"
echo "  3. mqtt-ntfy/config.json 的 ntfy URL"
echo "  4. fstab 根目錄掛載加上 noatime,commit=3600"
echo ""
echo "測試指令："
echo "  ~/dotfiles/scripts/test-mqtt.sh"
