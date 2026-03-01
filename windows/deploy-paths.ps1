# Windows 部署路徑登記表（Single Source of Truth）
#
# 所有 Windows 部署腳本必須引用此檔案的變數，禁止自行硬寫路徑。
# WSL 腳本用 windows/deploy-paths.sh 取得對應的 /mnt/c 路徑。
#
# 修改此檔案時，必須同步更新 deploy-paths.sh。

$DEPLOY_IME_DIR = "$env:LOCALAPPDATA\IME_Indicator"
$DEPLOY_IME_PYTHON = "$DEPLOY_IME_DIR\python_indicator"
$DEPLOY_IME_MAIN = "$DEPLOY_IME_PYTHON\main.py"

$DEPLOY_LHM_DIR = "$env:LOCALAPPDATA\LibreHardwareMonitor"
$DEPLOY_LHM_EXE = "$DEPLOY_LHM_DIR\LibreHardwareMonitor.exe"

$DEPLOY_SD_PLUGIN = "$env:USERPROFILE\com.duofilm.claude-monitor.sdPlugin"

$DEPLOY_OVERLAY_DIR = "$env:LOCALAPPDATA\claude-overlay"
$DEPLOY_OVERLAY_MAIN = "$DEPLOY_OVERLAY_DIR\claude-overlay.exe"
