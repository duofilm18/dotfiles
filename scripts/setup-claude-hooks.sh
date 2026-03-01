#!/bin/bash
# setup-claude-hooks.sh - 設定 Claude Code Hooks（ntfy 推播 + deploy guard）
# 用法: ~/dotfiles/scripts/setup-claude-hooks.sh

set -e

CLAUDE_DIR="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"

echo "=========================================="
echo "  設定 Claude Code Hooks"
echo "=========================================="

# 檢查必要工具
if ! command -v jq &>/dev/null; then
    echo "❌ 需要 jq，正在安裝..."
    sudo apt install -y jq
fi

# 生成 hooks JSON
NEW_HOOKS_JSON=$(cat <<'HOOKSJSON'
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/dotfiles/scripts/claude-dispatch.sh Stop",
            "async": true
          },
          {
            "type": "command",
            "command": "~/dotfiles/scripts/check-deploy.sh"
          }
        ]
      }
    ]
  }
}
HOOKSJSON
)

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

# 合併 hooks 到 settings.json
jq --argjson new_hooks "$NEW_HOOKS_JSON" '.hooks = $new_hooks.hooks' "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp"
mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"

echo ""
echo "=========================================="
echo "  ✅ Claude Code Hooks 設定完成！"
echo "=========================================="
echo ""
echo "📋 已設定的 Hooks："
echo "   • Stop → ntfy 手機推播 + deploy guard 檢查"
echo ""
echo "測試："
echo "  curl -s -X POST 'https://ntfy.sh/claude-notify-rpi5b' \\"
echo "    -H 'Title: test' -d 'ntfy works'"
echo ""
echo "重啟 Claude Code 後生效"
