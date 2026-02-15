#!/bin/bash
# 系統健康檢查腳本
# 檢查 SD 卡保護設定是否正常運作

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo " Raspberry Pi 系統健康檢查"
echo " $(date)"
echo "========================================"
echo ""

check_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
check_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
check_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 1. 檢查 tmpfs
echo "=== 記憶體掛載檢查 ==="
if mount | grep -q "tmpfs on /tmp"; then
    check_pass "/tmp 使用 tmpfs"
else
    check_fail "/tmp 未使用 tmpfs"
fi

if mount | grep -q "zram.*/var/log"; then
    check_pass "/var/log 使用 zram"
else
    check_warn "/var/log 未使用 zram"
fi

# 2. 檢查 swappiness
echo ""
echo "=== 核心參數檢查 ==="
SWAPPINESS=$(cat /proc/sys/vm/swappiness)
if [[ "$SWAPPINESS" -ge 60 ]]; then
    check_pass "vm.swappiness=$SWAPPINESS (優先使用 zram)"
else
    check_warn "vm.swappiness=$SWAPPINESS (建議設為 100)"
fi

# 3. 檢查 commit 間隔
if grep -q "commit=" /etc/fstab; then
    check_pass "fstab 有設定 commit 延遲寫入"
else
    check_warn "建議在 fstab 加入 commit=3600"
fi

# 4. 檢查 journald 限制
echo ""
echo "=== 日誌設定檢查 ==="
if grep -q "SystemMaxUse=" /etc/systemd/journald.conf; then
    SIZE=$(grep "SystemMaxUse=" /etc/systemd/journald.conf | tail -1 | cut -d= -f2)
    check_pass "journald 限制: $SIZE"
else
    check_warn "journald 未設定大小限制"
fi

# 5. 記憶體使用
echo ""
echo "=== 系統資源 ==="
echo "記憶體使用:"
free -h | head -2

echo ""
echo "Swap 使用:"
cat /proc/swaps

echo ""
echo "zram 狀態:"
zramctl 2>/dev/null || echo "zramctl 不可用"

# 6. SD 卡健康 (如果有 smartctl)
echo ""
echo "=== 儲存裝置 ==="
df -h / /tmp /var/log 2>/dev/null | head -5

# 7. 服務狀態
echo ""
echo "=== 服務狀態 ==="
for svc in log2ram armbian-ramlog docker mosquitto mqtt-led mqtt-ntfy; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        check_pass "$svc 運行中"
    elif systemctl is-enabled --quiet $svc 2>/dev/null; then
        check_warn "$svc 已啟用但未運行"
    fi
done

# 8. Docker 容器
if command -v docker &> /dev/null; then
    echo ""
    echo "=== Docker 容器 ==="
    docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null
fi

echo ""
echo "========================================"
echo " 檢查完成"
echo "========================================"
