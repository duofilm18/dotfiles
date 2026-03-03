---
name: streamdeck
description: >
  Stream Deck 硬體規格、SDK 效能規範、plugin 開發流程與踩坑紀錄。
  當新增/修改 Stream Deck action、調整按鍵佈局、撰寫 Windows PowerShell
  publisher、或需要啟動/重啟時使用。
---

# Stream Deck：規格、開發與操作

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

## 新增 Action 開發流程（Checklist）

新增一個 MQTT-driven 按鍵需要改 **5 個檔案 + 2 個 SVG**：

| # | 檔案 | 動作 |
|---|------|------|
| 1 | `src/actions/<name>.ts` | 新建。複製 `system-stats.ts` 模式：`@action` decorator + `SingletonAction` + `updateStats()` + `lastXxx` 去重欄位 |
| 2 | `src/renderer.ts` | 新增 `render<Name>Svg()` 函式 |
| 3 | `src/mqtt-handler.ts` | 新增 callback type → constructor 加參數 → `subscribe()` → `on("message")` 分支（JSON dedup） |
| 4 | `src/plugin.ts` | import action → new instance → MqttHandler 加 callback → `registerAction()` |
| 5 | `com.duofilm.claude-monitor.sdPlugin/manifest.json` | Actions 陣列加 entry |
| 6 | `imgs/<name>.svg` | 40×40 action list icon |
| 7 | `imgs/<name>-state.svg` | 144×144 預設狀態（`--` 佔位） |

### MQTT handler 去重模式

```typescript
// mqtt-handler.ts 內，每個 topic 一個 lastXxx 字串做 JSON 比對
private lastWinStats = "";

// on("message") 分支
if (packet.topic === "system/stats/win" && this.onWinStats) {
    const raw = payload.toString();
    if (raw === this.lastWinStats) return;  // 值沒變，跳過
    this.lastWinStats = raw;
    try {
        const data = JSON.parse(raw);
        this.onWinStats(data.temp ?? 0, data.freq ?? 0, data.ram ?? 0);
    } catch { /* ignore malformed */ }
    return;
}
```

### SVG 渲染模板（144×144 按鍵）

```
行 1: 標題（灰色 16px）     y=24
行 2: 主數值（32px bold）    y=58
行 3: 次數值（白色 18px）    y=92
行 4: 次數值（白色 18px）    y=122
```

4 行文字的 y 座標：24, 58, 92, 122。3 行的 y 座標：28, 72, 116。

## Windows PowerShell Publisher 開發規範

### 關鍵踩坑

| 問題 | 原因 | 解法 |
|------|------|------|
| PowerShell 語法錯誤（unexpected `}`） | WSL 寫的檔案是 LF，PowerShell 需要 CRLF | `sed -i 's/\r*$/\r/' file.ps1` |
| LHM WMI namespace 不存在 | LHM 沒開或沒以管理員執行 | 改用 HTTP API（`localhost:8085/data.json`） |
| WSL curl 連不到 Windows localhost:8085 | LHM HTTP 只綁 127.0.0.1，WSL mirrored networking 不通 | publisher 跑在 Windows PowerShell，不走 WSL |
| 需要安裝 mosquitto_pub | Windows 沒有 mosquitto-clients | 用 .NET `TcpClient` 寫純 TCP MQTT，零外部依賴 |
| HP Omen AMD CPU temp/clock 全是 0 | BIOS 鎖住 AMD SMU 寄存器，LHM 讀不到 | 溫度 fallback GPU Core，頻率 fallback `Win32_Processor` |
| ExecutionPolicy 擋腳本 | 預設 Restricted | `-ExecutionPolicy Bypass` |

### 純 TCP MQTT Publish（PowerShell，零依賴）

`Send-MqttPublish` 函式用 `System.Net.Sockets.TcpClient` 手工組 MQTT 3.1.1 封包：
CONNECT → CONNACK → PUBLISH (retain) → DISCONNECT。見 `windows/push-win-stats.ps1`。

### LHM HTTP API Sensor 讀取

LHM `/data.json` 是巢狀樹，需遞迴走訪。Sensor 名稱因硬體而異：

| 目標值 | 優先 sensor | fallback |
|--------|------------|----------|
| CPU 溫度 | `CPU Package` / `Core (Tctl/Tdie)` | `GPU Core`（同機溫度近似） |
| CPU 頻率 | LHM `Core #N` (MHz) | `Win32_Processor.CurrentClockSpeed`（base clock） |
| RAM 使用率 | LHM `Memory` (%) | — |

### PowerShell 檔案管理

- **一律用 CRLF** — WSL 的 Write tool 會寫 LF，寫完必須轉換
- **Task Scheduler 加 `-ExecutionPolicy Bypass`** — 否則 UNC 路徑腳本會被擋
- **從 WSL 執行 Windows 查詢**：`powershell.exe -NoProfile -Command "..."` 直接跑，不要請用戶貼輸出

## 注意事項

- Plugin 的 Node.js 由 Stream Deck 軟體內建管理，不需另外安裝
- 原 Python 版 (`streamdeck_mqtt.py`) 已移除，完全由 SDK plugin 取代
- **重啟 Stream Deck**：`powershell.exe -NoProfile -Command "Stop-Process -Name StreamDeck -Force; Start-Sleep 3; Start-Process 'C:\Program Files\Elgato\StreamDeck\StreamDeck.exe'"`
