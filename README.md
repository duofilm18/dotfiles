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
│   ├── claude-hook.sh
│   ├── install-docker.sh
│   ├── install.sh
│   ├── notify.sh
│   ├── play-melody.sh
│   ├── safe-check.sh
│   ├── setup-claude-hooks.sh
│   ├── setup-rpi5b.sh
│   ├── test-hooks.sh
│   ├── test-mqtt.sh
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

### 快速安裝（WSL）

```bash
git clone https://github.com/duofilm18/dotfiles.git ~/dotfiles
~/dotfiles/scripts/install.sh
```

### RPi5B 一鍵部署

SD 卡壞了？新的 Pi 要設定？一個指令搞定：

```bash
~/dotfiles/scripts/setup-rpi5b.sh
```

會依序安裝：系統設定 → Docker（含 Pi-hole）→ MQTT → Tailscale → crontab

需要互動的步驟會暫停提示，不會跳過。

### 安全審查工具

> 在執行危險指令前，先用 Ollama 審查

```bash
~/dotfiles/scripts/safe-check.sh "rm -rf /tmp/test"
```

需要先在 **Windows** 上啟動 Ollama。

### Claude Code Hooks（MQTT 通知 + LED 燈效）

讓 Claude Code 在需要你注意時，透過 MQTT 發送手機通知 + LED 燈效。

```bash
# 1. 部署 RPi5B（包含 MQTT 服務）
~/dotfiles/scripts/setup-rpi5b.sh

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
| `claude/led` | RGB LED | `{"r": 0-255, "g": 0-255, "b": 0-255, "pattern": "blink\|solid\|pulse\|rainbow", "times": N, "duration": N, "interval": N}` |
| `claude/buzzer` | 蜂鳴器 | `{"frequency": Hz, "duration": ms}` |

### LED 燈效對應

可修改 `wsl/led-effects.json`（修改後不需重啟任何服務）：

| 事件 | 顏色 | 效果 | 含義 |
|------|------|------|------|
| Claude 執行中 (running) | 綠色 | 慢呼吸 | 在跑，不用管 |
| Claude 完成 (stop) | 七色 | 彩虹閃 3 輪 → 關燈 | 做完了 |
| 需要權限 (permission) | 紅色 | 快閃 + 嗶 | 卡住了，快來 |
| Qwen 分析 (advisor) | 藍色 | 慢呼吸 | 背景處理，不用管 |
| 閒置提醒 (idle) | 橘色 | 閃爍 | 60 秒沒操作，提醒回來 |
| 關燈 (off) | — | 熄滅 | — |

> **設計原則：blink 只給需要提醒的狀態（permission, idle），背景處理用 pulse 呼吸燈。** 下一個事件會自動覆蓋前一個燈效。

接線方式見 `rpi5b/mqtt-led/config.json.example`。
目前使用共陰極 RGB LED（麵包板 + 電阻），`common_anode: false`。

### rpi5b 服務列表（192.168.88.10）

| 服務 | Port | 用途 |
|------|------|------|
| mosquitto | 1883 | MQTT broker |
| Pi-hole | 53, 80 | DNS 廣告過濾（Docker） |
| ntfy | 8080 | 手機推播引擎（Docker） |
| mqtt-led | — | MQTT → GPIO（LED + 蜂鳴器） |
| mqtt-ntfy | — | MQTT → ntfy 橋接 |
| Uptime Kuma | 3001 | 監控服務（Docker） |

### 測試指令

```bash
# WSL 需安裝 mosquitto-clients
sudo apt install mosquitto-clients

# 全部測試（LED + ntfy）
~/dotfiles/scripts/test-mqtt.sh

# 單獨測試
~/dotfiles/scripts/test-mqtt.sh led      # LED 閃爍
~/dotfiles/scripts/test-mqtt.sh ntfy     # 手機通知
~/dotfiles/scripts/test-mqtt.sh buzzer   # 蜂鳴器
~/dotfiles/scripts/test-mqtt.sh off      # 關燈
```

### Ansible 部署（推薦）

統一管理 WSL、RPi5B、Tinkerboard，可取代 shell script 部署。

```bash
# 安裝 Ansible
sudo apt install ansible
ansible-galaxy collection install ansible.posix community.docker

# 部署全部機器
cd ~/dotfiles/ansible && ansible-playbook site.yml

# 只部署特定機器
ansible-playbook rpi5b.yml
ansible-playbook wsl.yml

# 只跑特定步驟
ansible-playbook rpi5b.yml --tags mqtt

# 乾跑模式（不會實際修改）
ansible-playbook rpi5b.yml --check --diff
```

> 機器特定敏感值（Uptime Kuma token 等）放在 `ansible/host_vars/rpi5b.yml`（已 gitignore），模板見 `rpi5b.yml.example`。

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
