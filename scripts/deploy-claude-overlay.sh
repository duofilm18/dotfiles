#!/bin/bash
# deploy-claude-overlay.sh - Build + 部署 Claude Status Overlay (Tauri) 到 Windows
#
# WSL 的 UNC path (\\wsl$\...) 不被 Windows cmd.exe / npm scripts 支援，
# 所以先 robocopy 到 C:\temp 再 build，build 完把 .exe 部署到 %LOCALAPPDATA%。
#
# 用法:
#   ~/dotfiles/scripts/deploy-claude-overlay.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../windows/deploy-paths.sh"

SRC_DIR="$(cd "$SCRIPT_DIR/../claude-overlay" && pwd)"
EXE_NAME="claude-overlay.exe"
WIN_BUILD_DIR='C:\temp\claude-overlay-build'
WSL_BUILD_DIR="/mnt/c/temp/claude-overlay-build"
BUILT_EXE="$WSL_BUILD_DIR/src-tauri/target/release/$EXE_NAME"
DEST="$DEPLOY_OVERLAY_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── 同步原始碼到 Windows 本機 ──
echo -e "${CYAN}=== 同步原始碼到 $WIN_BUILD_DIR ===${NC}"
WIN_SRC=$(echo "$SRC_DIR" | sed 's|^/mnt/c|C:|;s|/|\\|g')

# robocopy 同步（排除 node_modules/target/dist，保留快取）
powershell.exe -ExecutionPolicy Bypass -Command "
    robocopy '$WIN_SRC' '$WIN_BUILD_DIR' /MIR /XD node_modules target dist /NFL /NDL /NJH /NJS /NP
" 2>/dev/null || true  # robocopy exit 1 = copied ok

# ── Build（在 Windows 本機目錄）──
echo -e "${CYAN}=== Build Claude Status Overlay ===${NC}"
powershell.exe -ExecutionPolicy Bypass -Command "
    \$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','User') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','Machine')
    Set-Location '$WIN_BUILD_DIR'
    npm install 2>&1
    npx tauri build 2>&1
" 2>&1

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
