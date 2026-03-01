#!/bin/bash
# deploy-claude-overlay.sh - Build + 部署 Claude Status Overlay (Tauri) 到 Windows
#
# 1. npm run tauri build（Tauri 透過 Windows Rust 工具鏈編譯 .exe）
# 2. 複製 .exe 到 %LOCALAPPDATA%\claude-overlay\
# 3. 殺舊進程 + 啟動新的
#
# 用法:
#   ~/dotfiles/scripts/deploy-claude-overlay.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../windows/deploy-paths.sh"

SRC_DIR="$(cd "$SCRIPT_DIR/../claude-overlay" && pwd)"
EXE_NAME="claude-overlay.exe"
BUILT_EXE="$SRC_DIR/src-tauri/target/release/$EXE_NAME"
DEST="$DEPLOY_OVERLAY_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Build ──
echo -e "${CYAN}=== Build Claude Status Overlay ===${NC}"
cd "$SRC_DIR"
npm install
npm run tauri build

if [ ! -f "$BUILT_EXE" ]; then
    echo -e "${RED}錯誤: 找不到編譯產物: $BUILT_EXE${NC}"
    exit 1
fi

# ── Deploy ──
echo ""
echo -e "${CYAN}=== 部署到 $DEST ===${NC}"
mkdir -p "$DEST"

# 終止舊進程
powershell.exe -Command "
    Get-Process 'claude-overlay' -ErrorAction SilentlyContinue |
        Stop-Process -Force
" 2>/dev/null || true
sleep 1

cp "$BUILT_EXE" "$DEST/$EXE_NAME"
echo -e "  ${GREEN}已複製${NC}: $EXE_NAME"

# ── 啟動 ──
echo ""
echo -e "${CYAN}=== 啟動 Claude Status Overlay ===${NC}"
WIN_EXE=$(echo "$DEPLOY_OVERLAY_MAIN" | sed 's|/mnt/c|C:|;s|/|\\|g')
powershell.exe -Command "Start-Process '$WIN_EXE'" 2>/dev/null

sleep 2
RUNNING=$(powershell.exe -Command "
    (Get-Process 'claude-overlay' -ErrorAction SilentlyContinue) -ne \$null
" 2>/dev/null | tr -d '\r')

if [ "$RUNNING" = "True" ]; then
    echo -e "  ${GREEN}Claude Status Overlay 已啟動${NC}"
else
    echo -e "  ${RED}啟動失敗，請手動檢查${NC}"
    exit 1
fi
