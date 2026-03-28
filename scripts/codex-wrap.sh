#!/bin/bash
# codex-wrap.sh - Codex wrapper，啟動 session watcher 並維持既有 tmux/MQTT 架構

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_BIN="${CODEX_REAL_BIN:-$(type -P codex)}"

if [ -z "$CODEX_BIN" ] || [ ! -x "$CODEX_BIN" ]; then
    echo "codex binary not found" >&2
    exit 127
fi

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_BASE="$(basename "$PROJECT_ROOT")"
PROJECT_KEY="${CODEX_PROJECT_KEY:-codex:${PROJECT_BASE}}"
START_EPOCH="$(date +%s)"
WATCH_PID=""

cleanup() {
    if [ -n "$WATCH_PID" ]; then
        kill "$WATCH_PID" 2>/dev/null || true
        wait "$WATCH_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

if [ -n "${TMUX:-}" ]; then
    tmux rename-window "$PROJECT_KEY" 2>/dev/null || true
    tmux set-window-option @project "$PROJECT_KEY" 2>/dev/null || true
fi

"$SCRIPT_DIR/codex-session-watch.sh" "$PWD" "$PROJECT_KEY" "$START_EPOCH" &
WATCH_PID=$!

"$CODEX_BIN" "$@"
