# WSL2 無法連線區網設備（RPi5B）排查指南

當 WSL2 無法 SSH 或 ping 到區網設備（如 192.168.88.10）時，按本指南逐步排查。

## 已知根因：Tailscale fwmark policy routing 黑洞

WSL2 使用 `networkingMode=mirrored` 時，本來可以直連區網 `192.168.88.x`。但如果 WSL 的 Tailscale 啟用了 `--accept-routes`，會發生以下問題：

1. Tailscale 在 Linux kernel 建立 **fwmark policy route**（routing table 52）
2. Table 52 的優先級**高於** main table
3. 發往 `192.168.88.x` 的封包被 policy route 劫持到 `tailscale0`
4. WSL 的 `tailscale0` 沒有 L2 出口（它不是真正的網路介面）
5. Kernel 直接 **drop** 封包 → 連線 timeout

**WSL 不應當 subnet routing client**——它跟 Windows 在同一台主機上，透過 mirrored networking 已經能直連 LAN。

## 第一步：確認症狀

```bash
# 測試區網連線（預期失敗才會來看這份文件）
ping -c 2 -W 3 192.168.88.10

# 測試外網（通常正常）
ping -c 2 -W 3 8.8.8.8
```

**典型症狀**：外網正常，區網 timeout。

## 第二步：確認 WSL 網路模式

```bash
# 查看 WSL IP
ip addr show eth0
```

- 如果 IP 是 `172.x.x.x` → **NAT 模式**，需要先改成 mirrored（見下方「前提條件」）
- 如果 IP 是 `192.168.88.x` 或看不到 eth0 → **mirrored 模式**，繼續排查

## 第三步：檢查 Tailscale 是否劫持路由

這是最常見的根因。依序執行：

```bash
# 3a. 檢查 Tailscale 是否在運行
tailscale status

# 3b. 檢查是否啟用了 accept-routes
tailscale status --json | grep -i acceptroutes
# ⚠️ 如果是 true，這就是問題所在

# 3c. 檢查 policy routing rules（關鍵證據）
ip rule list
# ⚠️ 如果看到 fwmark 規則指向 table 52，確認是 Tailscale 造成的

# 3d. 檢查 table 52 的內容
ip route show table 52
# ⚠️ 如果看到 192.168.88.0/24 或 default 路由指向 tailscale0，確認黑洞
```

**判斷邏輯**：
- `accept-routes = true` + table 52 有路由 → **確認是 Tailscale 黑洞**，執行修復
- `accept-routes = false` + 仍無法連線 → 跳到「第五步：其他可能原因」

## 第四步：修復 Tailscale 路由（需 sudo）

```bash
# 4a. 關閉 accept-routes
sudo tailscale set --accept-routes=false

# 4b. 重啟 Tailscale 使設定生效
sudo tailscale up --reset
# 會顯示 "Some peers are advertising routes but --accept-routes is false"
# 這是正確的，表示 WSL 不再接收 subnet routes

# 4c. 驗證 policy route 已移除
ip rule list
# 應該不再看到 fwmark → table 52 的規則

# 4d. 驗證連線恢復
ping -c 2 192.168.88.10
# 應該成功，延遲約 1-2ms
```

**⚠️ 注意**：`tailscale up --reset` 會重置所有 flags。如果之前有其他自訂設定（如 `--advertise-exit-node`），需要重新設定。但 WSL 通常不需要額外 flags。

## 第五步：其他可能原因

如果 Tailscale 不是問題（`accept-routes` 已經是 false），依序檢查：

### 5a. WSL 不是 mirrored 模式

檢查 `%USERPROFILE%\.wslconfig`（在 Windows 端）：

```ini
[wsl2]
networkingMode=mirrored
```

修改後需要在 PowerShell 重啟 WSL：
```powershell
wsl --shutdown
```

### 5b. RPi5B 的 SSH 服務未啟動

```bash
# 從能連到 RPi5B 的設備檢查
ssh root@192.168.88.10 'systemctl status sshd'
```

### 5c. SSH host key 變更

如果看到 `REMOTE HOST IDENTIFICATION HAS CHANGED` 錯誤：

```bash
# 移除舊的 host key
ssh-keygen -R 192.168.88.10

# 重新連線（會提示接受新 key）
ssh root@192.168.88.10
```

### 5d. Windows 防火牆阻擋

在 PowerShell（管理員）檢查：
```powershell
# 測試 Windows 本身能否 ping 到 RPi5B
ping 192.168.88.10
```

如果 Windows 也 ping 不到，問題不在 WSL。

## 第六步：設定 SSH 金鑰登入（可選）

連線恢復後，建議設定免密碼登入：

```bash
# 檢查是否已有 SSH key
ls ~/.ssh/id_ed25519.pub

# 如果沒有，產生一組
ssh-keygen -t ed25519

# 複製公鑰到 RPi5B（需輸入密碼一次）
ssh-copy-id root@192.168.88.10

# 驗證免密碼登入
ssh root@192.168.88.10 'echo "SSH OK: $(hostname)"'
```

## 快速診斷清單

| 步驟 | 指令 | 正常結果 | 異常 → 原因 |
|------|------|---------|------------|
| 外網 | `ping -c 2 8.8.8.8` | 成功 | 失敗 → WSL 網路根本沒通 |
| 網路模式 | `ip addr show eth0` | 192.168.x.x 或無 eth0 | 172.x.x.x → NAT 模式，需改 mirrored |
| Tailscale routes | `tailscale status --json \| grep acceptRoutes` | false | true → **執行第四步修復** |
| Policy route | `ip rule list` | 無 fwmark/table 52 | 有 → Tailscale 黑洞，執行第四步 |
| 區網 ping | `ping -c 2 192.168.88.10` | 成功，~1ms | timeout → 見第五步 |
| SSH | `ssh root@192.168.88.10` | 登入成功 | host key 錯誤 → 5c；密碼錯誤 → 第六步 |

## 重要原則

- **WSL 不需要 Tailscale 來連區網**——mirrored networking 已提供直連能力
- **WSL 絕不要 `--accept-routes=true`**——這會建立黑洞路由
- Tailscale 的 subnet routing 是給**不在同一 LAN 的設備**用的（如手機在外面）
- 如果 `tailscale up --reset` 後 Tailscale 完全斷線，執行 `sudo tailscale up` 重新連線即可

## 相關文件

- [Tailscale 路由衝突](./tailscale-route-conflict.md) - Windows / 其他 Linux 設備的路由衝突處理
- [CLAUDE.md](../../CLAUDE.md) - 環境備註與 SSH 指令
