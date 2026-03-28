#!/bin/bash
# codex-notify.sh - Codex notify callback，轉接完成事件到既有狀態/音效系統

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RAW_NOTIFICATION="${1:-}"

[ -n "$RAW_NOTIFICATION" ] || exit 0

TYPE=$(printf '%s\n' "$RAW_NOTIFICATION" | jq -r '.type // empty' 2>/dev/null || true)
[ "$TYPE" = "agent-turn-complete" ] || exit 0

CWD=$(printf '%s\n' "$RAW_NOTIFICATION" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -n "$CWD" ] || exit 0
[ -d "$CWD" ] || exit 0

PROJECT_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$CWD")"
PROJECT_BASE="$(basename "$PROJECT_ROOT")"
PROJECT_KEY="codex:${PROJECT_BASE}"

cd "$CWD"
AI_LABEL="Codex" PROJECT_KEY="$PROJECT_KEY" WINDOW_NAME="$PROJECT_KEY" \
    "$SCRIPT_DIR/claude-dispatch.sh" Stop
