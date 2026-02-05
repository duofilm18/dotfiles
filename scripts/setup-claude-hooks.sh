#!/bin/bash
# setup-claude-hooks.sh - 設定 Claude Code Hooks (通知功能)
# 用法: ~/dotfiles/scripts/setup-claude-hooks.sh

set -e

DOTFILES="$HOME/dotfiles"
EXAMPLE_FILE="$DOTFILES/wsl/claude-hooks.json.example"
CONFIG_FILE="$DOTFILES/wsl/claude-hooks.json"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"

echo "=========================================="
echo "  設定 Claude Code Hooks"
echo "=========================================="

# 檢查 jq 是否安裝
if ! command -v jq &>/dev/null; then
    echo "❌ 需要 jq，正在安裝..."
    sudo apt install -y jq
fi

# 檢查模板是否存在
if [ ! -f "$EXAMPLE_FILE" ]; then
    echo "❌ 找不到模板: $EXAMPLE_FILE"
    exit 1
fi

# 如果設定檔不存在，複製模板
if [ ! -f "$CONFIG_FILE" ]; then
    cp "$EXAMPLE_FILE" "$CONFIG_FILE"
    echo "📋 已複製模板到: $CONFIG_FILE"
    echo ""
    echo "⚠️  請編輯 $CONFIG_FILE 修改你的設定："
    echo "    - APPRISE_HOST: 你的 Apprise 伺服器 IP"
    echo "    - APPRISE_PORT: Apprise 連接埠 (預設 8000)"
    echo "    - APPRISE_TAG: 通知標籤 (預設 claude-notify)"
    echo ""
    read -p "編輯完成後按 Enter 繼續..."
fi

# 讀取設定
APPRISE_HOST=$(jq -r '.APPRISE_HOST' "$CONFIG_FILE")
APPRISE_PORT=$(jq -r '.APPRISE_PORT' "$CONFIG_FILE")
APPRISE_TAG=$(jq -r '.APPRISE_TAG' "$CONFIG_FILE")

# 驗證必要設定
if [ "$APPRISE_HOST" = "null" ] || [ -z "$APPRISE_HOST" ]; then
    echo "❌ 請在 $CONFIG_FILE 中設定 APPRISE_HOST"
    exit 1
fi

echo ""
echo "📡 使用設定："
echo "   Host: $APPRISE_HOST"
echo "   Port: $APPRISE_PORT"
echo "   Tag:  $APPRISE_TAG"

# 生成完整的 hooks JSON 結構
NEW_HOOKS_JSON=$(jq -n \
    --arg host "$APPRISE_HOST" \
    --arg port "$APPRISE_PORT" \
    --arg tag "$APPRISE_TAG" \
'{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://\($host):\($port)/notify/\($tag) -H '\''Content-Type: application/json'\'' -d '\''{\"event\": \"stop\", \"body\": \"✅ Claude 已完成回應\"}'\''"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://\($host):\($port)/notify/\($tag) -H '\''Content-Type: application/json'\'' -d '\''{\"event\": \"idle\", \"body\": \"⚠️ Claude 需要你的注意\"}'\''"
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://\($host):\($port)/notify/\($tag) -H '\''Content-Type: application/json'\'' -d '\''{\"event\": \"permission\", \"body\": \"🔴 Claude 需要權限確認\"}'\''"
          }
        ]
      }
    ]
  }
}')

# 確保 ~/.claude 目錄存在
mkdir -p "$CLAUDE_DIR"

# 如果 settings.json 不存在，建立空的
if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo "{}" > "$CLAUDE_SETTINGS"
    echo "📄 建立新的 settings.json"
fi

# 備份現有設定
BACKUP_FILE="$CLAUDE_SETTINGS.backup.$(date +%s)"
cp "$CLAUDE_SETTINGS" "$BACKUP_FILE"
echo "💾 備份: $BACKUP_FILE"

# 用 jq 合併 hooks 到 settings.json（覆蓋 hooks 部分，保留其他設定）
jq --argjson new_hooks "$NEW_HOOKS_JSON" '.hooks = $new_hooks.hooks' "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp"
mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"

echo ""
echo "=========================================="
echo "  ✅ Claude Code Hooks 設定完成！"
echo "=========================================="
echo ""
echo "📋 已設定的 Hooks："
echo "   • Stop          → ✅ Claude 已完成回應"
echo "   • idle_prompt   → ⚠️ Claude 需要你的注意"
echo "   • permission    → 🔴 Claude 需要權限確認"
echo ""
echo "測試通知："
echo "  curl -X POST http://${APPRISE_HOST}:${APPRISE_PORT}/notify/${APPRISE_TAG} \\"
echo "    -H 'Content-Type: application/json' -d '{\"body\": \"test\"}'"
echo ""
echo "重啟 Claude Code 後生效"
