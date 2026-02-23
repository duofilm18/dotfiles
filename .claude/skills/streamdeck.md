---
name: streamdeck
description: >
  Stream Deck 硬體規格與操作規範。當修改 streamdeck_mqtt.py、調整按鍵佈局、
  變更字型大小、或需要啟動/重啟 Stream Deck 腳本時使用。
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
Windows: streamdeck_mqtt.py (Consumer，被動顯示器)
       ↓
Stream Deck USB
```

腳本跑在 **Windows**（`C:\Python312\pythonw.exe`），不是 WSL。

## 啟動 / 重啟

```bash
# 從 WSL 啟動（透過 powershell.exe）
powershell.exe -Command "Start-Process -FilePath 'C:\Python312\pythonw.exe' \
  -ArgumentList '\\\\wsl$\\Ubuntu\\home\\duofilm\\dotfiles\\streamdeck\\streamdeck_mqtt.py' \
  -WindowStyle Hidden"

# 查看執行中的 Python 進程
powershell.exe -Command "Get-WmiObject Win32_Process -Filter \"Name='pythonw.exe'\" \
  | Select-Object ProcessId, CommandLine | Format-List"

# 停止（排除 IME Indicator）
powershell.exe -Command "Get-WmiObject Win32_Process -Filter \"Name='pythonw.exe'\" \
  | Where-Object { \$_.CommandLine -like '*streamdeck*' } \
  | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }"
```

## 按鍵佈局（config.json）

| 設定 | 預設 | 說明 |
|------|------|------|
| `claude_button_index` | 0 | 專案按鍵起始 index |
| `date_button_index` | -1 | 日期按鍵 index（-1 = 停用） |
| `max_projects` | 8 | 最多幾個專案按鍵 |
| `font_size_title` | 16 | 專案名稱字型 |
| `font_size_state` | 18 | 狀態標籤字型 |
| `font_size_date` | 32 | 日期按鍵字型 |

專案按鍵自動分配時會跳過 `date_button_index`。

## 注意事項

- `config.json` 在 `.gitignore`，機器特定設定不進 repo
- `config.json.example` 是模板，新增設定要同步更新
- Windows 上的 `pythonw.exe` 不會有 console 輸出，除錯時改用 `python.exe`
- IME Indicator 也用 `pythonw.exe`，停止進程時要排除它
