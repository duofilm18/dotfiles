# Stream Deck MQTT Monitor

透過 MQTT 訂閱開發狀態，即時顯示在 Stream Deck 按鍵上。

```
MQTT Broker (RPi5B)              Windows
┌──────────────────┐            ┌──────────────────────┐
│ mosquitto :1883  │            │ streamdeck_mqtt.py   │
│  claude/led ─────┼── sub ────┤  paho-mqtt (TCP)     │
│  (retain=true)   │            │  python-streamdeck   │
└──────────────────┘            │  → Stream Deck XL    │
                                └──────────────────────┘
```

## 按鍵狀態

| 狀態 | 顏色 | 含義 |
|------|------|------|
| RUNNING | 🟦 藍色 | Claude 執行中 |
| WAITING | 🟨 黃色 | 需要你操作 |
| DONE | 🟩 綠色 | 任務完成 |
| IDLE | 🟧 橘色 | 閒置中 |
| ERROR | 🟥 紅色 | 出錯了 |

---

## Windows 安裝步驟

### Step 1: 安裝 Python

從 [python.org](https://www.python.org/downloads/) 下載安裝。

> **不要用 Microsoft Store 版**，PATH 設定會有問題。

安裝時勾選 **「Add Python to PATH」**。

驗證：

```powershell
python --version
```

### Step 2: 安裝 hidapi.dll

Stream Deck 庫需要 `hidapi.dll` 來溝通 USB 裝置。

1. 到 [libusb/hidapi Releases](https://github.com/libusb/hidapi/releases) 下載最新版
2. 選擇 `hidapi-win.zip`
3. 解壓後找到 `x64/hidapi.dll`（如果你的 Python 是 64-bit）
4. 把 `hidapi.dll` 複製到 **以下任一位置**：
   - Python 安裝目錄（例如 `C:\Python312\`）
   - 或任何在 `%PATH%` 裡的資料夾

驗證：

```powershell
python -c "import ctypes; ctypes.cdll.LoadLibrary('hidapi')" && echo OK
```

### Step 3: 安裝 Python 套件

```powershell
cd C:\Users\你的帳號\dotfiles\streamdeck
pip install -r requirements.txt
```

requirements.txt 內容：
- `streamdeck` — Stream Deck 硬體控制
- `Pillow` — 圖片生成（按鍵上的文字和顏色）
- `paho-mqtt` — MQTT 客戶端

### Step 4: 設定

```powershell
copy config.json.example config.json
```

編輯 `config.json`：

```json
{
  "mqtt_broker": "192.168.88.10",
  "mqtt_port": 1883,
  "mqtt_topic": "claude/led",
  "deck_brightness": 30,
  "claude_button_index": 0
}
```

| 欄位 | 說明 | 預設值 |
|------|------|--------|
| `mqtt_broker` | MQTT broker IP（RPi5B 的 LAN IP） | `192.168.88.10` |
| `mqtt_port` | MQTT port | `1883` |
| `mqtt_topic` | 訂閱的 topic | `claude/led` |
| `deck_brightness` | Stream Deck 亮度 (0-100) | `30` |
| `claude_button_index` | 狀態顯示在第幾個按鍵 (0 = 左上角) | `0` |

### Step 5: 關閉官方 Stream Deck 軟體

本程式直接透過 USB 控制 Stream Deck 硬體，**無法與官方軟體同時使用**。

在系統匣（右下角）找到 Stream Deck 圖示 → 右鍵 → 結束。

### Step 6: 執行

```powershell
cd C:\Users\你的帳號\dotfiles\streamdeck
python streamdeck_mqtt.py
```

成功會看到：

```
Stream Deck: Stream Deck XL (32 keys)
Connecting to MQTT 192.168.88.10:1883...
MQTT connected (rc=0), subscribed to claude/led
```

按鍵 0（左上角）會顯示目前 Claude Code 狀態。

按 `Ctrl+C` 停止。

---

## 故障排除

### 找不到 Stream Deck

```
No Stream Deck found.
```

檢查：
1. `hidapi.dll` 有放到 PATH 裡嗎？
2. 官方 Stream Deck 軟體有關嗎？
3. USB 線有接好嗎？（試換 USB 孔）

### MQTT 連不上

```
ConnectionRefusedError: [Errno 111] Connection refused
```

檢查：
1. RPi5B 有開機嗎？
2. `ping 192.168.88.10` 能通嗎？
3. Mosquitto 有在跑嗎？（`ssh root@192.168.88.10 "systemctl status mosquitto"`）

### 按鍵顯示 "?" 不會變

按鍵初始顯示 "?" 代表還沒收到 MQTT 訊息。可能原因：
1. Claude Code 還沒觸發任何 hook
2. 手動測試：在 WSL 執行 `~/dotfiles/scripts/notify.sh running`

---

## 開機自動啟動

### 一鍵安裝（推薦）

安裝腳本會自動完成：Python 套件安裝、hidapi.dll 下載、config.json 建立、Task Scheduler 排程。

```powershell
cd C:\Users\你的帳號\dotfiles\streamdeck
powershell -ExecutionPolicy Bypass -File install.ps1
```

> 換新電腦時再跑一次就好。

### 手動設定 Task Scheduler

如果你想手動設定：

```powershell
# 建立排程
$action = New-ScheduledTaskAction -Execute "C:\Python312\pythonw.exe" -Argument "C:\Users\你的帳號\dotfiles\streamdeck\streamdeck_mqtt.py" -WorkingDirectory "C:\Users\你的帳號\dotfiles\streamdeck"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "StreamDeck MQTT Monitor" -Action $action -Trigger $trigger -Settings $settings

# 立即啟動
Start-ScheduledTask -TaskName "StreamDeck MQTT Monitor"

# 移除排程
Unregister-ScheduledTask -TaskName "StreamDeck MQTT Monitor" -Confirm:$false
```

> `pythonw.exe` 不會跳出 console 視窗。

---

## 相關專案

- [python-elgato-streamdeck](https://github.com/abcminiuser/python-elgato-streamdeck) — 本專案使用的 Stream Deck Python 庫
- [LukasOchmann/streamdeck-mqtt](https://github.com/LukasOchmann/streamdeck-mqtt) — 類似專案（Linux/Docker 版）
