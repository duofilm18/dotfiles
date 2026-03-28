#!/bin/bash
# setup-codex-status.sh - 設定 Codex notify callback，接回既有提示系統

set -euo pipefail

CODEX_DIR="$HOME/.codex"
CODEX_CONFIG="$CODEX_DIR/config.toml"
NOTIFY_SCRIPT="$HOME/dotfiles/scripts/codex-notify.sh"
NOTIFY_LINE="notify = [\"$NOTIFY_SCRIPT\"]"

mkdir -p "$CODEX_DIR"

if [ ! -f "$CODEX_CONFIG" ]; then
    touch "$CODEX_CONFIG"
fi

cp "$CODEX_CONFIG" "$CODEX_CONFIG.backup.$(date +%s)"

if grep -q '^[[:space:]]*notify[[:space:]]*=' "$CODEX_CONFIG"; then
    sed -i "s|^[[:space:]]*notify[[:space:]]*=.*$|$NOTIFY_LINE|" "$CODEX_CONFIG"
else
    if [ -s "$CODEX_CONFIG" ]; then
        printf '\n%s\n' "$NOTIFY_LINE" >> "$CODEX_CONFIG"
    else
        printf '%s\n' "$NOTIFY_LINE" > "$CODEX_CONFIG"
    fi
fi

echo "Configured Codex notify hook in $CODEX_CONFIG"
echo "Reload shell if you also updated ~/.bash_aliases"
