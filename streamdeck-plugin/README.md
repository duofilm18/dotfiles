# Stream Deck SDK Plugin — Claude Monitor

使用 Elgato Stream Deck SDK (Node.js/TypeScript) 重寫的 Claude Code 監控插件。

與現有 `streamdeck/` (Python) 並存，差別在於：
- 不獨佔 Stream Deck，可搭配其他 plugin
- 由 Stream Deck app 管理硬體與生命週期
- SVG 渲染（零依賴，取代 PIL）
- 設定透過 Property Inspector UI

## 架構

```
RPi5B MQTT Broker ←── WSL Publisher (tmux-mqtt-colors.sh)
       ↑                ↑
       │                └── RPi5B cron (push-temp.sh → system/stats)
       │                └── Windows Task Scheduler (push-win-stats.ps1 → system/stats/win)
       ↓
Stream Deck App → Claude Monitor Plugin (此目錄)
       ↓
Stream Deck XL 按鍵
```

MQTT publisher (`tmux-mqtt-colors.sh`) 與 broker 完全不變，只重寫 consumer 端。

## 前置需求

- **Stream Deck app** 6.9+
- **Node.js** 20+ （由 Stream Deck app 內建，不需額外安裝）
- **Stream Deck CLI**：`npm install -g @elgato/cli`

## 建置

```bash
cd streamdeck-plugin
npm install
npm run build
```

## 安裝（開發模式）

在 Windows 上執行：

```powershell
cd \\wsl$\Ubuntu\home\duofilm\dotfiles\streamdeck-plugin
streamdeck link com.duofilm.claude-monitor.sdPlugin
```

重啟 Stream Deck app 後，在 action 列表看到 "Claude Monitor" category。

## 使用

1. 拖 N 個 **Claude Status** action 到按鍵上（建議 8 個）
2. 拖 1 個 **Claude Date** action 到按鍵上
3. 點任一 action → Property Inspector 設定 MQTT Broker IP/Port
4. 在 WSL 執行 Claude Code → 按鍵自動顯示專案狀態

### 按鍵行為

| Action | 顯示 | 按下 |
|--------|------|------|
| Claude Status | 專案名 + 狀態色塊 | 切 tmux window + 喚起 Terminal |
| Claude Date | YYYY / MMDD | 貼上今天日期 (YYYYMMDD) |
| System Stats | RPi5B 溫度 + RAM | — |
| Win Stats | Win PC 溫度 + 頻率 + RAM | — |

### 狀態顏色

| 狀態 | 背景色 | 閃爍 |
|------|--------|------|
| idle | 橘 (255,13,0) | 閃白 |
| running | 藍 (0,0,255) | — |
| waiting | 黃 (255,255,0) | 閃白 |
| completed | 綠 (0,180,0) | — |
| error | 紅 (255,0,0) | — |
| off | 暗灰 (30,30,30) | — |

## 目錄結構

```
streamdeck-plugin/
├── src/
│   ├── plugin.ts              # 進入點
│   ├── mqtt-handler.ts        # MQTT + Rebuild Phase
│   ├── renderer.ts            # SVG 渲染
│   ├── types.ts               # 型別 + 色彩常數
│   └── actions/
│       ├── claude-status.ts   # 狀態 action
│       ├── claude-date.ts     # 日期 action
│       ├── system-stats.ts    # RPi5B 系統狀態
│       └── win-stats.ts       # Windows PC 系統狀態
├── com.duofilm.claude-monitor.sdPlugin/
│   ├── manifest.json
│   ├── bin/                   # Rollup 輸出
│   ├── imgs/                  # SVG icons
│   └── ui/
│       └── global-settings.html
├── package.json
├── tsconfig.json
└── rollup.config.mjs
```

## 測試

```bash
# 發送測試訊息
mosquitto_pub -h 192.168.88.10 -t claude/led/test -m '{"state":"running"}'

# 清除
mosquitto_pub -h 192.168.88.10 -t claude/led/test -n
```
