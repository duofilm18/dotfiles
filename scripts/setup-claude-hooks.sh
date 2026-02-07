#!/bin/bash
# setup-claude-hooks.sh - 設定 Claude Code Hooks (MQTT 通知)
# 用法: ~/dotfiles/scripts/setup-claude-hooks.sh

set -e

DOTFILES="$HOME/dotfiles"
EXAMPLE_FILE="$DOTFILES/wsl/claude-hooks.json.example"
CONFIG_FILE="$DOTFILES/wsl/claude-hooks.json"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"

echo "=========================================="
echo "  設定 Claude Code Hooks (MQTT)"
echo "=========================================="

# 檢查必要工具
for cmd in jq mosquitto_pub; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ 需要 $cmd，正在安裝..."
        sudo apt install -y jq mosquitto-clients
        break
    fi
done

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
    echo "    - MQTT_HOST: rpi5b 的 IP"
    echo "    - MQTT_PORT: MQTT 連接埠 (預設 1883)"
    echo ""
    read -p "編輯完成後按 Enter 繼續..."
fi

# 讀取設定
MQTT_HOST=$(jq -r '.MQTT_HOST' "$CONFIG_FILE")
MQTT_PORT=$(jq -r '.MQTT_PORT' "$CONFIG_FILE")

# 驗證
if [ "$MQTT_HOST" = "null" ] || [ -z "$MQTT_HOST" ]; then
    echo "❌ 請在 $CONFIG_FILE 中設定 MQTT_HOST"
    exit 1
fi

echo ""
echo "📡 使用設定："
echo "   MQTT Host: $MQTT_HOST"
echo "   MQTT Port: $MQTT_PORT"

# 生成 hooks JSON（所有 hook 都呼叫腳本，腳本內部用 notify.sh → mosquitto_pub）
NEW_HOOKS_JSON=$(jq -n '{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash|Edit|Write|Read",
        "hooks": [
          {
            "type": "command",
            "command": "~/dotfiles/scripts/qwen-advisor.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/dotfiles/scripts/qwen-stop-summary.sh"
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
            "command": "~/dotfiles/scripts/notify.sh idle '\"'\"'⚠️ Claude 需要你的注意'\"'\"' '\"'\"'Claude 已閒置超過 60 秒，等待你的輸入'\"'\"'"
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "~/dotfiles/scripts/qwen-permission.sh"
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

# 合併 hooks 到 settings.json
jq --argjson new_hooks "$NEW_HOOKS_JSON" '.hooks = $new_hooks.hooks' "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp"
mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"

echo ""
echo "=========================================="
echo "  ✅ Claude Code Hooks 設定完成！"
echo "=========================================="
echo ""
echo "📋 已設定的 Hooks："
echo "   • Stop          → Qwen 總結 + MQTT 通知 + LED"
echo "   • idle_prompt   → MQTT 通知 + LED"
echo "   • permission    → Qwen 分析 + MQTT 通知 + LED"
echo "   • PostToolUse   → Qwen 專家分析 + MQTT 通知 + LED"
echo ""
echo "測試："
echo "  mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -t claude/notify \\"
echo "    -m '{\"title\":\"測試\",\"body\":\"MQTT 通知正常\"}'"
echo ""
echo "重啟 Claude Code 後生效"
