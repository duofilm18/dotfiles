# 新增 Claude Code Hook

在 dotfiles 中新增 Claude Code Hook 的標準流程。

## 前置條件

- 確認 hook 類型（Notification, PreToolUse, PostToolUse 等）
- 確認需要的變數（IP, endpoint 等）
- 確認 Apprise 服務是否需要新增通知渠道

## 步驟

### 1. 更新模板

編輯 `wsl/claude-hooks.json.example`，加入新變數：

```json
{
  "APPRISE_HOST": "192.168.88.10",
  "APPRISE_PORT": "8000",
  "APPRISE_TAG": "claude-notify",
  "NEW_VAR": "預設值"
}
```

> ⚠️ JSON 最後一個欄位不能有逗號

### 2. 更新腳本

編輯 `scripts/setup-claude-hooks.sh`：

```bash
# 讀取新變數
NEW_VAR=$(jq -r '.NEW_VAR' "$CONFIG_FILE")

# 在 HOOKS_JSON 中加入對應的 hook 邏輯
```

### 3. 更新文件

- 更新 `README.md` 說明新功能
- 如有需要，更新 `CLAUDE.md`

### 4. 測試

```bash
# 重新執行設定腳本
~/dotfiles/scripts/setup-claude-hooks.sh

# 測試通知是否正常
curl -X POST http://${APPRISE_HOST}:${APPRISE_PORT}/notify/${APPRISE_TAG} -d 'test'
```

### 5. 提交

```bash
cd ~/dotfiles
git add -A
git status  # 確認變更內容
git commit -m "feat: add XXX hook"
git push    # 不要忘記 push！
```

## Hook 類型參考

| Hook 類型 | 觸發時機 |
|-----------|----------|
| Notification | Claude 需要用戶注意時 |
| PreToolUse | 執行工具前 |
| PostToolUse | 執行工具後 |
| Stop | 會話結束時 |

## 相關檔案

- `wsl/claude-hooks.json.example` - 設定模板
- `wsl/claude-hooks.json` - 實際設定（被 gitignore）
- `scripts/setup-claude-hooks.sh` - 安裝腳本
- `~/.claude/settings.json` - Claude Code 設定檔
