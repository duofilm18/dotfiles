---
name: pihole-tplink
description: >
  RPi5B 原生安裝的 Pi-hole 搭配 TP-Link 路由器的廣告攔截設定與維護。當需要
  新增擋廣告名單、排查廣告未被攔截、設定 TP-Link DHCP DNS、或處理 Pi-hole v6
  API 操作時使用。
---

# Pi-hole + TP-Link 路由器設定與維護

## 架構

```
所有設備 → TP-Link 路由器（DHCP 派發 DNS） → Pi-hole (192.168.88.10:53) → 上游 DNS
                                                    ↓
                                              廣告域名 → 0.0.0.0（攔截）
                                              正常域名 → 正常解析
```

## Pi-hole 基本資訊

| 項目 | 值 |
|------|-----|
| 位址 | `192.168.88.10` |
| Web UI | `http://192.168.88.10/admin` |
| 版本 | v6.x（原生安裝） |
| 服務 | `pihole-FTL`（systemd） |
| DNS Port | 53 (TCP/UDP) |
| Web Port | 80 |

## TP-Link 路由器 DHCP 設定

**位置：進階設定 > 網路設定 > DHCP 伺服器**

| 項目 | 建議值 | 說明 |
|------|--------|------|
| DHCP 伺服器 | 啟用 | — |
| IP 位址範圍 | `192.168.88.20` - `192.168.88.253` | 避開 `.10`（Pi-hole 固定 IP） |
| 預設閘道 | `192.168.88.1` | 路由器本身 |
| 主要 DNS | `192.168.88.10` | Pi-hole |
| 次要 DNS | **留空** | ⚠️ 填路由器 IP 會導致設備繞過 Pi-hole |

### ⚠️ 重要注意事項

1. **次要 DNS 必須留空** — 若填入路由器 IP（如 `192.168.88.1`），設備在 Pi-hole 回應稍慢時會直接用路由器 DNS，廣告就不會被擋
2. **改完要重啟路由器** — TP-Link 改 DHCP 設定後必須 Reboot，光按儲存不夠
3. **設備要重新連線** — 路由器重啟後設備需重連 Wi-Fi 才會拿到新 DNS

### 參考文件

- [TP-Link 官方 Pi-hole 設定指南](https://www.tp-link.com/tw/support/faq/3230/)
- [Pi-hole 官方 TP-Link 文件](https://docs.pi-hole.net/routers/tp-link/)

## 擋廣告名單

### 目前使用的名單

| 名單 | 網域數 | 說明 |
|------|--------|------|
| [StevenBlack/hosts](https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts) | ~79,000 | 綜合性英文廣告名單（預設） |
| [anti-AD](https://anti-ad.net/domains.txt) | ~111,000 | 中文區命中率最高，針對中文網站優化 |

### 新增名單（Pi-hole v6 API）

Pi-hole v6 不再支援 `pihole -a adlist add`，需透過 REST API：

```bash
# 1. 取得 session ID
SID=$(curl -s -X POST "http://localhost/api/auth" \
  -H "Content-Type: application/json" \
  -d '{"password":"YOUR_PASSWORD"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['session']['sid'])")

# 2. 新增名單
curl -s -X POST "http://localhost/api/lists" \
  -H "Content-Type: application/json" \
  -H "sid: $SID" \
  -d '{"address":"https://example.com/blocklist.txt","comment":"說明"}' \
  --url-query "type=block"

# 3. 更新 gravity
pihole -g
```

## 關鍵設定：listeningMode

**`listeningMode` 必須設為 `"all"`**，讓 Pi-hole 接受所有介面的 DNS 查詢。

```bash
# 查看目前設定
pihole-FTL --config dns.listeningMode
# 必須是 ALL

# 修改（Ansible 已設定，通常不需手動改）
sudo pihole-FTL --config dns.listeningMode all
sudo systemctl restart pihole-FTL
```

安全性由主機防火牆控制。

## 故障排查

### 廣告沒有被攔截

```bash
# 1. 確認 Pi-hole 運行中
pihole status

# 2. 確認有設備在使用 Pi-hole DNS（最重要！）
#    若只有 localhost，代表路由器 DNS 設定未生效
SID=$(curl -s -X POST \
  "http://localhost/api/auth" -H "Content-Type: application/json" \
  -d '{"password":"YOUR_PASSWORD"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[\"session\"][\"sid\"])") && \
curl -s "http://localhost/api/stats/top_clients" -H "sid: $SID"

# 3. 測試 Pi-hole 本身是否正常攔截
dig ad.doubleclick.net @127.0.0.1 +short
# 預期回傳 0.0.0.0 = 攔截正常
```

### 常見問題

| 症狀 | 原因 | 解決方式 |
|------|------|----------|
| 只有 localhost 查詢，沒有其他設備 | `listeningMode` 不是 `"all"` 或路由器 DNS 未生效 | 確認 pihole.toml `listeningMode = "all"` + 重啟路由器 |
| 部分廣告仍然出現 | 次要 DNS 填了路由器 IP | 次要 DNS 留空 |
| 設備無法上網 | pihole-FTL 服務掛了 | `sudo systemctl restart pihole-FTL` |
| Gravity 更新失敗 | 上游 DNS 或網路問題 | 檢查 RPi5B 網路連線 |

### 確認設備 DNS 是否指向 Pi-hole

- **Windows**：`ipconfig /all` → DNS Servers 應為 `192.168.88.10`
- **macOS**：系統偏好設定 → 網路 → Wi-Fi → 詳細資訊 → DNS
- **iPhone/Android**：Wi-Fi 設定 → 連線詳細資訊 → DNS
- **Linux**：`resolvectl status` 或 `cat /etc/resolv.conf`

## 常用維護指令

```bash
# 以下指令皆在 RPi5B 上執行（ssh duofilm@192.168.88.10）

# Pi-hole 狀態
pihole status

# 更新擋廣告名單
pihole -g

# 查看即時 DNS 查詢紀錄
pihole -t

# 查詢特定網域是否被攔截
pihole -q example.com

# 列出所有名單
pihole api lists

# 重啟 Pi-hole
sudo systemctl restart pihole-FTL
```

## 相關檔案

- `ansible/roles/rpi_pihole/` — Pi-hole Ansible role（原生安裝）
- `ansible/roles/rpi_pihole/defaults/main.yml` — 預設變數（密碼、DNS、介面）
