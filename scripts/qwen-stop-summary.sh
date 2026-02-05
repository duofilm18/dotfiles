#!/bin/bash
# qwen-stop-summary.sh - Claude 回應完成時，讓 Qwen 分析回應內容
# 從 transcript 檔案讀取 Claude 最後的回應
# 使用排隊機制避免撞車

LOCK_FILE="/tmp/qwen-advisor.lock"

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

# 從 transcript 讀取最後的 text 類型記錄（Claude 的文字回應）
CLAUDE_RESPONSE=$(tac "$TRANSCRIPT_PATH" | head -30 | grep '"type":"text"' | head -1 | jq -r '.message.content[0].text // empty' 2>/dev/null | head -c 800)

# 如果沒找到，發簡單通知
if [ -z "$CLAUDE_RESPONSE" ] || [ "$CLAUDE_RESPONSE" = "null" ]; then
    curl -s -X POST http://192.168.88.10:8000/notify/claude-notify \
        -H "Content-Type: application/json" \
        -d '{"event": "stop", "body": "✅ Claude 已完成回應"}' \
        >/dev/null 2>&1
    exit 0
fi

# 使用 flock 排隊呼叫 Qwen
{
    flock -w 30 200 || exit 0

    MODEL="${OLLAMA_MODEL:-qwen2.5-coder:1.5b}"
    PROMPT="你是使用者的助理。Claude AI 剛回應了以下內容，請用繁體中文總結重點（2-3句話），讓使用者快速了解 Claude 說了什麼、問了什麼、或建議了什麼。

Claude 的回應：
$CLAUDE_RESPONSE

簡潔有力，像在幫使用者讀重點。請務必用繁體中文回答！"

    RESULT=$(curl -s "http://localhost:11434/api/generate" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" '{model: $model, prompt: $prompt, stream: false}')" \
        2>/dev/null | jq -r '.response // empty')

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

} 200>"$LOCK_FILE"

exit 0
