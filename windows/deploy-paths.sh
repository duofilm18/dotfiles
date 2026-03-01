#!/bin/bash
# Windows 部署路徑登記表（WSL 側，/mnt/c 版本）
#
# 所有 WSL 腳本引用此檔案的變數，禁止自行硬寫 /mnt/c 路徑。
# 此檔案必須與 deploy-paths.ps1 保持一致。
#
# 用法: source ~/dotfiles/windows/deploy-paths.sh

WIN_USER="duofilm"
WIN_HOME="/mnt/c/Users/${WIN_USER}"
WIN_LOCALAPPDATA="${WIN_HOME}/AppData/Local"

DEPLOY_LHM_DIR="${WIN_LOCALAPPDATA}/LibreHardwareMonitor"

DEPLOY_OVERLAY_DIR="${WIN_LOCALAPPDATA}/claude-overlay"
DEPLOY_OVERLAY_MAIN="${DEPLOY_OVERLAY_DIR}/main.py"
