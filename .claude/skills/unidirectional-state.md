---
name: unidirectional-state
description: >
  單向資料流與被動顯示器的架構規範。當設計涉及「狀態源 → 發佈者 → 消費者」
  的系統時使用，例如 MQTT、Stream Deck、LED 等多端同步顯示。
  適用場景：出現幽靈狀態、殘留顯示、多端狀態不一致、重啟後顯示過期資料等問題。
---

# 單向資料流：消除幽靈狀態

## 問題

多端顯示系統（Stream Deck、LED、tmux tab）各自讀寫狀態，
導致某端殘留已不存在的資料（幽靈按鍵、幽靈燈效）。
根因：**沒有 single source of truth**，各端自行解讀 + 快取。

## Pattern：單向資料流

```
Source of Truth → [State Publisher] → Message Bus → Consumer(s)
     (tmux)          (輪詢+發佈)        (MQTT)      (Deck, LED)
```

### 四條規則

| 規則 | 做法 | 原因 |
|------|------|------|
| Single Source of Truth | 狀態只寫入一處（如 tmux window option） | 避免多端各自寫入導致不一致 |
| 單向流出 | Source → Publisher → Consumer，不反向寫回 | 消除循環依賴與競爭 |
| 被動顯示器 | Consumer 啟動時清空，不保留舊狀態，只渲染收到的 | 杜絕硬體/記憶體殘留 |
| 啟動清理 | Publisher 啟動時清除 bus 上所有殘留，從 source 重建 | 重啟後不會有幽靈 |

## 各角色職責

### Source of Truth（狀態寫入端）

```bash
# Hook 直接寫 tmux，不碰 message bus
tmux set-window-option -t ":$IDX" @claude_state "$state"
```

- 只寫一處，不發 MQTT、不通知 consumer
- 狀態檔（`/tmp/xxx`）僅供 hook 內部去重，不是 source of truth

### State Publisher（輪詢 + 發佈）

```bash
# 啟動清理：清除所有 retained
mosquitto_pub -r -t "topic" -n   # 空 payload = 清除 retained

# 主迴圈：每秒輪詢 source，偵測變化才發佈
declare -A prev_states
while true; do
    # 讀 source of truth
    # diff prev_states vs current
    # 有變化 → publish retained
    # 偵測消失 → publish 空 retained（清除）
    sleep 1
done
```

- 同步清理完成後才進入主迴圈（避免競爭）
- 偵測項目消失 → 主動清除 message bus 上的殘留

### Consumer（被動顯示器 + Rebuild Phase）

**關鍵認知：MQTT retained ≠ 狀態同步協議。**
retained 只保證「存在的 state」送達，已刪除的 topic 不會通知新 subscriber。
因此 Consumer 必須視每次 MQTT 連線為 cold start（Stateless Consumer Reconstruction）。

```python
_rebuilding = False
_rebuild_timer = None

def on_connect(client, ...):
    _rebuilding = True
    reset_internal_state()       # 清空 cache，不碰硬體
    client.subscribe("topic/+")
    # Fallback：無 retained 時仍完成 rebuild
    start_timer(1.0, finish_rebuild)

def on_message(msg):
    if not msg.payload:
        remove_from_cache()      # 更新 cache（rebuild 中不碰硬體）
        return
    update_cache(msg)            # MQTT → cache
    if _rebuilding:
        reset_timer(0.3, finish_rebuild)  # debounce
    else:
        render(msg)              # 正常：逐訊息即時 render

def finish_rebuild():
    _rebuilding = False
    clear_all_display()          # 先清空硬體
    batch_render_from_cache()    # 一次性繪製所有按鍵
```

核心原則：
- **reconnect = cold start**：每次連線清空 cache，由 retained 重建
- **MQTT → cache → batch render**：UI 不逐訊息 render，收集完再一次性繪製
- debounce 300ms 無新訊息 → rebuild 完成；fallback 1s 防無 retained 卡住
- blink_loop 等背景 thread 在 rebuild 期間暫停，避免渲染半成品

## 反模式

| 反模式 | 問題 | 正確做法 |
|--------|------|----------|
| Consumer 寫回 source | 循環依賴，狀態打架 | Consumer 只讀不寫 |
| 各端直接發 MQTT | 沒人負責清除，幽靈殘留 | 統一由 Publisher 發佈 |
| Consumer 信任本地快取 | 重連後幽靈殘留（已刪 topic 不通知） | reconnect = cold start |
| Consumer 逐訊息 render | 重連時閃爍、按鍵亂跳 | Rebuild Phase batch render |
| Consumer 用 TTL 清除 | idle 專案被誤刪、timing = truth | 不猜測，只信 retained |
| Publisher 背景清理 | 與主迴圈 publish 競爭 | 同步清理完再進主迴圈 |

## 例外：不同 Domain 的反向流

IME 狀態（`ime/state` → tmux `@ime_state`）是 MQTT→tmux 的反向流，
但這是**不同 domain**（輸入法 vs Claude 狀態），不違反單向原則。
判斷標準：同一份資料不能有兩個寫入端。

## 參考實作

| 檔案 | 角色 |
|------|------|
| `scripts/claude-hook.sh` | Source：寫 tmux `@claude_state` |
| `scripts/tmux-mqtt-colors.sh` | Publisher：輪詢 tmux → 發 MQTT |
| `streamdeck/streamdeck_mqtt.py` | Consumer：被動顯示 MQTT 狀態 |
| `rpi5b/mqtt-led/mqtt_led.py` | Consumer：LED 燈效 |
