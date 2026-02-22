# IME 中英指示器 - Windows 安裝腳本
# 用法: 在 PowerShell 中執行:
#   cd C:\Users\你的帳號\dotfiles\windows
#   .\install.ps1
#
# 使用 RickAsli/IME_Indicator 的 Python 版本
# https://github.com/duofilm18/IME_Indicator (fork of RickAsli/IME_Indicator)

$ErrorActionPreference = "Stop"
$TaskName = "IME Indicator"
$InstallDir = "$env:LOCALAPPDATA\IME_Indicator"

Write-Host "=== IME 中英指示器安裝 ===" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: 檢查 Python ---
Write-Host "[1/3] 檢查 Python..." -ForegroundColor Yellow

$pythonCmd = $null
foreach ($cmd in @("python", "python3", "py")) {
    try {
        $ver = & $cmd --version 2>&1
        if ($ver -match "Python 3") {
            $pythonCmd = $cmd
            break
        }
    } catch {}
}

if ($pythonCmd) {
    Write-Host "  OK: $(& $pythonCmd --version)" -ForegroundColor Green
} else {
    Write-Host "  FAIL: 找不到 Python 3" -ForegroundColor Red
    Write-Host "  請從 https://www.python.org/ 安裝 Python 3（勾選 Add to PATH）" -ForegroundColor Yellow
    exit 1
}

# --- Step 2: Clone / 更新 IME_Indicator ---
Write-Host "[2/3] 安裝 IME_Indicator..." -ForegroundColor Yellow

if (Test-Path "$InstallDir\.git") {
    Write-Host "  已存在，更新中..." -ForegroundColor Yellow
    Push-Location $InstallDir
    git pull --quiet
    Pop-Location
    Write-Host "  OK: 已更新" -ForegroundColor Green
} else {
    if (Test-Path $InstallDir) {
        Remove-Item -Recurse -Force $InstallDir
    }
    git clone --quiet "https://github.com/duofilm18/IME_Indicator.git" $InstallDir
    Write-Host "  OK: 已 clone 到 $InstallDir" -ForegroundColor Green
}

# 安裝 Python 依賴
Write-Host "  安裝 Python 套件..." -ForegroundColor Yellow
& $pythonCmd -m pip install --quiet -r "$InstallDir\python_indicator\requirements.txt"
Write-Host "  OK: 依賴已安裝" -ForegroundColor Green

# --- Step 3: 設定 Task Scheduler 開機自動啟動 ---
Write-Host "[3/3] 設定開機自動啟動..." -ForegroundColor Yellow

# 取得 pythonw.exe 路徑（無 console 視窗）
$pythonwPath = (Get-Command $pythonCmd).Source -replace "python\.exe$", "pythonw.exe"
if (-not (Test-Path $pythonwPath)) {
    # fallback: 用 python.exe
    $pythonwPath = (Get-Command $pythonCmd).Source
}

$mainScript = "$InstallDir\python_indicator\main.py"

# 移除舊的排程
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction `
    -Execute $pythonwPath `
    -Argument "`"$mainScript`"" `
    -WorkingDirectory "$InstallDir\python_indicator"

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "IME 中英指示器 - 游標旁顯示中/英輸入法狀態 (RickAsli/IME_Indicator)" `
    | Out-Null

Write-Host "  OK: 已建立排程工作 '$TaskName'" -ForegroundColor Green

# --- 完成 ---
Write-Host ""
Write-Host "=== 安裝完成 ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  來源: RickAsli/IME_Indicator (Python)" -ForegroundColor White
Write-Host "  安裝: $InstallDir" -ForegroundColor White
Write-Host "  功能: 游標旁顯示中/英輸入法狀態圓點" -ForegroundColor White
Write-Host "  自動啟動: 登入 Windows 時自動執行" -ForegroundColor White
Write-Host "  更新: cd $InstallDir && git pull" -ForegroundColor White
Write-Host "  移除排程: Unregister-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host ""

# 詢問是否立即啟動
$answer = Read-Host "現在要啟動嗎？(Y/n)"
if ($answer -ne "n") {
    Start-Process $pythonwPath -ArgumentList "`"$mainScript`"" -WorkingDirectory "$InstallDir\python_indicator"
    Write-Host "已啟動！移動游標看看旁邊的指示器圓點。" -ForegroundColor Green
}
