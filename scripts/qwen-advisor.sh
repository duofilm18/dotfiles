#!/bin/bash
# qwen-advisor.sh - Qwen 專家顧問
# 在 Claude 執行完操作後，分析並給出專業意見
# 支援 Bash、Edit、Write、Read 等工具

# 從 stdin 讀取 JSON 輸入
INPUT=$(cat)

# 提取工具名稱
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# 根據不同工具提取資訊
case "$TOOL_NAME" in
    Bash)
        COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
        OUTPUT=$(echo "$INPUT" | jq -r '.tool_response.stdout // .tool_response // empty' | head -c 800)

        # 簡單指令不需要評論
        if [[ "$COMMAND" =~ ^(ls|pwd|cd|echo|cat|head|tail|which|whoami)( |$) ]]; then
            exit 0
        fi

        CONTEXT="📝 執行的指令:
$COMMAND

📤 執行結果:
$OUTPUT"
        PROMPT_HINT="分析這個 Linux 指令做了什麼，結果代表什麼意思，有什麼值得注意的地方。"
        ICON="🖥️"
        ;;

    Edit)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
        OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' | head -c 300)
        NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' | head -c 300)

        CONTEXT="📄 修改檔案: $FILE_PATH

🔴 原本內容:
$OLD_STRING

🟢 改成:
$NEW_STRING"
        PROMPT_HINT="解釋這個程式碼修改做了什麼改變，為什麼這樣改，有什麼影響。"
        ICON="✏️"
        ;;

    Write)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
        CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' | head -c 500)

        CONTEXT="📄 寫入檔案: $FILE_PATH

📝 內容:
$CONTENT"
        PROMPT_HINT="解釋這個檔案的用途，寫入的內容做什麼用。"
        ICON="📝"
        ;;

    Read)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

        # Read 操作比較簡單，只需簡短說明
        CONTEXT="📖 讀取檔案: $FILE_PATH"
        PROMPT_HINT="簡單說明這是什麼類型的檔案，通常用來做什麼。"
        ICON="📖"
        ;;

    *)
        # 不支援的工具，跳過
        exit 0
        ;;
esac

# 如果沒有內容，不做任何事
if [ -z "$CONTEXT" ]; then
    exit 0
fi

# 呼叫 Qwen 給意見
MODEL="${OLLAMA_MODEL:-qwen2.5-coder:1.5b}"
JSON_PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --arg prompt "你是一位程式開發專家顧問。Claude AI 剛執行了一個操作，請用繁體中文給出簡短專業意見（2-4句話）。

$CONTEXT

$PROMPT_HINT

簡潔有力，像個專業顧問在旁邊給建議。請務必用繁體中文回答！" \
    '{model: $model, prompt: $prompt, stream: false}')

RESPONSE=$(curl -s "http://localhost:11434/api/generate" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" 2>/dev/null)

RESULT=$(echo "$RESPONSE" | jq -r '.response // empty')

# 如果有回應，發送到通知系統
if [ -n "$RESULT" ]; then
    NOTIFY_BODY="$ICON Qwen 專家分析

$CONTEXT

💡 分析:
$RESULT"

    curl -s -X POST http://192.168.88.10:8000/notify/claude-notify \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg body "$NOTIFY_BODY" '{event: "qwen-advisor", body: $body}')" \
        >/dev/null 2>&1
fi

exit 0
