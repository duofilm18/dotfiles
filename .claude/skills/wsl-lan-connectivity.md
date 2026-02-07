# WSL2 本地網路連線問題排查

當 WSL2 無法連線到本地區網設備（如 192.168.88.x）時，使用此指南理解原因並採用正確的解決方案。

## 問題症狀

- WSL 可以連外網（ping 8.8.8.8 成功）
- WSL 無法 ping 本地區網 IP（如 192.168.88.10）
- WSL 無法 SSH 到區網內的設備

## 根本原因（這是設計，不是 Bug）

WSL2 使用 **NAT 網路模式** 是刻意的安全設計：
- WSL 有獨立的虛擬網段（如 172.20.x.x）
- 與主機 LAN 網路隔離
- 防止 WSL 內的程式直接存取本地網路資源

**不應該試圖繞過這個安全設計。**

## 診斷步驟（確認問題）

### 第一步：確認 WSL 網路環境

```bash
# 查看 WSL 的 IP 和網段
ip addr show eth0

# 查看 WSL 路由表
ip route
```

**預期結果**：
- WSL IP 類似 `172.20.x.x/20`（NAT 網段）
- Gateway 類似 `172.20.80.1`

### 第二步：測試連線範圍

```bash
# 測試 WSL gateway（應該成功）
ping -c 2 172.20.80.1

# 測試外網（應該成功）
ping -c 2 8.8.8.8

# 測試本地 LAN（預期失敗 - 這是正常的安全隔離）
ping -c 2 192.168.88.10
```

## 正確的解決方案

### 方案 A：在 WSL 啟用 Tailscale（推薦）

透過 Tailscale VPN 安全地連線到區網設備：

```bash
# 啟動 WSL 的 Tailscale
sudo tailscale up

# 確認連線狀態
tailscale status

# 使用 Tailscale 網路連線（而非 LAN IP）
ssh root@100.105.101.50  # RPI5B 的 Tailscale IP
```

**優點**：
- 安全的加密通道
- 不破壞 WSL2 的網路隔離設計
- 在外網也能連線

### 方案 B：使用 Tailscale Subnet Routing

如果目標設備有廣播 subnet route：

```bash
# 確保 WSL Tailscale 接受路由
tailscale up --accept-routes

# 然後可以用 LAN IP 連線（透過 Tailscale 隧道）
ssh root@192.168.88.10
```

**前提**：
- RPI5B 需廣播 `192.168.88.0/24` 路由
- 在 Tailscale Admin Console 核准該路由

## 不建議的做法

| 做法 | 為什麼不建議 |
|------|-------------|
| 關閉 Windows 防火牆 | 暴露整個系統於風險中 |
| 新增防火牆例外規則 | 破壞網路隔離設計 |
| WSL2 鏡像網路模式 | 可能與 Docker 衝突，且降低隔離性 |

## 快速診斷清單

| 檢查項目 | 指令 | 預期結果 |
|---------|------|---------|
| WSL IP | `ip addr show eth0` | 172.x.x.x（NAT 網段） |
| WSL Gateway | `ping 172.20.80.1` | 成功 |
| 外網連線 | `ping 8.8.8.8` | 成功 |
| LAN 連線 | `ping 192.168.88.10` | 失敗（正常的安全隔離） |
| Tailscale | `tailscale status` | 顯示連線狀態 |

## 結論

WSL2 無法直接連線本地 LAN 是**安全設計**，不是問題。

正確做法：**使用 Tailscale 建立安全的連線通道**。

## 相關問題

- [Tailscale 路由衝突](./tailscale-route-conflict.md) - 當 Tailscale 的路由覆蓋本地路由時
