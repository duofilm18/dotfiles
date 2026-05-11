# Codex Next Steps for Claude

最後更新：2026-05-09

這份文件是給 Claude 執行用的工作單。Codex 的判斷：目前不應再做一般「最佳化 plugin 程式碼」；要把問題切成可量測的邊界，確認 CPU 是卡在 MQTT codec、SDK WebSocket IPC、Stream Deck host app preview repaint，還是 Windows/Elgato runtime。

## 原則

- 不要重跑 `CPU_REGRESSION_REPORT.md` 已列的 12 個 ablation。
- 每次只改一個軸線，記錄三個 process 的 CPU：`StreamDeck.exe`、plugin Node process、`dwm.exe`。
- 每個測試至少 idle 2 分鐘後取值，因為 retained rebuild 和 Stream Deck 啟動初期會污染數字。
- 每個測試都要寫回 `CPU_REGRESSION_REPORT.md` 或新增測試紀錄，包含日期、SD app 版本、SDK 版本、plugin commit、測試模式、CPU 數字。

## 我認為最值得先測的軸線

### 1. Render target: hardware-only

假設：Stream Deck app 7.4.x 對 plugin 的 `setImage` / `setTitle` 預設同時更新 hardware + software preview，導致 app UI repaint，進一步拉高 `dwm.exe`。

Claude 要做：

- 加一個最小 patch，讓所有 `setImage` 和 `setTitle` 呼叫都帶 `{ target: Target.Hardware }`。
- 先不要加 UI 設定，直接硬編碼 hardware-only。
- 跑 Windows 實機測試。

預期判讀：

- 如果 `dwm.exe` 明顯下降，host preview repaint 是主要因素之一。
- 如果 plugin Node 仍約 22%，表示 plugin runtime 或 MQTT path 仍有獨立 busy loop。
- 如果 `StreamDeck.exe` 和 `dwm.exe` 都下降，這可以先當 workaround。

注意：

- SDK 2.1.0 的 `KeyAction.setImage(image, options)` 支援 target；`setTitle` 型別可能只標單參數，但底層 command type 有 `target`。如果 TypeScript 報錯，先用很小的 helper 做 typed wrapper，不要大改 action 架構。

### 2. MQTT connected but no SUBSCRIBE

假設：不是 CONNECT/keepalive，而是 SUBSCRIBE 後的 broker publish path 或 retained rebuild 觸發 host/SDK 行為。

Claude 要做：

- 在 `MqttHandler` 加一個硬編碼測試模式：CONNECT 收到 CONNACK 後不送 SUBSCRIBE。
- 不改 action render。
- 測 CPU。

預期判讀：

- `no SUBSCRIBE` 低 CPU：問題在 publish/parse/render 後段。
- `no SUBSCRIBE` 仍高 CPU：問題在 MQTT connection state、codec stream plumbing、Node sandbox 對 socket activity 的處理，或 host 對 plugin network activity 的 regression。

### 3. SUBSCRIBE but drop render

假設：MQTT 收包本身不燒，是 callback 進入 action render 後造成 SDK IPC/host repaint。

Claude 要做：

- 保留 SUBSCRIBE 和 JSON parse。
- 在 `plugin.ts` 的 MQTT callbacks 最前面 return，不呼叫任何 action method。
- 記錄 dropped publish count 到 log，每 100 筆一行即可。

預期判讀：

- CPU 下降：SDK IPC / action render 是主要觸發點。
- CPU 不下降：MQTT codec / event dispatch / plugin runtime 本身有問題。

### 4. Topic split: status-only vs stats-only

假設：不是總流量，而是某一類 action update 型態觸發 host regression。

Claude 要做：

- 做兩個短暫測試 build：
  - 只訂 `claude/led/+`
  - 只訂 `system/stats` 和 `system/stats/win`
- 不改其他邏輯。

預期判讀：

