---
name: ime-mqtt-contract
description: >
  IME 狀態 MQTT 資料流契約。當修改 IME_Indicator、tmux-mqtt-colors.sh、
  或 tmux status bar 中 @ime_state 相關邏輯時使用。
  防止 payload 格式不一致（如 "chinese" vs "zh"）導致顯示失敗。
---

# IME MQTT 資料流契約

## 資料流

```
Windows IME_Indicator → localhost:1883 (ime/state) → tmux-mqtt-colors.sh → tmux @ime_state
```

- IME 走**本機 MQTT HUB**（`localhost:1883`），不依賴 RPi5B，出門也能用
- Claude LED/Stream Deck 走 RPi5B（`$MQTT_HOST`），不在家時靜默失敗

## 契約

| 項目 | 值 | 違反時的症狀 |
|------|-----|-------------|
| MQTT broker | `localhost:1883` | tmux 收不到 IME 狀態 |
| Topic | `ime/state` | 同上 |
| Payload（中文） | `zh` | tmux 判斷失敗，顏色不變 |
| Payload（英文） | `en` | 同上 |
| Retain | `true` | 新 subscriber 收不到初始狀態 |

**Payload 只允許 `zh` 或 `en`，不允許 `chinese`/`english` 或其他格式。**

## 各端對應

| 元件 | 檔案 | 關鍵行 |
|------|------|--------|
| Publisher | `IME_Indicator/python_indicator/main.py` | `publish(MQTT_IME_TOPIC, "zh" if ... else "en")` |
| Broker 設定 | `IME_Indicator/python_indicator/config.py` | `MQTT_BROKER = "localhost"` |
| Subscriber | `scripts/tmux-mqtt-colors.sh` → `ime_loop()` | `mosquitto_sub -h "localhost" -p 1883 -t "ime/state"` |
| 顯示判斷 | `shared/.tmux.conf` | `#{==:#{@ime_state},zh}` |

## 修改前必做

1. 確認四端的格式一致（上表）
2. 跑測試：`~/dotfiles/scripts/test-ime-local-hub.sh`
3. 測試包含 E2E：模擬 publish → 驗證 tmux `@ime_state` 更新

## 歷史教訓

- IME_Indicator 發 `"chinese"`/`"english"`，tmux 判斷 `"zh"` → **顏色永遠不變**
- 靜態 grep 測試無法抓到這種不一致，必須有 E2E 測試
