---
name: streamdeck
description: >
  Stream Deck 硬體規格、SDK 效能規範與操作指南。當修改 Stream Deck plugin、
  調整按鍵佈局、變更字型大小、或需要啟動/重啟時使用。
---

# Stream Deck：規格與操作

## 硬體規格

| 項目 | 值 |
|------|-----|
| 型號 | Stream Deck XL |
| 按鍵數 | 32（4 行 × 8 列） |
| 按鍵解析度 | **144 × 144 px** |
| 連接 | USB 接 Windows 主機 |

## 字型大小參考（144×144 按鍵）

| 字元數/行 | 建議字型大小 | 佔寬比 |
|-----------|------------|--------|
| 3-4 字 | 30-36 | 50-60% |
| 5-7 字 | 18-24 | 適中 |
| 8-10 字 | 11-16 | 緊湊 |

設計按鍵內容時，以 144px 寬度為基準估算。

## 架構

```
RPi5B MQTT Broker ←── WSL Publisher (tmux-mqtt-colors.sh)
       ↓
Windows: Elgato Stream Deck 軟體 → Node.js plugin (claude-monitor)
       ↓
Stream Deck USB
```

Plugin 由 Elgato Stream Deck 軟體管理，透過 `@elgato/streamdeck` SDK (Node.js) 通訊。
部署路徑：`C:\Users\duofilm\com.duofilm.claude-monitor.sdPlugin\`

## SDK 效能規範（Elgato 官方）

### API 成本比較

| 方法 | 成本 | 說明 |
|------|------|------|
| `setState(0/1)` | **最輕** | 只送數字，manifest 定義的預設圖 |
| `setTitle("text")` | 輕 | 純文字，SD 軟體渲染 |
| `setImage(svg)` | **最重** | 完整 SVG/PNG payload |

### 關鍵限制

- **`setImage` 上限 10 次/秒**（全域，含所有按鍵）
- SDK 內部**零節流、零快取、零去重** — 每次 `setImage` 都直送 WebSocket
- **不支援 animated GIF**

### 必須遵守的模式

1. **事件驅動** — 只在狀態真正改變時才呼叫 `setImage`，絕不用 `setInterval` 輪詢刷畫面
2. **去重** — 呼叫前比對新舊值，相同就跳過（SDK 不會幫你擋）
3. **閃爍用 setState** — 若需要動畫效果，在 manifest 定義 2 個 States，用 `setState(0/1)` 切換，不要每次重新生成 SVG
4. **SVG 優先** — 比 base64 PNG 輕很多，且自動適配所有 SD 型號

## 建構與部署

```bash
cd ~/dotfiles/streamdeck-plugin
npm run build    # rollup 編譯 + 自動 deploy 到 Windows
```

## 按鍵配置

Plugin 的 MQTT broker 設定透過 Stream Deck 軟體的 Property Inspector UI 修改（Global Settings）。
預設值：`192.168.88.10:1883`

專案按鍵由 plugin 自動分配（拖幾個 "Claude Status" action 到面板即可）。

## 注意事項

- Plugin 的 Node.js 由 Stream Deck 軟體內建管理，不需另外安裝
- 原 Python 版 (`streamdeck_mqtt.py`) 已移除，完全由 SDK plugin 取代
