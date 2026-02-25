---
name: ime-mqtt-contract
description: >
  IME 狀態檔案介面契約。當修改 IME_Indicator、tmux-mqtt-colors.sh、
  或 tmux status bar 中 @ime_state 相關邏輯時使用。
  防止 payload 格式不一致（如 "chinese" vs "zh"）導致顯示失敗。
---

# IME 檔案介面契約

## 資料流

```
Windows IME_Indicator → C:\Temp\ime_state → tmux-mqtt-colors.sh（輪詢 200ms）→ tmux @ime_state
```

- IME 走**檔案介面**，不依賴 MQTT，install.ps1 更新 IME_Indicator 不影響 tmux
- Claude LED/Stream Deck 走 RPi5B MQTT（`$MQTT_HOST`），與 IME 無關

## 契約

| 項目 | 值 | 違反時的症狀 |
|------|-----|-------------|
| 檔案路徑 | `C:\Temp\ime_state`（WSL: `/mnt/c/Temp/ime_state`） | tmux 收不到 IME 狀態 |
| 內容（中文） | `zh` | tmux 判斷失敗，顏色不變 |
| 內容（英文） | `en` | 同上 |
| 寫入方 | IME_Indicator（唯一 writer） | — |
| 讀取方 | tmux-mqtt-colors.sh（輪詢 200ms） | — |

**檔案內容只允許 `zh` 或 `en`（純文字，無換行），不允許 `chinese`/`english` 或其他格式。**

## 各端對應

| 元件 | 檔案 | 關鍵行 |
|------|------|--------|
| Writer | `IME_Indicator/python_indicator/main.py` | `open(config.IME_STATE_FILE, 'w').write("zh" or "en")` |
| 路徑設定 | `IME_Indicator/python_indicator/config.py` | `IME_STATE_FILE = r"C:\Temp\ime_state"` |
| Reader | `scripts/tmux-mqtt-colors.sh` → `ime_loop()` | `cat "$IME_STATE_FILE"` 輪詢 200ms |
| 顯示判斷 | `shared/.tmux.conf` | `#{==:#{@ime_state},zh}` |

## 修改前必做

1. 確認 writer/reader 的格式一致（上表）
2. 跑測試：`~/dotfiles/scripts/test-ime-local-hub.sh`
3. 測試包含 E2E：寫檔案 → 驗證 tmux `@ime_state` 更新

## 歷史教訓

- IME_Indicator 發 `"chinese"`/`"english"`，tmux 判斷 `"zh"` → **顏色永遠不變**
- 靜態 grep 測試無法抓到這種不一致，必須有 E2E 測試
- IME_Indicator 曾有 MQTT publish，install.ps1 更新時 MQTT 邏輯被覆蓋 → tmux/LED 壞掉（發生 4-5 次）→ 改為檔案介面徹底解耦
