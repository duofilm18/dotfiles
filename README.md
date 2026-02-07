# Dotfiles

個人開發環境配置檔案，用於快速設置 WSL 開發環境。

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

### Claude Code Hooks（MQTT 通知）

讓 Claude Code 在需要你注意時，透過 MQTT 發送手機通知 + LED 燈效。

架構：WSL（Master）→ MQTT → rpi5b（Slave）

```bash
# 1. 複製模板並修改設定
cp ~/dotfiles/wsl/claude-hooks.json.example ~/dotfiles/wsl/claude-hooks.json
vim ~/dotfiles/wsl/claude-hooks.json  # 修改 MQTT_HOST

# 2. 部署 MQTT 服務到 rpi5b
~/dotfiles/scripts/setup-rpi5b-mqtt.sh

# 3. 設定 Claude Code Hooks
~/dotfiles/scripts/setup-claude-hooks.sh

# 4. 重啟 Claude Code
```

### LED 燈效通知

Claude Code 事件觸發 RGB LED 燈效，戴耳機時也能注意到狀態變化。

燈效對應（可修改 `wsl/led-effects.json`）：

| 事件 | 顏色 | 效果 |
|------|------|------|
| Claude 完成回應 | 綠色 | 閃 2 下 |
| 需要權限確認 | 紅色 | 持續亮 30 秒 |
| Qwen 專家分析 | 藍色 | 閃 1 下 |

接線方式見 `rpi5b/mqtt-led/config.json.example`。

測試：

```bash
# 測試通知
mosquitto_pub -h 192.168.88.10 -t claude/notify \
    -m '{"title":"測試","body":"MQTT 通知正常"}'

# 測試 LED
mosquitto_pub -h 192.168.88.10 -t claude/led \
    -m '{"r":0,"g":255,"b":0,"pattern":"blink","times":2}'
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
