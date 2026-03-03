#!/bin/bash
# launch-claude-overlay.sh - 從 tmux run-shell 啟動 Claude Status Overlay
#
# Singleton：檢查 Windows 進程是否已存在，避免重複開。
# 由 .tmux.conf run-shell -b 呼叫。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../windows/deploy-paths.sh"

# 檢查 deploy 目標是否存在
if [ ! -f "$DEPLOY_OVERLAY_MAIN" ]; then
    exit 0
fi

# Singleton：檢查是否已在執行
ALREADY_RUNNING=$(powershell.exe -Command "
    \$found = \$false
    Get-Process pythonw -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            \$cmd = (Get-WmiObject Win32_Process -Filter \"ProcessId=\$(\$_.Id)\").CommandLine
            if (\$cmd -like '*claude-overlay*') { \$found = \$true }
        } catch {}
    }
    \$found
" 2>/dev/null | tr -d '\r')

if [ "$ALREADY_RUNNING" = "True" ]; then
    exit 0
fi

# 啟動
WIN_MAIN=$(echo "$DEPLOY_OVERLAY_MAIN" | sed 's|/mnt/c|C:|;s|/|\\|g')
WIN_DIR=$(echo "$DEPLOY_OVERLAY_DIR" | sed 's|/mnt/c|C:|;s|/|\\|g')
powershell.exe -Command "Start-Process pythonw -ArgumentList '$WIN_MAIN' -WorkingDirectory '$WIN_DIR'" 2>/dev/null || true