- stats-only 高：低頻 `setTitle` 仍足以觸發 host bug。
- status-only 高：retained status rebuild 或 status key render 是主因。
- 兩者都低、合起來高：host 對多 action/message routing 有非線性成本。

### 5. SDK WebSocket instrumentation

假設：SDK 2.1.0 改善 `dwm` 但未解 host/plugin CPU，值得量 SDK send/receive 數量與耗時。

Claude 要做：

- 不 fork npm package 起步，先在 bundle 前用本地 patch 或直接臨時改 `node_modules/@elgato/streamdeck/dist/plugin/connection.js`。
- 在 `Connection.send()` 計數 event type：`setTitle`、`setImage`、其他。
- 在 `tryEmit()` 計數 host 傳入 event type。
- 每 10 秒 log 一行：
  - outgoing counts by event
  - incoming counts by event
  - max JSON stringify/send time

預期判讀：

- outgoing 很少但 CPU 高：host/runtime bug 較可能。
- incoming 很多：Stream Deck host 可能在對 plugin spam event。
- stringify/send 耗時高：SDK/WebSocket path 是可優化點。

## 建議的執行順序

1. 先跑 `hardware-only`，因為它可能直接變成可用 workaround。
2. 跑 `MQTT no SUBSCRIBE`，切開 CONNECT 與 publish。
3. 跑 `SUBSCRIBE drop render`，切開 MQTT parse 與 SDK IPC。
4. 跑 `topic split`，定位是 status 還是 stats。
5. 最後才做 SDK instrumentation；這步資訊最多，但也最容易引入觀察者效應。

## Windows 實機量測格式

每輪請記錄：

```text
Test:
Plugin commit:
SD app:
SDK:
Mode:
Duration:
StreamDeck.exe CPU:
Plugin Node CPU:
dwm.exe CPU:
Notes:
```

建議用 PowerShell 固定取樣，而不是肉眼看 Task Manager。可以用下面格式做 60 秒平均，實際 process name 以 Windows 上看到的為準：

```powershell
$names = @("StreamDeck", "node", "dwm")
1..60 | ForEach-Object {
  Get-Process | Where-Object { $names -contains $_.ProcessName } |
    Select-Object ProcessName, Id, CPU
  Start-Sleep -Seconds 1
}
```

如果要更嚴謹，用 Windows Performance Recorder 抓 60 秒 CPU trace：

```powershell
wpr -start CPU
Start-Sleep -Seconds 60
wpr -stop "$env:USERPROFILE\Desktop\streamdeck-cpu.etl"
```

用 Windows Performance Analyzer 打開 `.etl`，先看 CPU Usage (Sampled)，group by Process / Stack。重點看：

- `StreamDeck.exe` 是否卡在 UI/render/message dispatch。
- plugin Node 是否卡在 `ws`、`mqtt-packet`、stream、JSON parse、timer。
- `dwm.exe` 是否跟 StreamDeck window repaint 同步。

## 給 Elgato issue 的最小證據包

如果要回報上游，請準備：

- `CPU_REGRESSION_REPORT.md`
- 5 個新 ablation 的 CPU 表格
- 一個 WPR `.etl` trace
- plugin source commit hash
- SD app exact version：`7.4.1.22720`
- SDK exact version：`@elgato/streamdeck 2.1.0`
- 明確一句結論：

```text
On Stream Deck 7.4.x for Windows, a Node 20 plugin that maintains an MQTT connection and sends very low-frequency setTitle/setImage updates can keep StreamDeck.exe and dwm.exe busy even when MQTT traffic is under 1 msg/sec. Hardware-only render target / no-subscribe / drop-render ablations isolate whether the regression is in host preview repaint, plugin IPC routing, or plugin runtime networking.
```

## 暫時不要做

- 不要再換 MQTT library。
- 不要再改 SVG/data URI。
- 不要再改 broker。
- 不要先重構 action 架構。
- 不要把 render 搬 worker。Worker 仍要回 SDK IPC，未先證明 IPC 是主因前，這會增加變因。

