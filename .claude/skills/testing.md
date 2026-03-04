---
name: testing
description: >
  全 repo 測試慣例：Bats（Hook 狀態機）+ pytest（Stream Deck / LED）。
  當需要新增或修改測試時使用。
---

# Testing（Bats）

## 結構

```
tests/
├── test_helper.bash       # 共用 setup/teardown/fire/assert
├── state_machine.bats     # T1-T7: 狀態轉換 + 智慧抑制
├── dedup.bats             # T8-T9: 2 秒去重
├── melody.bats            # T1-T6 dispatch 音效 + T10-T13 git 音效
├── dispatch.bats          # T-D1, T-D2: PROJECT 計算
├── flock.bats             # T-B1, T-B2: activity before lock
├── timeout.bats           # T-TO1~TO8: 背景 timeout + flock 釋放
├── state_publisher.bats   # SP-1~SP-10: build_payload、blink、debounce
├── deploy_integrity.bats  # DI-*: 靜態結構檢查（腳本、template、handler、接線）
└── led_e2e.bats           # LED 端到端（需 RPi5B MQTT）
```

## 執行

```bash
bats tests/                # 全跑（LED 在無 RPi5B 時 skip）
bats tests/melody.bats     # 單檔
bats tests/ --filter "T1"  # 過濾
```

## test_helper.bash API

| 函式 | 用途 |
|------|------|
| `common_setup` | 清除暫存檔、啟用 melody log 模式 |
| `common_teardown` | 清除暫存檔、關閉 melody log 模式 |
| `fire <event> [matcher] [json]` | 觸發 hook 事件 + melody dispatch |
| `assert_state <expected>` | 驗證 STATE_FILE 第一行 |
| `assert_melody <pattern>` | 驗證 MELODY_LOG 最後一行含 pattern |
| `assert_no_melody <before_count>` | 驗證 MELODY_LOG 行數未增加 |
| `melody_line_count` | 回傳 MELODY_LOG 目前行數 |

## 接線契約測試（deploy_integrity.bats）

介面層引用底層元件時，必須有靜態檢查確認兩端都存在且接線完整。
底層被移除時，測試要**立刻失敗**（而不是跟著消失）。

| 模式 | 測試做法 |
|------|----------|
| 腳本存在 | `[ -f "$DOTFILES/scripts/xxx.sh" ]` |
| 介面引用底層 | `grep -q 'xxx.sh' interface.sh` |
| 映射表一致 | 從 test_helper 抽名稱，逐一確認 dispatch 有對應 |

新增管線時，在 `deploy_integrity.bats` 加對應的 DI-* 測試。

## 新增測試步驟

1. 建立 `tests/<name>.bats`
2. `setup()` 內 `load test_helper; common_setup`
3. `teardown()` 內 `common_teardown`
4. 用 `@test "描述" { ... }` 撰寫測試
5. 每個 `@test` 獨立隔離，不依賴其他 test 的狀態

## LED E2E 特殊流程

- `setup()` 偵測 MQTT broker，不通 → `skip "MQTT unreachable"`
- 用 `mosquitto_sub -C 1 -W 5` 等待 RPi5 ACK（5 秒 timeout）
- ACK JSON 含 `r/g/b/pattern/is_lit/gpio`
- 比對 `rpi5b/mqtt-led/led-effects.json` 預期值
- GPIO `is_lit=true` 表示 LED 實際有亮

# Testing（pytest / Stream Deck）

## 結構

```
streamdeck/
└── test_rebuild.py    # Stream Deck Consumer 純邏輯測試
```

## 執行

```bash
cd streamdeck && python3 -m pytest test_rebuild.py -v
```

## Mock 基礎

測試檔開頭用 `sys.modules` 替換所有硬體依賴（StreamDeck USB、PIL、paho），
`reset()` autouse fixture 每個測試前重置全域狀態 + mock deck + patch `threading.Timer`。

## 慣例

- `make_msg(topic, state)` 建立 mock MQTT message
- `state=None` 產生空 payload（模擬專案移除）
- 測試只驗純邏輯（按鍵分配、狀態對照、callback 路由），不碰真實硬體
- subprocess / _run_powershell 用 `patch` 隔離

## Thread Safety 測試

`TestThreadSafety` 用真正的多 thread 重現 race condition：

- `threading.Barrier` 同步啟動，迴圈數百次提高觸發機率
- `render_button` / `render_date_button` / `_clear_all_buttons` 用 `patch` mock 掉硬體
- 驗 `_state_lock` 存在且不卡死（`acquire(timeout=1)`）

# Testing（pytest / MQTT LED Service）

## 結構

```
rpi5b/mqtt-led/
└── test_mqtt_led.py   # LED 效果引擎純邏輯測試
```

## 執行

```bash
cd rpi5b/mqtt-led && python3 -m pytest test_mqtt_led.py -v
```

## Mock 基礎

`sys.modules` 替換 lgpio / gpiozero / paho，`builtins.open` + `json.load` mock config.json。
`reset()` fixture 重置 `_cancel`、`_melody_cancel`、`_off_timer`、`led` mock。

## 覆蓋範圍

- payload 解析（malformed JSON、預設值、RGB 正規化）
- effect dispatch（solid/blink/pulse/rainbow 路由、參數傳遞）
- timer 取消機制（_stop_custom、新效果取消舊效果）
- rainbow 可取消（_cancel event）+ 完成後自動關燈
- buzzer / melody dispatch（背景 thread、取消正在播放的旋律）
- ACK 回報

# TDD 工作流

修 bug 或加功能時，優先採用 RED → GREEN → REFACTOR 循環：

## 步驟

1. **RED** — 先寫測試重現問題（測試應 FAIL 或偶發 crash）
   - Race condition：用 `threading.Barrier` + 迴圈數百次重現
   - 邏輯 bug：直接 assert 預期行為
   - 跑測試確認 FAIL，證明 bug 存在

2. **GREEN** — 最小改動讓測試通過
   - 只改必要的 code，不順便重構
   - 跑全部測試確認新舊都 PASS

3. **REFACTOR**（可選）— 通過後再整理
   - 提取 helper、改名、清理重複
   - 每次小改動後跑測試確認沒壞

## 實務要點

- Thread safety 修復用 **Snapshot Under Lock** 模式：lock 內拍快照，lock 外做 I/O
- `bare except` → `log.debug(..., exc_info=True)` 保留除錯資訊
- 測試命名：`test_<場景>_<預期行為>`，一看就懂驗什麼
