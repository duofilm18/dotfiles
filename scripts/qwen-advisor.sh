#!/bin/bash
# qwen-advisor.sh - Qwen 專家顧問
# 在旁邊觀察 Claude 的操作，給出專業意見
# 不阻止執行，只是提供建議

# 從 stdin 讀取 JSON 輸入
INPUT=$(cat)

# 提取指令內容
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# 如果沒有指令，不做任何事
if [ -z "$COMMAND" ]; then
    exit 0
fi

# 簡單指令不需要評論（減少噪音）
if [[ "$COMMAND" =~ ^(ls|pwd|cd|echo|cat|head|tail|which|whoami)( |$) ]]; then
    exit 0
fi

# 呼叫 Qwen 給意見
MODEL="${OLLAMA_MODEL:-qwen2.5-coder:1.5b}"
JSON_PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --arg prompt "你是一位 Linux 專家，正在旁邊觀察。請針對這個指令給出簡短意見（2-3句話）：
指令: $COMMAND

可以包括：
- 這個指令做什麼
- 有什麼要注意的
- 有沒有更好的做法
- 潛在風險（如果有）

用繁體中文回答，簡潔有力。" \
    '{model: $model, prompt: $prompt, stream: false}')

RESPONSE=$(curl -s "http://localhost:11434/api/generate" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" 2>/dev/null)

RESULT=$(echo "$RESPONSE" | jq -r '.response // empty')

# 如果有回應，顯示 Qwen 的意見
if [ -n "$RESULT" ]; then
    echo ""
    echo "╭─────────────────────────────────────────╮"
    echo "│ 🧠 Qwen 專家意見                        │"
    echo "├─────────────────────────────────────────┤"
    echo "$RESULT" | fold -s -w 43 | sed 's/^/│ /; s/$/ │/'
    echo "╰─────────────────────────────────────────╯"
    echo ""
fi

# 永遠放行，不阻止
exit 0
