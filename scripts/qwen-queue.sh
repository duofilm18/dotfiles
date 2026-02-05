#!/bin/bash
# qwen-queue.sh - 排隊機制，確保 Qwen 請求按順序處理
# 用法: echo "prompt" | qwen-queue.sh [event_type]

LOCK_FILE="/tmp/qwen-advisor.lock"
EVENT_TYPE="${1:-general}"

# 使用 flock 排隊（等待最多 30 秒）
exec 200>"$LOCK_FILE"
flock -w 30 200 || {
    echo "等待超時，跳過此次分析" >&2
    exit 0
}

# 從 stdin 讀取 prompt
PROMPT=$(cat)

if [ -z "$PROMPT" ]; then
    exit 0
fi

# 呼叫 Qwen
MODEL="${OLLAMA_MODEL:-qwen2.5-coder:1.5b}"
RESULT=$(curl -s "http://localhost:11434/api/generate" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" '{model: $model, prompt: $prompt, stream: false}')" \
    2>/dev/null | jq -r '.response // empty')

echo "$RESULT"
