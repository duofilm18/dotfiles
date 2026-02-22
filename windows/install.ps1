# IME 中英指示器 - Windows 安裝腳本
# 用法: 在 PowerShell 中執行:
#   cd C:\Users\你的帳號\dotfiles\windows
#   .\install.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TaskName = "IME Indicator"
$AhkScript = Join-Path $ScriptDir "ime-indicator.ahk"

Write-Host "=== IME 中英指示器安裝 ===" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: 檢查 / 安裝 AutoHotkey v2 ---
Write-Host "[1/2] 檢查 AutoHotkey v2..." -ForegroundColor Yellow

$ahkPath = ""

# 搜尋常見安裝路徑
$searchPaths = @(
    "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
    "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey32.exe",
    "${env:ProgramFiles(x86)}\AutoHotkey\v2\AutoHotkey64.exe",
    "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
)

foreach ($p in $searchPaths) {
    if (Test-Path $p) {
        $ahkPath = $p
        break
    }
}

if ($ahkPath) {
    Write-Host "  OK: $ahkPath" -ForegroundColor Green
} else {
    Write-Host "  找不到 AutoHotkey v2，正在下載安裝..." -ForegroundColor Yellow
    $installerUrl = "https://www.autohotkey.com/download/ahk-v2.exe"
    $installerPath = "$env:TEMP\ahk-v2-setup.exe"

    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
    Start-Process $installerPath -ArgumentList "/silent" -Wait
    Remove-Item $installerPath -ErrorAction SilentlyContinue

    # 重新搜尋
    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            $ahkPath = $p
            break
        }
    }

    if ($ahkPath) {
        Write-Host "  OK: AutoHotkey v2 已安裝" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: 安裝後仍找不到 AutoHotkey。請手動安裝: https://www.autohotkey.com/" -ForegroundColor Red
        exit 1
    }
}

# --- Step 2: 設定 Task Scheduler 開機自動啟動 ---
Write-Host "[2/2] 設定開機自動啟動..." -ForegroundColor Yellow

# 移除舊的排程
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction `
    -Execute $ahkPath `
    -Argument "`"$AhkScript`"" `
    -WorkingDirectory $ScriptDir

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
    -Description "IME 中英指示器 - 游標旁顯示目前輸入法狀態" `
    | Out-Null

Write-Host "  OK: 已建立排程工作 '$TaskName'" -ForegroundColor Green

# --- 完成 ---
Write-Host ""
Write-Host "=== 安裝完成 ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  功能: 游標旁顯示「中」(橘) /「EN」(綠)，按 Shift 切換" -ForegroundColor White
Write-Host "  自動啟動: 登入 Windows 時自動執行" -ForegroundColor White
Write-Host "  停止排程: Unregister-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host ""

# 詢問是否立即啟動
$answer = Read-Host "現在要啟動嗎？(Y/n)"
if ($answer -ne "n") {
    Start-Process $ahkPath -ArgumentList "`"$AhkScript`""
    Write-Host "已啟動！移動游標看看旁邊的指示器。" -ForegroundColor Green
}
