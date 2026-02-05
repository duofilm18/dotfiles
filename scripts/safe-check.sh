#!/bin/bash
# safe-check.sh - 使用 Ollama API 審查指令安全性
# 用法: ./safe-check.sh "要審查的指令"

OLLAMA_HOST="${OLLAMA_HOST:-localhost}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
MODEL="${OLLAMA_MODEL:-qwen2.5-coder:1.5b}"

if [ -z "$1" ]; then
    echo "用法: $0 \"要審查的指令\""
    echo "範例: $0 \"rm -rf /tmp/test\""
    exit 1
fi

COMMAND="$1"

# 用 jq 建立 JSON（自動處理特殊字元）
JSON_PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --arg prompt "Is this Linux command dangerous? Command: $COMMAND. Answer SAFE if it only reads/lists/queries. Answer DANGER if it deletes/modifies/destroys. One word only: SAFE or DANGER" \
    '{model: $model, prompt: $prompt, stream: false}')

RESPONSE=$(curl -s "http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/generate" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$RESPONSE" ]; then
    echo "ERROR: 無法連接 Ollama API (${OLLAMA_HOST}:${OLLAMA_PORT})"
    echo "請確認 Ollama 是否在 Windows 上運行"
    exit 2
fi

# 解析 JSON：優先用 jq，沒有就 fallback 到 grep
if command -v jq &>/dev/null; then
    RESULT=$(echo "$RESPONSE" | jq -r '.response // empty' | tr -d '[:space:]')
else
    RESULT=$(echo "$RESPONSE" | grep -o '"response":"[^"]*"' | sed 's/"response":"//;s/"$//' | tr -d '[:space:]')
fi

if echo "$RESULT" | grep -qi "DANGER"; then
    echo "⚠️  DANGER - 這個指令可能有危險！"
    echo "指令: $COMMAND"
    exit 1
elif echo "$RESULT" | grep -qi "SAFE"; then
    echo "✅ SAFE - 這個指令看起來安全"
    echo "指令: $COMMAND"
    exit 0
else
    echo "⚠️  UNKNOWN - 無法判斷，請人工審查"
    echo "指令: $COMMAND"
    echo "AI 回應: $RESULT"
    exit 1
fi
