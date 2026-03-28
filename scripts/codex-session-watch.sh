#!/bin/bash
# codex-session-watch.sh - 監看 Codex session log，轉接到既有 tmux hook 狀態流
#
# 用法: codex-session-watch.sh <cwd> <project_key> [start_epoch]

set -euo pipefail

TARGET_CWD="${1:?missing cwd}"
PROJECT_KEY="${2:?missing project key}"
START_EPOCH="${3:-$(date +%s)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSIONS_DIR="${CODEX_HOME:-$HOME/.codex}/sessions"
DISCOVERY_WINDOW="${CODEX_DISCOVERY_WINDOW:-180}"
DISCOVERY_TIMEOUT="${CODEX_DISCOVERY_TIMEOUT:-20}"

dispatch() {
    AI_LABEL="Codex" PROJECT_KEY="$PROJECT_KEY" WINDOW_NAME="$PROJECT_KEY" \
        "$SCRIPT_DIR/claude-dispatch.sh" "$1" "${2:-}"
}

find_session_file() {
    local now candidate meta cwd mtime meta_epoch best_file best_epoch

    while true; do
        now=$(date +%s)
        if [ $((now - START_EPOCH)) -ge "$DISCOVERY_TIMEOUT" ]; then
            return 1
        fi

        best_file=""
        best_epoch=0

        while IFS= read -r candidate; do
            [ -f "$candidate" ] || continue

            mtime=$(stat -c %Y "$candidate" 2>/dev/null || echo 0)
            if [ "$mtime" -lt $((START_EPOCH - DISCOVERY_WINDOW)) ]; then
                continue
            fi

            meta=$(grep -m1 '"type":"session_meta"' "$candidate" 2>/dev/null || true)
            [ -n "$meta" ] || continue

            cwd=$(printf '%s\n' "$meta" | jq -r '.payload.cwd // empty' 2>/dev/null || true)
            [ "$cwd" = "$TARGET_CWD" ] || continue

            meta_epoch=$(printf '%s\n' "$meta" | jq -r '.payload.timestamp // empty' 2>/dev/null | xargs -r -I{} date -d "{}" +%s 2>/dev/null || echo 0)
            if [ "$meta_epoch" -lt "$START_EPOCH" ]; then
                continue
            fi

            if [ "$meta_epoch" -ge "$best_epoch" ]; then
                best_epoch="$meta_epoch"
                best_file="$candidate"
            fi
        done < <(find "$SESSIONS_DIR" -type f -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -20 | cut -d' ' -f2-)

        if [ -n "$best_file" ]; then
            printf '%s\n' "$best_file"
            return 0
        fi

        sleep 0.5
    done
}

handle_line() {
    local line="$1"
    local root_type payload_type approval

    root_type=$(printf '%s\n' "$line" | jq -r '.type // empty' 2>/dev/null || true)
    case "$root_type" in
        event_msg)
            payload_type=$(printf '%s\n' "$line" | jq -r '.payload.type // empty' 2>/dev/null || true)
            case "$payload_type" in
                task_started|user_message)
                    dispatch UserPromptSubmit
                    ;;
                task_complete)
                    dispatch Stop
                    ;;
            esac
            ;;
        response_item)
            payload_type=$(printf '%s\n' "$line" | jq -r '.payload.type // empty' 2>/dev/null || true)
            case "$payload_type" in
                function_call)
                    approval=$(printf '%s\n' "$line" | jq -r '.payload.arguments | fromjson? | .sandbox_permissions? // empty' 2>/dev/null || true)
                    if [ "$approval" = "require_escalated" ]; then
                        dispatch PermissionRequest
                    fi
                    ;;
                function_call_output)
                    dispatch PostToolUse AskUserQuestion
                    ;;
            esac
            ;;
    esac
}

main() {
    local session_file

    [ -d "$SESSIONS_DIR" ] || exit 0

    session_file=$(find_session_file) || exit 0

    while IFS= read -r line; do
        handle_line "$line"
    done < "$session_file"

    tail -Fn0 "$session_file" 2>/dev/null | while IFS= read -r line; do
        handle_line "$line"
    done
}

main "$@"
