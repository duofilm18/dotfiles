# Tailscale 路由衝突診斷與修復

當 Tailscale 的 Subnet Routes 與本地區網發生衝突時，會導致無法連線到區網內的設備。本指南提供診斷和修復的完整流程。

## 問題症狀

- 無法 ping 通區網內的 IP（如 192.168.88.10）
- curl 請求一直等待，沒有回應
- 同網段的其他設備可以正常連線

## 問題原因

Tailscale 的 Subnet Routes 功能會在路由表中建立低 metric（高優先級）的路由，將特定網段的流量導向 Tailscale 接口。當你同時：

1. 連接到實體區網（如 192.168.88.0/24）
2. Tailscale 廣播了相同網段的 Subnet Route

就會發生路由衝突，流量被錯誤地導向 Tailscale 而非本地網路。

## 診斷步驟

### Windows

```powershell
# 1. 查看 Tailscale 狀態
tailscale status

# 2. 檢查路由表中的衝突
route print | findstr 192.168.88

# 3. 識別問題路由
# 正常：192.168.88.0  255.255.255.0  ????  192.168.88.x  (metric 高，如 281)
# 衝突：192.168.88.0  255.255.255.0  100.100.100.100  100.x.x.x  (metric 低，如 5)
#       ↑ Tailscale 路由，gateway 是 100.100.100.100，優先級高於本地路由
```

### Linux / WSL

```bash
# 1. 查看 Tailscale 狀態
tailscale status

# 2. 檢查路由表
ip route | grep 192.168.88

# 3. 檢查所有路由表
ip route show table all | grep 192.168.88

# 4. 識別問題路由
# 衝突：192.168.88.0/24 dev tailscale0 (Tailscale 接管了這個網段)
```

## 修復方法

### Windows（PowerShell 管理員）

```powershell
# 刪除 Tailscale 建立的衝突路由
route delete 192.168.88.0 mask 255.255.255.0 100.100.100.100

# 驗證修復
ping 192.168.88.10
route print | findstr 192.168.88
```

### Linux / WSL

```bash
# 方法 1：暫時停止 Tailscale
sudo tailscale down

# 方法 2：刪除特定路由（如果存在）
sudo ip route del 192.168.88.0/24 dev tailscale0

# 驗證修復
ping 192.168.88.10
ip route | grep 192.168.88
```

## 永久解決方案

### 方案 A：調整 Tailscale Subnet Routes

在廣播 Subnet Route 的設備上（如 rpi5b），移除或調整路由：

```bash
# 在 rpi5b 上執行
# 查看目前廣播的路由
tailscale status --json | jq '.Self.AllowedIPs'

# 如果不需要廣播 192.168.88.0/24，重新設定
sudo tailscale up --advertise-routes=  # 清除所有路由
# 或只廣播需要的路由
sudo tailscale up --advertise-routes=192.168.1.0/24
```

### 方案 B：在客戶端停用特定 Subnet Route

```bash
# 在客戶端停用接收特定的 subnet route
# （需要 Tailscale 較新版本支援）
tailscale up --accept-routes=false
```

### 方案 C：腳本自動修復（Windows）

建立 `fix-tailscale-route.ps1`：

```powershell
# fix-tailscale-route.ps1 - 自動修復 Tailscale 路由衝突

param(
    [string]$Subnet = "192.168.88.0",
    [string]$Mask = "255.255.255.0"
)

# 檢查是否有衝突路由
$routes = route print | Select-String "$Subnet.*100\.100\.100\.100"

if ($routes) {
    Write-Host "發現 Tailscale 路由衝突，正在修復..." -ForegroundColor Yellow
    route delete $Subnet mask $Mask 100.100.100.100
    Write-Host "已刪除衝突路由" -ForegroundColor Green
} else {
    Write-Host "未發現路由衝突" -ForegroundColor Green
}

# 驗證
Write-Host "`n目前路由表："
route print | Select-String $Subnet
```

### 方案 D：腳本自動修復（Linux/Bash）

建立 `fix-tailscale-route.sh`：

```bash
#!/bin/bash
# fix-tailscale-route.sh - 自動修復 Tailscale 路由衝突

SUBNET="${1:-192.168.88.0/24}"

# 檢查是否有通過 tailscale0 的衝突路由
if ip route | grep -q "$SUBNET.*tailscale0"; then
    echo "發現 Tailscale 路由衝突，正在修復..."
    sudo ip route del "$SUBNET" dev tailscale0
    echo "已刪除衝突路由"
else
    echo "未發現路由衝突"
fi

# 驗證
echo -e "\n目前路由表："
ip route | grep "${SUBNET%/*}"
```

## 預防措施

1. **規劃網段**：Tailscale Subnet Routes 盡量使用不會與常見區網衝突的網段
2. **選擇性接受**：只在需要的設備上啟用 `--accept-routes`
3. **監控腳本**：在開機時執行修復腳本，自動處理衝突

## 快速診斷清單

| 檢查項目 | Windows 指令 | Linux 指令 |
|---------|-------------|-----------|
| Tailscale 狀態 | `tailscale status` | `tailscale status` |
| 路由表 | `route print \| findstr 網段` | `ip route \| grep 網段` |
| 連線測試 | `ping IP` | `ping IP` |
| 刪除衝突路由 | `route delete 網段 mask 遮罩 100.100.100.100` | `sudo ip route del 網段 dev tailscale0` |

## 相關資源

- [Tailscale Subnet Routes 文件](https://tailscale.com/kb/1019/subnets)
- [Tailscale 路由優先級](https://tailscale.com/kb/1105/route-precedence)
