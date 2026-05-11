# Stream Deck Plugin CPU Regression — Brief for Codex

> 這份是給另一個 AI（Codex）的求助 brief。請假設你沒看過這個 repo。
> 目的：找出 Claude 已 ablate 完所有合理路徑後，**還沒試過**的調查方向。

最後更新：2026-05-09
作者狀態：用戶把 Stream Deck 硬體物理拔掉當 workaround 中。

---

## TL;DR

Stream Deck Windows app **v7.4.0.22712**（2026-03-31 自動更新）開始，我們自製
plugin（`com.duofilm.claude-monitor`，Node 20 sandbox，持有一條 idle MQTT TCP
連線）會讓整個 SD 生態系持續燒 ~1 個 CPU core：

| Process | CPU |
|---|---|
| `StreamDeck.exe`（host） | 60–85% |
| plugin node process | ~22% |
| `dwm.exe` | ~30%（被 SD UI 重繪推爆） |

關掉 SD app 整體 CPU 從 ~20% 掉到 ~11%，風扇立刻安靜。

**球目前在 Elgato。** 已升 SD app 7.4.1、SDK 2.1.0、改寫 MQTT codec、改寫渲染管線
都不解。但用戶想知道 — 還有什麼是 Claude 漏掉沒試的？

---

## 環境

- **OS**：Windows 11，HP 筆電 `LAPTOP-HP`，16 GB RAM
- **SD app**：v7.4.1.22720（從 7.4.0.22712 升上來，無效）
- **SD SDK**：`@elgato/streamdeck` v2.1.0（從 2.0.1 升上來，dwm CPU 從 ~30% 降到 ~15%，但本體仍燒）
- **Plugin runtime**：Node 20（manifest 指定）
- **Plugin source**：這個資料夾，TypeScript + rollup → CJS bundle
- **MQTT broker**：mosquitto on RPi5B（`192.168.88.10:1883`，匿名 listener）
- **訊息流量**：broker 整體 ~0.4 msg/sec，plugin 訂閱 3 個 topic：
  - `claude/led/+`（多個專案狀態）
  - `system/stats`（RPi5B CPU/RAM，每 5s）
  - `system/stats/win`（Windows CPU/RAM，每 5s）

---

## 當前 plugin 架構（很簡單，沒什麼可砍）

```
src/
├── plugin.ts          (63 lines) — 註冊 4 個 actions、啟動 MQTT
├── mqtt-handler.ts   (231 lines) — net.Socket + mqtt-connection codec
├── types.ts           (35 lines)
└── actions/
    ├── claude-status.ts   (163) — 主要 action，setImage/setTitle dedup
    ├── claude-date.ts     ( 74)
    ├── system-stats.ts    ( 40)
    └── win-stats.ts       ( 59)
```

關鍵設計（已套用所有 ablation 學到的教訓）：

1. **不用 mqtt.js**，改用 `mqtt-connection` v4（純 packet codec）+ 自管 `net.Socket`。
   `rollup.config.mjs` 強制 `exportConditions: ["node"]` 避免 worker-timers 被打進來。
2. **setImage 改靜態 SVG 路徑**（不再 data URI），且每個 contextId 記 `lastIcon` dedup。
3. **setTitle 同樣 dedup**（`lastTitle`）。
4. **handlePublish 進入點 dedup**：`system/stats` 和 `system/stats/win` 比對
   `raw === lastSysStats / lastWinStats`，相同就 return；`claude/led/+`
   比對 cache 裡的 state，相同也 return。
5. **Reconnect**：5s 退避，單一 timer。
6. **PING**：自送 `pingreq()` 每 50s（keepalive=60）。

→ 也就是說：plugin 在「沒有訊息進來」時應該幾乎完全 idle。

---

## 已 ablate 的假設（這些都試過了，**不要再叫我們試**）

| # | 假設 | 結果 |
|---|---|---|
| 1 | mqtt.js v5 worker-timers | 換 mqtt.js v4、再換 mqtt-connection 都一樣 ~22% |
| 2 | `timerVariant: "native"` + `keepalive: 0` | 沒救 |
| 3 | setImage 頻率太高 | refactor 到只在 state 切換才 setImage，沒救 |
| 4 | SVG data URI 太重 | 改靜態 SVG + setTitle，沒救 |
| 5 | 訊息洪水 | broker 實測只 0.4 msg/sec |
| 6 | 第三方 plugin 害的 | 全部停用，只跑我們的，仍燒 |
| 7 | TCP 連線本身有問題 | raw TCP idle 連線只 ~1.5%，但講 MQTT protocol 就 22% |
| 8 | broker 配置 | mosquitto 最簡 listener + anonymous，仍燒 |
| 9 | reconnect storm | log 確認連線一次後沒再重連 |
| 10 | SD app 7.4.0 → 7.4.1.22720 | 沒救（release notes 也沒提 plugin runtime/CPU 修復） |
| 11 | SDK 2.0.1 → 2.1.0 | 部分有效，dwm 從 ~30% → ~15%；plugin/SD app 本體仍燒 |
| 12 | `useExperimentalMessageIdentifiers` flag | 只影響 `getSettings()`，我們沒用 |

