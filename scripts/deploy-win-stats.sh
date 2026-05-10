#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/../windows/deploy-paths.sh"

install -d "$DEPLOY_WIN_STATS_DIR"
install -m 0644 "$(dirname "$0")/../windows/push-win-stats.ps1" "$DEPLOY_WIN_STATS_MAIN"
install -m 0644 "$(dirname "$0")/../windows/run-win-stats.vbs" "$DEPLOY_WIN_STATS_RUNNER"
install -m 0644 "$(dirname "$0")/../windows/deploy-paths.ps1" "$DEPLOY_WIN_STATS_DIR/deploy-paths.ps1"

# PowerShell scripts on Windows should keep CRLF to avoid parsing issues.
sed -i 's/\r*$/\r/' "$DEPLOY_WIN_STATS_MAIN" "$DEPLOY_WIN_STATS_RUNNER" "$DEPLOY_WIN_STATS_DIR/deploy-paths.ps1"

echo "Deployed win-stats scripts to: $DEPLOY_WIN_STATS_DIR"
echo "Next: run in Windows PowerShell"
echo "  & '$DEPLOY_WIN_STATS_MAIN' -Install"
