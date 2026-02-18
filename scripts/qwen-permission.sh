#!/bin/bash
# qwen-permission.sh - 權限確認時，讓 Qwen 解釋 Claude 想做什麼
# 從 transcript 讀取 Claude 想執行的操作
# 使用排隊機制避免撞車
#
# 注意：LED 狀態由 claude-hook.sh 管理，本腳本只負責 Qwen 解釋

LOCK_FILE="/tmp/qwen-permission.lock"

INPUT=$(cat)

# 取得 transcript 路徑
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
MESSAGE=$(echo "$INPUT" | jq -r '.message // empty')

# 從 transcript 讀取最近的 tool_use（Claude 想執行的操作）
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    LAST_TOOL=$(tac "$TRANSCRIPT_PATH" | grep -m1 '"type":"tool_use"' || true)

    if [ -n "$LAST_TOOL" ]; then
        TOOL_NAME=$(echo "$LAST_TOOL" | jq -r '.message.content[0].name // empty' 2>/dev/null)
        TOOL_INPUT=$(echo "$LAST_TOOL" | jq -r '.message.content[0].input' 2>/dev/null)

        case "$TOOL_NAME" in
            Bash)
                COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null)
                DESC=$(echo "$TOOL_INPUT" | jq -r '.description // empty' 2>/dev/null)
                if [ -n "$DESC" ]; then
                    CONTEXT="Claude 想執行指令:
$COMMAND

說明: $DESC"
                else
                    CONTEXT="Claude 想執行指令:
$COMMAND"
                fi
                ;;
            Edit)
                FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
                OLD_STR=$(echo "$TOOL_INPUT" | jq -r '.old_string // empty' 2>/dev/null | head -c 200)
                NEW_STR=$(echo "$TOOL_INPUT" | jq -r '.new_string // empty' 2>/dev/null | head -c 200)
                CONTEXT="Claude 想修改檔案: $FILE_PATH

原本: $OLD_STR
改成: $NEW_STR"
                ;;
            Write)
                FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
                CONTENT=$(echo "$TOOL_INPUT" | jq -r '.content // empty' 2>/dev/null | head -c 300)
                CONTEXT="Claude 想寫入檔案: $FILE_PATH

內容: $CONTENT"
                ;;
            Read)
                FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
                CONTEXT="Claude 想讀取檔案: $FILE_PATH"
                ;;
            *)
                CONTEXT="$MESSAGE"
                ;;
        esac
    fi
fi

# 如果還是沒有 context，用 message
if [ -z "$CONTEXT" ]; then
    CONTEXT="$MESSAGE"
fi

# 使用 flock 排隊呼叫 Qwen
{
    flock -w 30 200 || exit 0

    MODEL="${OLLAMA_MODEL:-qwen2.5-coder:1.5b}"
    PROMPT="你是一位安全顧問。Claude AI 想執行一個操作，需要使用者確認權限。

$CONTEXT

請用繁體中文，用 1-2 句話簡單解釋：
1. 這個操作要做什麼
2. 有沒有需要注意的地方

簡潔有力。請務必用繁體中文回答！"

    RESULT=$(curl -s "http://localhost:11434/api/generate" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" '{model: $model, prompt: $prompt, stream: false}')" \
        2>/dev/null | jq -r '.response // empty')

    if [ -n "$RESULT" ]; then
        echo "$RESULT"
    fi

} 200>"$LOCK_FILE"

exit 0