---

## 觀察到的「形狀」（可能對診斷有幫助）

- **idle TCP 連線本身只 1.5%**（換 raw socket 不講 MQTT 時測過）。
- **一旦走 MQTT 協議**（CONNECT → CONNACK → SUBSCRIBE → 開始收 publish）就跳到 22%。
- **dwm 連帶吃 CPU** → 暗示 SD app **UI 在重繪**，即使我們有 `setImage` dedup。
  也就是 SD host 收到 plugin 的 message 後**忽略 dedup 仍重繪**？或是 host 本身在
  message routing 層就燒了？SDK 2.1.0 部分有效這點符合「host 端 message handling 有問題」。
- 用 raw socket（不講 MQTT）就不燒 → **不是純 socket 活躍度**，是「plugin 上有有意義的 IPC traffic」會觸發 SD host regression。

---

## 相關上游

- [elgatosf/streamdeck#140](https://github.com/elgatosf/streamdeck/issues/140)
  — host application memory growth from plugin WebSocket activity。同樣機制
  （host 對 plugin 訊息有累積/重複 work），但 fix 針對 `getSettings`，**不直接套用我們 case**。
- 沒有看到專門針對「plugin 持有 idle TCP 連線 → host CPU 燒」的 issue。

---

## 已 commit 的 refactor（架構正確，雖沒解 CPU，可作為 baseline）

- `ec46167` (2026-05-08) — mqtt v5 → mqtt-connection；SVG data URI → 靜態 + setTitle；setImage/setTitle dedup；rollup `exportConditions: ["node"]`
- `a8f5f29` (2026-05-08) — `@elgato/streamdeck` SDK 2.0.1 → 2.1.0

---

## 想請 Codex 幫忙的方向

1. **還有什麼 ablation 沒試？** 看了上面 12 條，請挑出我們沒測過的軸線。
   特別是 host 端 / SDK 內部 / Node sandbox 配置 / OS 層級的角度。
2. **能不能把 plugin 的「有效 IPC」與 SD host 的反應 decouple？**
   例如：用 named pipe / 把 MQTT 訊息 batch 一秒再傳給 SDK / 把 Action 渲染搬到 worker？
3. **有沒有方法繞過 SDK 直接跟 SD host WebSocket 對話**，自己控制 IPC 節奏？
   觀察 SDK 2.1.0 部分有效，懷疑是 SDK 內部 message dispatch overhead。
4. **能不能透過 SD app log / Windows ETW trace 抓出 host 在燒什麼？**
   有沒有具體可執行的 profiling 步驟（不是叫用戶開 Performance Monitor 亂截）？
5. **是否值得 fork SDK 2.1.0 加 instrumentation** 看 message loop 時間分布？

---

## 不需要再做的事

- 改 plugin 程式碼想「修」CPU — 已經 ablate 過十幾種寫法。
- 升 SD app / SDK 等 fix — 已升到目前最新。
- 換 broker / 換訊息格式 — 與 broker 無關（已驗證）。

球在 Elgato。但如果有沒想到的角度，我們想知道。

---

## 檔案 / commit 對照

```
streamdeck-plugin/
├── package.json                    # @elgato/streamdeck ^2.1.0, mqtt-connection ^4.1.0
├── rollup.config.mjs              # exportConditions: ["node"]
├── src/mqtt-handler.ts            # net.Socket + mqtt-connection，pingreq 50s
├── src/plugin.ts                  # 註冊 4 actions，setTimeout(connectMqtt, 500)
├── src/actions/claude-status.ts   # setImage/setTitle dedup（lastIcon/lastTitle map）
└── com.duofilm.claude-monitor.sdPlugin/manifest.json   # Nodejs 20, SDKVersion 2
```

User repo root：`/home/duofilm/dotfiles`
近期相關 commits：`a8f5f29`, `ec46167`
