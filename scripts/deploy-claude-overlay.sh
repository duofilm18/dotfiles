#!/bin/bash
# deploy-claude-overlay.sh - 部署 Claude Status Overlay 到 Windows
#
# dotfiles 的 claude-overlay/ 是 source of truth，
# Windows 端路徑由 windows/deploy-paths.sh 定義。
# 本腳本同步兩邊並重啟 Windows 進程。
#
# 用法:
#   ~/dotfiles/scripts/deploy-claude-overlay.sh          # 部署 + 重啟
#   ~/dotfiles/scripts/deploy-claude-overlay.sh --diff    # 只顯示差異

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../windows/deploy-paths.sh"

SRC="$(cd "$SCRIPT_DIR/../claude-overlay" && pwd)"
DEST="$DEPLOY_OVERLAY_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── 前置檢查 ──
if [ ! -d "$SRC" ]; then
    echo -e "${RED}錯誤: 來源目錄不存在: $SRC${NC}"
    exit 1
fi

# 自動建立目標目錄
if [ ! -d "$DEST" ]; then
    echo -e "${CYAN}建立目標目錄: $DEST${NC}"
    mkdir -p "$DEST"
fi

# ── --diff 模式：只顯示差異 ──
if [ "${1:-}" = "--diff" ]; then
    echo -e "${CYAN}=== dotfiles vs Windows 差異 ===${NC}"
    has_diff=false
    for f in "$SRC"/*.py; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        if [ -f "$DEST/$name" ]; then
            if ! diff -q "$f" "$DEST/$name" >/dev/null 2>&1; then
                echo -e "${RED}不同: $name${NC}"
                diff --color=auto "$f" "$DEST/$name" || true
                echo ""
                has_diff=true
            fi
        else
            echo -e "${RED}缺少: $name（Windows 端不存在）${NC}"
            has_diff=true
        fi
    done
    if [ "$has_diff" = false ]; then
        echo -e "${GREEN}兩邊完全一致${NC}"
    fi
    exit 0
fi

# ── 部署 ──
echo -e "${CYAN}=== 部署 Claude Status Overlay ===${NC}"
echo "  來源: $SRC"
echo "  目標: $DEST"
echo ""

copied=0
for f in "$SRC"/*.py; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    if ! diff -q "$f" "$DEST/$name" >/dev/null 2>&1; then
        cp "$f" "$DEST/$name"
        echo -e "  ${GREEN}更新${NC}: $name"
        copied=$((copied + 1))
    fi
done

if [ "$copied" -eq 0 ]; then
    echo -e "  ${GREEN}所有檔案已是最新${NC}"
    exit 0
fi
echo ""
echo -e "  已更新 ${GREEN}$copied${NC} 個檔案"

# ── 重啟 Windows 進程 ──
echo ""
echo -e "${CYAN}=== 重啟 Claude Status Overlay ===${NC}"

# 終止舊進程（殺所有 command line 含 claude-overlay 的 python/pythonw）
powershell.exe -Command "
    Get-Process python*, pythonw* -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            \$cmd = (Get-WmiObject Win32_Process -Filter \"ProcessId=\$(\$_.Id)\").CommandLine
            if (\$cmd -like '*claude-overlay*') { Stop-Process -Id \$_.Id -Force }
        } catch {}
    }
" 2>/dev/null || true
sleep 1

# 啟動新進程
WIN_MAIN=$(echo "$DEPLOY_OVERLAY_MAIN" | sed 's|/mnt/c|C:|;s|/|\\|g')
WIN_DIR=$(echo "$DEPLOY_OVERLAY_DIR" | sed 's|/mnt/c|C:|;s|/|\\|g')
powershell.exe -Command "Start-Process pythonw -ArgumentList '$WIN_MAIN' -WorkingDirectory '$WIN_DIR'" 2>/dev/null

sleep 2
RUNNING=$(powershell.exe -Command "
    \$found = \$false
    Get-Process pythonw -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            \$cmd = (Get-WmiObject Win32_Process -Filter \"ProcessId=\$(\$_.Id)\").CommandLine
            if (\$cmd -like '*claude-overlay*') { \$found = \$true }
        } catch {}
    }
    \$found
" 2>/dev/null | tr -d '\r')

if [ "$RUNNING" = "True" ]; then
    echo -e "  ${GREEN}Claude Status Overlay 已重啟${NC}"
else
    echo -e "  ${RED}Claude Status Overlay 啟動失敗，請手動檢查${NC}"
    exit 1
fi
