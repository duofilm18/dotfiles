---
name: architecture-health
description: >
  系統層級架構健康原則。設計跨裝置互動、審查系統架構時使用。
  涵蓋裝置邊界、語意介面。
---

# 系統架構健康原則

## 裝置邊界（Device Boundary）

每台裝置是一個自治單元。

- **內部事不出邊界** — tmux 變數、Claude hooks 都是主機內部事務
- **跨裝置只經由語意介面通訊** — 不直接存取對方的內部狀態

## 語意介面（Semantic Interface）

跨裝置 payload 傳「是什麼」，不傳「怎麼做」。

| | payload 範例 | 性質 |
|---|---|---|
| **正確** | `{domain:"system", state:"temp_high"}` | 語意：描述狀態 |
| **反模式** | `{action:"send_alert", target:"phone"}` | 指令：替對方決定行為 |

## 審查 Checklist

設計或修改跨裝置功能時逐項確認：

- [ ] 改 A 會不會壞 B？（如果會 → 耦合過緊，需拆解）
- [ ] 這個資訊該內部消化還是跨裝置？（內部 → 不出邊界）
- [ ] 跨裝置的 payload 是語意還是指令？（指令 → 改為語意）

## 現有裝置邊界（參考）

| 角色 | 實體 | 內部元件 | 對外介面 |
|------|------|----------|-------------|
| 主機 | HP (Win+WSL) | tmux, Claude hooks, dispatch.sh | curl ntfy.sh |
| 伺服器 | RPi5B | Docker (Pi-hole, ntfy, Uptime Kuma), mosquitto | HTTP API, MQTT |
