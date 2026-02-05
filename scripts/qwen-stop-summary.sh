#!/bin/bash
# qwen-stop-summary.sh - Claude 回應完成時，讓 Qwen 分析回應內容
# 從 transcript 檔案讀取 Claude 最後的回應

INPUT=$(cat)

# 取得 transcript 路徑
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    curl -s -X POST http://192.168.88.10:8000/notify/claude-notify \
        -H "Content-Type: application/json" \
        -d '{"event": "stop", "body": "✅ Claude 已完成回應"}' \
        >/dev/null 2>&1
    exit 0
fi

# 從 transcript 讀取 Claude 最後的回應
# transcript 是 JSONL 格式，每行一個 JSON
CLAUDE_RESPONSE=$(tac "$TRANSCRIPT_PATH" | head -20 | grep '"type":"assistant"' | head -1 | jq -r '.message // empty' 2>/dev/null | head -c 800)

# 如果沒找到 message，試試 content
if [ -z "$CLAUDE_RESPONSE" ] || [ "$CLAUDE_RESPONSE" = "null" ]; then
    CLAUDE_RESPONSE=$(tac "$TRANSCRIPT_PATH" | head -20 | grep '"type":"assistant"' | head -1 | jq -r '.content // empty' 2>/dev/null | head -c 800)
fi

# 還是沒有，發簡單通知
if [ -z "$CLAUDE_RESPONSE" ] || [ "$CLAUDE_RESPONSE" = "null" ]; then
    curl -s -X POST http://192.168.88.10:8000/notify/claude-notify \
        -H "Content-Type: application/json" \
        -d '{"event": "stop", "body": "✅ Claude 已完成回應"}' \
        >/dev/null 2>&1
    exit 0
fi

# 呼叫 Qwen 分析 Claude 的回應
MODEL="${OLLAMA_MODEL:-qwen2.5-coder:1.5b}"
JSON_PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --arg prompt "你是使用者的助理。Claude AI 剛回應了以下內容，請用繁體中文總結重點（2-3句話），讓使用者快速了解 Claude 說了什麼、問了什麼、或建議了什麼。

Claude 的回應：
$CLAUDE_RESPONSE

簡潔有力，像在幫使用者讀重點。請務必用繁體中文回答！" \
    '{model: $model, prompt: $prompt, stream: false}')

RESULT=$(curl -s "http://localhost:11434/api/generate" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" 2>/dev/null | jq -r '.response // empty')

if [ -n "$RESULT" ]; then
    NOTIFY_BODY="✅ Claude 完成回應

💡 Qwen 總結:
$RESULT"
else
    NOTIFY_BODY="✅ Claude 已完成回應"
fi

curl -s -X POST http://192.168.88.10:8000/notify/claude-notify \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg body "$NOTIFY_BODY" '{event: "stop", body: $body}')" \
    >/dev/null 2>&1

exit 0
