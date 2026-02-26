#!/bin/bash
# ============================================
# setup-rpi5b.sh - RPi5B 一鍵部署
# ============================================
#
# ⚠️ DEPRECATED — 此腳本為 Ansible 導入前的遺留 bootstrap，
# 所有功能已被 Ansible roles 覆蓋，請改用：
#
#   cd ~/dotfiles/ansible && ansible-playbook rpi5b.yml
#
# 保留僅供參考，不再維護。
#
# ============================================

echo "⚠️  此腳本已 deprecated，請改用："
echo "    cd ~/dotfiles/ansible && ansible-playbook rpi5b.yml"
echo ""
read -rp "仍要繼續執行？(y/N) " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || exit 0

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
step "Step 1/9: 系統設定（boot, fstab, log2ram, sysctl, journald, MOTD）"

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
# Step 2: Docker
# ============================================
step "Step 2/9: Docker"

if ssh "$RPI_USER@$RPI_HOST" "command -v docker" &>/dev/null; then
    info "Docker 已安裝，跳過"
else
    info "安裝 Docker..."
    ssh "$RPI_USER@$RPI_HOST" "curl -fsSL https://get.docker.com | sh"
fi

# ============================================
# Step 3: Docker Compose（uptime-kuma + ntfy + pihole）
# ============================================
step "Step 3/9: Docker Compose 服務（uptime-kuma + ntfy + pihole）"

info "停用 systemd-resolved（釋放 port 53 給 Pi-hole）..."
ssh "$RPI_USER@$RPI_HOST" "
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        sudo systemctl disable --now systemd-resolved
        sudo rm -f /etc/resolv.conf
        echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf
    fi
"

info "部署 docker-compose..."
ssh "$RPI_USER@$RPI_HOST" "cd $REMOTE_DOTFILES/rpi5b/docker && docker compose up -d"
info "Step 3 完成 ✅"

# ============================================
# Step 4: Mosquitto + lgpio
# ============================================
step "Step 4/9: Mosquitto + lgpio 編譯"

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

info "Step 4 完成 ✅"

# ============================================
# Step 5: mqtt-led + systemd
# ============================================
step "Step 5/9: MQTT 服務部署（mqtt-led）"

REMOTE_LED="$REMOTE_HOME/mqtt-led"

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

# 清理舊 mqtt-ntfy（已移除，通知改用 dispatch.sh 直接 curl ntfy.sh）
info "清理舊 mqtt-ntfy..."
ssh "$RPI_USER@$RPI_HOST" "sudo systemctl stop mqtt-ntfy 2>/dev/null; sudo systemctl disable mqtt-ntfy 2>/dev/null; sudo rm -f /etc/systemd/system/mqtt-ntfy.service; rm -rf $REMOTE_HOME/mqtt-ntfy" || true

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

ssh "$RPI_USER@$RPI_HOST" "sudo systemctl daemon-reload && sudo systemctl enable mqtt-led && sudo systemctl restart mqtt-led"

info "Step 5 完成 ✅"

# ============================================
# Step 6: Tailscale（需手動登入）
# ============================================
step "Step 6/9: Tailscale"

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
# Step 7: Crontab
# ============================================
step "Step 7/9: Crontab"

info "設定 crontab..."
ssh "$RPI_USER@$RPI_HOST" "crontab -" <<'CRON'
# 每分鐘推送系統狀態到 Uptime Kuma
* * * * * /root/dotfiles/rpi5b/scripts/push-temp.sh
CRON

info "Step 7 完成 ✅"

# ============================================
# Step 8: 停用 unblock-rfkill
# ============================================
step "Step 8/9: 停用 unblock-rfkill"

ssh "$RPI_USER@$RPI_HOST" "
    if systemctl is-enabled unblock-rfkill &>/dev/null; then
        sudo systemctl disable unblock-rfkill
        sudo systemctl stop unblock-rfkill 2>/dev/null || true
        echo '已停用 unblock-rfkill'
    else
        echo 'unblock-rfkill 已停用或不存在，跳過'
    fi
"

info "Step 8 完成 ✅"

# ============================================
# Step 9: 清理舊 repo
# ============================================
step "Step 9/9: 清理舊 repo"

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

info "Step 9 完成 ✅"

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
    for svc in mosquitto mqtt-led; do
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
echo "  3. ntfy 推播已改用 dispatch.sh 直接 curl ntfy.sh 雲端"
echo "  4. fstab 根目錄掛載加上 noatime,commit=3600"
echo "  5. Pi-hole Web UI 密碼（PIHOLE_PASSWORD 環境變數，預設 changeme）"
echo "  6. 路由器 DHCP DNS 指向 192.168.88.10"
echo ""
echo "測試指令："
echo "  ~/dotfiles/scripts/test-mqtt.sh"
