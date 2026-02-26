---
name: add-hook
description: >
  在 dotfiles 中新增 Claude Code Hook 的標準流程。當需要新增 Notification、
  PreToolUse、PostToolUse 等 hook，或修改現有 hook 的通知/燈效行為時使用。
---

# 新增 Claude Code Hook

## 前置條件

- 確認 hook 類型（Notification, PreToolUse, PostToolUse 等）
- 確認 rpi5b 的 MQTT broker 正常運行

## 架構

```
claude-dispatch.sh（事件分發器）
  ├→ claude-hook.sh → mosquitto_pub → claude/led → mqtt-led → GPIO（燈效）
  ├→ play-melody.sh → 音效
  └→ curl ntfy.sh   → 手機推播（Stop 事件，直接雲端，不經 MQTT）
```

通知由 `claude-dispatch.sh` 統一分發，燈效走 MQTT，手機推播直接 curl ntfy.sh 雲端。

## 步驟

### 1. 建立 hook 腳本

新增 `scripts/your-hook.sh`，在需要通知時呼叫 notify.sh：

```bash
SCRIPT_DIR="$(dirname "$0")"

# notify.sh <事件類型> <標題> <內容>
"$SCRIPT_DIR/notify.sh" your_event "標題" "內容"
```

### 2. 新增燈效（如需要）

編輯 `wsl/led-effects.json`，加入新事件的燈效：

```json
{
  "your_event": {"r": 255, "g": 128, "b": 0, "pattern": "blink", "times": 999}
}
```

> **重要：times 必須設 999（持續閃爍）。** 使用者戴耳機看影片，只閃幾下看不到。下一個事件會自動覆蓋。

### 3. 更新 setup 腳本

編輯 `scripts/setup-claude-hooks.sh`，在 `NEW_HOOKS_JSON` 中加入新 hook。

### 4. 更新文件

- 更新 `README.md` 說明新功能
- 如有需要，更新 `CLAUDE.md`

### 5. 測試

```bash
# 重新執行設定腳本
~/dotfiles/scripts/setup-claude-hooks.sh

# 測試
~/dotfiles/scripts/test-mqtt.sh
```

### 6. 提交

```bash
cd ~/dotfiles
git add -A
git status  # 確認變更內容
git commit -m "feat: add XXX hook"
git push    # 不要忘記 push！
```

## notify.sh 接口規範

所有通知 **必須** 透過 `scripts/notify.sh` 發送：

```bash
"$SCRIPT_DIR/notify.sh" <event_type> <title> <body>
```

### 參數

| 參數 | 說明 | 範例 |
|------|------|------|
| `event_type` | 事件類型，對應 led-effects.json 的 key | `stop`, `permission`, `advisor` |
| `title` | 通知標題，顯示在 ntfy 列表 | `✅ Claude 完成回應` |
| `body` | 通知內容，點進去看到的詳細資訊 | Qwen 總結、指令內容等 |

### 禁止事項

- **不可繞過 dispatch.sh 直接呼叫 mosquitto_pub** — dispatch.sh 是統一入口
- **不可省略 title** — ntfy 點進去會看不到內容

## MQTT Topic 規範

詳見 [mqtt-wiring](mqtt-wiring.md) 登記表。

| Topic | 用途 | Payload |
|-------|------|---------|
| `claude/led` | RGB LED 控制 | `{"r": 0-255, "g": 0-255, "b": 0-255, "pattern": "blink\|solid\|pulse", "times": N, "duration": N}` |
| `claude/buzzer` | 蜂鳴器控制 | `{"frequency": Hz, "duration": ms}` |

## Hook 類型參考

| Hook 類型 | Matcher | Emoji | 觸發時機 |
|-----------|---------|-------|----------|
| Stop | — | ✅ | 回應完成，等待輸入 |
| Notification | idle_prompt | ⚠️ | 閒置超過 60 秒 |
| Notification | permission_prompt | 🔴 | 需要權限確認 |
| PreToolUse | 工具名稱 | — | 執行工具前 |
| PostToolUse | 工具名稱 | — | 執行工具後 |

## 相關檔案

- `wsl/claude-hooks.json.example` - MQTT 設定模板
- `wsl/claude-hooks.json` - 實際設定（被 gitignore）
- `wsl/led-effects.json` - 事件→燈效對應表
- `scripts/notify.sh` - 通知單一入口（DRY）
- `scripts/setup-claude-hooks.sh` - 安裝腳本
- `~/.claude/settings.json` - Claude Code 設定檔
