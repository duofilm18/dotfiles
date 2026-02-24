#!/bin/bash
# deploy-ime-indicator.sh - 部署 IME_Indicator 到 Windows
#
# dotfiles 的 IME_Indicator/ 是 source of truth，
# Windows 端 C:\Users\duofilm\IME_Indicator 是執行副本。
# 本腳本同步兩邊並重啟 Windows 進程。
#
# 用法:
#   ~/dotfiles/scripts/deploy-ime-indicator.sh          # 部署 + 重啟
#   ~/dotfiles/scripts/deploy-ime-indicator.sh --diff    # 只顯示差異

set -euo pipefail

SRC="$(cd "$(dirname "$0")/../IME_Indicator/python_indicator" && pwd)"
DEST="/mnt/c/Users/duofilm/IME_Indicator/python_indicator"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── 前置檢查 ──
if [ ! -d "$SRC" ]; then
    echo -e "${RED}錯誤: 來源目錄不存在: $SRC${NC}"
    exit 1
fi
if [ ! -d "$DEST" ]; then
    echo -e "${RED}錯誤: 目標目錄不存在: $DEST${NC}"
    echo "請先在 Windows 端 clone IME_Indicator"
    exit 1
fi

# ── --diff 模式：只顯示差異 ──
if [ "${1:-}" = "--diff" ]; then
    echo -e "${CYAN}=== dotfiles vs Windows 差異 ===${NC}"
    has_diff=false
    for f in "$SRC"/*.py "$SRC"/*.txt; do
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
echo -e "${CYAN}=== 部署 IME_Indicator ===${NC}"
echo "  來源: $SRC"
echo "  目標: $DEST"
echo ""

copied=0
for f in "$SRC"/*.py "$SRC"/*.txt; do
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
echo -e "${CYAN}=== 重啟 IME_Indicator ===${NC}"

# 終止舊進程
powershell.exe -Command "Get-Process python*, pythonw* 2>\$null | Where-Object { \$_.Path -like '*IME_Indicator*' -or \$_.MainModule.FileName -like '*IME_Indicator*' } | Stop-Process -Force" 2>/dev/null || true
# pythonw 不帶路徑時 fallback：殺所有 pythonw
powershell.exe -Command "Stop-Process -Name pythonw -Force -ErrorAction SilentlyContinue" 2>/dev/null || true
sleep 1

# 啟動新進程
powershell.exe -Command "Start-Process pythonw -ArgumentList 'C:\Users\duofilm\IME_Indicator\python_indicator\main.py' -WorkingDirectory 'C:\Users\duofilm\IME_Indicator\python_indicator'" 2>/dev/null

sleep 2
if powershell.exe -Command "(Get-Process pythonw -ErrorAction SilentlyContinue).Count" 2>/dev/null | grep -q '[1-9]'; then
    echo -e "  ${GREEN}IME_Indicator 已重啟${NC}"
else
    echo -e "  ${RED}IME_Indicator 啟動失敗，請手動檢查${NC}"
    exit 1
fi
