# Dotfiles

個人開發環境配置檔案，用於快速設置 WSL 開發環境。

## 架構

```
WSL (Master)                              rpi5b (Slave, 192.168.88.10)
┌──────────────────────┐                  ┌──────────────────────────┐
│ Claude Code Hooks    │                  │ mosquitto (port 1883)    │
│   → qwen-*.sh        │   MQTT           │                          │
│   → notify.sh ───────┼──────────────→  │ mqtt-led (GPIO 控制)     │
│                      │  mosquitto_pub   │   └ claude/led topic     │
│ wsl/led-effects.json │                  │   └ claude/buzzer topic  │
│ (燈效設定,大腦在這)   │                  │                          │
│                      │                  │ mqtt-ntfy (ntfy 橋接)    │
│ Qwen (Ollama)        │                  │   └ claude/notify topic  │
│ (本地 AI 摘要)        │                  │   └→ ntfy (port 8080)    │
└──────────────────────┘                  └──────────────────────────┘
```

**設計原則**：WSL 是大腦（決定燈效、通知內容），rpi5b 是四肢（只執行 GPIO 指令）。rpi5b 部署一次很少動。

## 目錄結構

```
dotfiles/
├── .claude/
│   └── skills/
│       └── add-hook.md
├── scripts/
│   ├── install-docker.sh
│   ├── install.sh
│   ├── notify.sh
│   ├── qwen-advisor.sh
│   ├── qwen-permission.sh
│   ├── qwen-queue.sh
│   ├── qwen-stop-summary.sh
│   ├── safe-check.sh
│   ├── setup-claude-hooks.sh
│   ├── setup-rpi5b-mqtt.sh
│   └── update-readme.sh
├── shared/
│   ├── .tmux.conf
│   └── .vimrc
├── wsl/
│   ├── .bash_aliases
│   └── claude-hooks.json.example
├── CLAUDE.md
└── README.md
```

## 使用方式

### 快速安裝

```bash
git clone https://github.com/duofilm18/dotfiles.git ~/dotfiles
~/dotfiles/scripts/install.sh
```

### 安全審查工具

> 在執行危險指令前，先用 Ollama 審查

```bash
~/dotfiles/scripts/safe-check.sh "rm -rf /tmp/test"
```

需要先在 **Windows** 上啟動 Ollama。

### Claude Code Hooks（MQTT 通知 + LED 燈效）

讓 Claude Code 在需要你注意時，透過 MQTT 發送手機通知 + LED 燈效。

```bash
# 1. 部署 MQTT 服務到 rpi5b（一次性）
~/dotfiles/scripts/setup-rpi5b-mqtt.sh

# 2. 複製模板並修改設定
cp ~/dotfiles/wsl/claude-hooks.json.example ~/dotfiles/wsl/claude-hooks.json
vim ~/dotfiles/wsl/claude-hooks.json  # 修改 MQTT_HOST

# 3. 設定 Claude Code Hooks
~/dotfiles/scripts/setup-claude-hooks.sh

# 4. 重啟 Claude Code
```

### 通知接口（給 AI 和開發者看）

所有通知 **必須** 透過 `scripts/notify.sh` 發送：

```bash
# notify.sh <事件類型> <標題> <內容>
~/dotfiles/scripts/notify.sh stop "✅ Claude 完成回應" "Qwen 總結內容..."
```

notify.sh 會自動：
1. 發送 `claude/notify` → 手機推播
2. 讀取 `wsl/led-effects.json` → 發送 `claude/led` → LED 燈效

### MQTT Topic 規範

| Topic | 用途 | Payload |
|-------|------|---------|
| `claude/notify` | 手機推播 | `{"title": "...", "body": "..."}` |
| `claude/led` | RGB LED | `{"r": 0-255, "g": 0-255, "b": 0-255, "pattern": "blink\|solid\|pulse", "times": N, "duration": N}` |
| `claude/buzzer` | 蜂鳴器 | `{"frequency": Hz, "duration": ms}` |

### LED 燈效對應

可修改 `wsl/led-effects.json`（修改後不需重啟任何服務）：

| 事件 | 顏色 | 效果 |
|------|------|------|
| Claude 完成回應 (stop) | 綠色 | 閃 2 下 |
| 需要權限確認 (permission) | 紅色 | 持續亮 30 秒 |
| Qwen 專家分析 (advisor) | 藍色 | 閃 1 下 |

接線方式見 `rpi5b/mqtt-led/config.json.example`。

### rpi5b 服務列表（192.168.88.10）

| 服務 | Port | 用途 |
|------|------|------|
| mosquitto | 1883 | MQTT broker |
| ntfy | 8080 | 手機推播引擎 |
| mqtt-led | — | MQTT → GPIO（LED + 蜂鳴器） |
| mqtt-ntfy | — | MQTT → ntfy 橋接 |
| Homepage | 3000 | 儀表板 |
| Uptime Kuma | 3001 | 監控服務 |
| Portainer | 9000 | Docker 管理 |

### 測試指令

```bash
# WSL 需安裝 mosquitto-clients
sudo apt install mosquitto-clients

# 測試手機通知
mosquitto_pub -h 192.168.88.10 -t claude/notify \
    -m '{"title":"測試","body":"MQTT 通知正常"}'

# 測試 LED（綠燈閃 2 下）
mosquitto_pub -h 192.168.88.10 -t claude/led \
    -m '{"r":0,"g":255,"b":0,"pattern":"blink","times":2}'

# 測試蜂鳴器
mosquitto_pub -h 192.168.88.10 -t claude/buzzer \
    -m '{"frequency":1000,"duration":500}'
```

---

## 慘案教訓

> 這些是用血淚換來的經驗，請務必遵守！

> **1. 重要資料要 git push**
>
> 本地的 git 歷史在重灌時會一起消失。只有 push 到 GitHub 的才是真正的備份。

```bash
git add .
git commit -m "update"
git push  # 這步不能忘！
```

> **2. 危險指令用 safe-check 審查**
>
> 在執行 `rm`、`prune`、`clean` 相關指令前，先審查。

**特別危險的指令：**
- `rm -rf` - 刪除檔案/目錄
- `docker system prune -a` - 清除所有 Docker 資源
- `git reset --hard` - 丟棄所有未提交的更改
- `chmod -R 777` - 危險的權限設定

> **3. Ollama 裝 Windows，不要裝 WSL**
>
> WSL 的 Ollama 會佔用大量記憶體，Windows 版本可以更好地利用 GPU。
> WSL 透過 `localhost:11434` 直接存取 Windows 的 Ollama。

---

## License

MIT
