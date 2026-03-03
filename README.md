# Dotfiles

個人開發環境配置檔案，用於快速設置 WSL 開發環境。

## 架構

```
Windows                     WSL (Master)                       rpi5b (Slave, 192.168.88.10)
┌──────────────────┐       ┌──────────────────────┐           ┌──────────────────────────┐
│ IME_Indicator    │ MQTT  │ mosquitto (本機 HUB)  │           │ mosquitto (port 1883)    │
│  → ime/state ────┼──────→│   port 1883           │           │                          │
│                  │       │                      │           │ mqtt-led (GPIO 控制)     │
│ Stream Deck XL   │       │ tmux-mqtt-colors.sh  │  MQTT     │   └ claude/led topic     │
│  → SD Plugin ────┼───────┼─→ ime_loop ← 本機    │──────→   │   └ claude/buzzer topic  │
│  (Node.js SDK)   │       │   claude/led → RPi5B │           │   └ led-effects.json     │
│                  │       │                      │           │                          │
└──────────────────┘       │ Claude Code Hooks    │           │ ntfy (port 8080, Docker) │
                           │   → dispatch.sh ─────┼─ curl ──→│   └→ 手機推播             │
                           │                      │           └──────────────────────────┘
                           └──────────────────────┘
```

**設計原則**：
- WSL 是大腦（送語意指令 `{domain, state, project}`），rpi5b 是四肢（查本地映射表翻譯成硬體動作）
- IME 狀態走**本機 MQTT HUB**（`localhost:1883`），出門不依賴 RPi5B
- Claude LED / Stream Deck 走 **RPi5B MQTT**，不在家時靜默失敗
- 手機推播走 **ntfy.sh 雲端**（dispatch.sh 直接 curl），不依賴 RPi5B

## 目錄結構

