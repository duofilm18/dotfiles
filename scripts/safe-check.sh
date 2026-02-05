#!/bin/bash
# safe-check.sh - 使用 Ollama API 審查指令安全性
# 用法: ./safe-check.sh "要審查的指令"

OLLAMA_HOST="${OLLAMA_HOST:-localhost}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
MODEL="${OLLAMA_MODEL:-hf.co/sugiken/Ordis-1.5B-V355-VarGH-GGUF:Q4_K_M}"

if [ -z "$1" ]; then
    echo "用法: $0 \"要審查的指令\""
    echo "範例: $0 \"rm -rf /tmp/test\""
    exit 1
fi

COMMAND="$1"

PROMPT="你是一個 Linux 指令安全審查員。請分析以下指令的危險程度。

指令: $COMMAND

請判斷這個指令是否危險，只回答一個詞：
- DANGER: 如果指令可能造成資料遺失、系統損壞、或不可逆的操作
- SAFE: 如果指令是安全的

只回答 DANGER 或 SAFE，不要有其他文字。"

RESPONSE=$(curl -s "http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/generate" \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL\",
        \"prompt\": \"$PROMPT\",
        \"stream\": false,
        \"options\": {
            \"temperature\": 0.7,
            \"top_p\": 0.9,
            \"top_k\": 20,
            \"repeat_penalty\": 1.1
        }
    }" 2>/dev/null)

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
