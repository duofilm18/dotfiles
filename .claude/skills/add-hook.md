---
name: add-hook
description: >
  Claude Code Hook 與 dispatch.sh 事件分發器的標準流程。當需要新增 Notification、
  PreToolUse、PostToolUse 等 hook，或修改 claude-dispatch.sh 的通知行為時使用。
---

# 新增 Claude Code Hook

## 架構

```
claude-dispatch.sh（事件分發器）
  └→ curl ntfy.sh → 手機推播（Stop 事件，直接雲端，不經 MQTT）
```

通知由 `claude-dispatch.sh` 統一分發，手機推播直接 curl ntfy.sh 雲端。

## 步驟

### 1. 在 dispatch.sh 加入事件處理

所有 hook 事件由 `scripts/claude-dispatch.sh` 統一分發。在對應的 if 區塊加入邏輯：

```bash
# 手機推播範例
if [ "$EVENT" = "YourEvent" ]; then
    curl -s -X POST "https://ntfy.sh/claude-notify-rpi5b" \
        -H "Title: $PROJECT" -d "描述" &>/dev/null &
fi
```

### 2. 更新 setup 腳本

編輯 `scripts/setup-claude-hooks.sh`，在 `NEW_HOOKS_JSON` 中加入新 hook。

### 3. 測試

```bash
# 重新執行設定腳本
~/dotfiles/scripts/setup-claude-hooks.sh
```

### 4. 提交

```bash
cd ~/dotfiles
git add -A
git status  # 確認變更內容
git commit -m "feat: add XXX hook"
git push    # 不要忘記 push！
```

## 禁止事項

- **不可繞過 dispatch.sh** — dispatch.sh 是統一入口
- **不可省略 ntfy title** — 手機推播點進去會看不到內容

## Hook 類型參考

| Hook 類型 | Matcher | 觸發時機 |
|-----------|---------|----------|
| Stop | — | 回應完成，等待輸入 |
| Notification | idle_prompt | 閒置超過 60 秒 |
| Notification | permission_prompt | 需要權限確認 |
| PreToolUse | 工具名稱 | 執行工具前 |
| PostToolUse | 工具名稱 | 執行工具後 |

## 相關檔案

- `scripts/claude-dispatch.sh` - 事件分發器（統一入口）
- `scripts/setup-claude-hooks.sh` - 安裝腳本
- `~/.claude/settings.json` - Claude Code 設定檔