```
dotfiles/
├── .claude/
│   └── skills/
│       └── add-hook.md
├── scripts/
│   ├── check-deploy.sh
│   ├── check-rpi5b-deploy.sh
│   ├── claude-dispatch.sh
│   ├── claude-hook.sh
│   ├── deploy-claude-overlay.sh
│   ├── deploy-ime-indicator.sh
│   ├── ime-mqtt-publisher.sh
│   ├── install-docker.sh
│   ├── install-lighthouse.sh
│   ├── install.sh
│   ├── launch-claude-overlay.sh
│   ├── notify.sh
│   ├── setup-claude-hooks.sh
│   ├── setup-rpi5b.sh
│   ├── test-hooks.sh
│   ├── test-ime-local-hub.sh
│   ├── test-mqtt.sh
│   ├── tmux-mqtt-colors.sh
│   ├── tmux-switch-project.sh
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

### RPi5B 部署

SD 卡壞了？新的 Pi 要設定？用 Ansible 一次搞定：

```bash
cd ~/dotfiles/ansible && ansible-playbook rpi5b.yml
```

會依序安裝：系統設定 → Docker（含 Pi-hole）→ MQTT → Tailscale → crontab

> `scripts/setup-rpi5b.sh` 為 Ansible 導入前的遺留腳本，已 deprecated。

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

通知流程：
- **LED 燈效**：`claude-hook.sh` → MQTT `claude/led` → mqtt-led → GPIO
- **手機推播**：`claude-dispatch.sh` → curl ntfy.sh 雲端（Stop 事件）

### MQTT Topic 規範

| Topic | 用途 | Payload |
|-------|------|---------|
| `claude/led` | RGB LED + Stream Deck | `{"domain": "claude\|ime", "state": "idle\|running\|...", "project": "..."}` |
| `claude/buzzer` | 蜂鳴器 | `{"frequency": Hz, "duration": ms}` |
| `system/stats` | RPi5B 系統狀態（Stream Deck） | `{"temp": °C, "ram": %}` |
| `system/stats/win` | Windows PC 系統狀態（Stream Deck） | `{"temp": °C, "freq": MHz, "ram": %}` |

### LED 燈效對應

可修改 `rpi5b/mqtt-led/led-effects.json`（修改後需 Ansible 部署到 RPi5B）：

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

### IME 中英指示器（Windows）

游標旁顯示中/英輸入法狀態圓點。使用 [duofilm18/IME_Indicator](https://github.com/duofilm18/IME_Indicator)（fork of RickAsli/IME_Indicator）的 Python 版本，透過 Win32 IMM API 偵測（單一資訊來源，不依賴按鍵追蹤）。

**前置需求：** Windows 安裝 Python 3.x（[python.org](https://www.python.org/)，勾選 Add to PATH）

**安裝：**
```powershell
cd C:\Users\<user>\dotfiles\windows
.\install.ps1
```

會自動：clone IME_Indicator → 安裝 pip 依賴 → 設定開機自動啟動

**更新（從 WSL 部署）：**
```bash
~/dotfiles/scripts/deploy-ime-indicator.sh          # 部署 + 自動重啟
~/dotfiles/scripts/deploy-ime-indicator.sh --diff    # 只看差異
```

### Stream Deck XL 監控（Windows）

使用 Elgato Stream Deck SDK (Node.js) 的原生 plugin，不獨佔 Stream Deck，可搭配其他 plugin。
透過 MQTT 訂閱 RPi5B broker，即時顯示 Claude Code 開發狀態。

**安裝：**
```bash
cd ~/dotfiles/streamdeck-plugin
npm install && npm run build
# 在 Windows 上: streamdeck link com.duofilm.claude-monitor.sdPlugin
```

**按鍵顯示：**

| 狀態 | 顏色 | 含義 |
|------|------|------|
| RUNNING | 藍色 | Claude 執行中 |
| WAITING | 黃色 | 需要你操作 |
| DONE | 綠色 | 任務完成 |
| IDLE | 橘色 | 閒置中 |
| ERROR | 紅色 | 出錯了 |

詳見 [streamdeck-plugin/README.md](streamdeck-plugin/README.md)。

### Windows PC 系統監控（Stream Deck）

透過 LibreHardwareMonitor + PowerShell 腳本，每分鐘將 CPU 溫度、頻率、RAM 發布到 MQTT，Stream Deck 即時顯示。

**前置需求：**
1. [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) — 以管理員身分背景執行
2. mosquitto-clients — `choco install mosquitto` 或手動安裝

**安裝：**
```powershell
cd C:\Users\<user>\dotfiles\windows
.\push-win-stats.ps1 -Install     # 註冊 Task Scheduler（每分鐘，需管理員）
.\push-win-stats.ps1 -Uninstall   # 移除
```

### rpi5b 服務列表（192.168.88.10）

| 服務 | Port | 用途 |
|------|------|------|
| mosquitto | 1883 | MQTT broker |
| Pi-hole | 53, 80 | DNS 廣告過濾（Docker） |
| ntfy | 8080 | 手機推播引擎（Docker） |
| mqtt-led | — | MQTT → GPIO（LED + 蜂鳴器） |
| Uptime Kuma | 3001 | 監控服務（Docker） |

### 測試指令

```bash
# Hook 測試（Bats）
sudo apt install bats
bats tests/                    # 全跑（LED 在無 RPi5B 時 skip）
bats tests/state_machine.bats  # 單檔
bats tests/ --filter "T1"     # 過濾

# MQTT 手動測試（需 mosquitto-clients）
sudo apt install mosquitto-clients
~/dotfiles/scripts/test-mqtt.sh          # 全部測試（LED）
~/dotfiles/scripts/test-mqtt.sh led      # LED 閃爍
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

**CI**：push 到 `ansible/` 目錄時，GitHub Actions 會自動跑 `ansible-lint` + `--syntax-check`（見 `.github/workflows/ansible-lint.yml`）。

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

> **2. 危險指令要三思**
>
> 在執行 `rm -rf`、`docker system prune -a`、`git reset --hard`、`chmod -R 777` 前，先想清楚。

---

## License

MIT
