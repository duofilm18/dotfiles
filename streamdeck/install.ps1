# Stream Deck MQTT Monitor - Windows 安裝腳本
# 用法: 右鍵 → 以 PowerShell 執行，或在 PowerShell 中執行:
#   cd C:\Users\你的帳號\dotfiles\streamdeck
#   .\install.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TaskName = "StreamDeck MQTT Monitor"

Write-Host "=== Stream Deck MQTT Monitor 安裝 ===" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: 檢查 Python ---
Write-Host "[1/5] 檢查 Python..." -ForegroundColor Yellow
try {
    $pythonPath = (Get-Command python -ErrorAction Stop).Source
    $pythonVersion = python --version 2>&1
    Write-Host "  OK: $pythonVersion ($pythonPath)" -ForegroundColor Green
} catch {
    Write-Host "  FAIL: 找不到 Python。請從 https://www.python.org/downloads/ 安裝" -ForegroundColor Red
    Write-Host "  安裝時務必勾選 'Add Python to PATH'" -ForegroundColor Red
    exit 1
}

# pythonw.exe 路徑（無 console 視窗版本）
$pythonDir = Split-Path $pythonPath
$pythonwPath = Join-Path $pythonDir "pythonw.exe"
if (!(Test-Path $pythonwPath)) {
    Write-Host "  WARN: 找不到 pythonw.exe，改用 python.exe（會有 console 視窗）" -ForegroundColor Yellow
    $pythonwPath = $pythonPath
}

# --- Step 2: 安裝 Python 套件 ---
Write-Host "[2/5] 安裝 Python 套件..." -ForegroundColor Yellow
pip install -r "$ScriptDir\requirements.txt" --quiet
Write-Host "  OK: streamdeck, Pillow, paho-mqtt" -ForegroundColor Green

# --- Step 3: 檢查 hidapi.dll ---
Write-Host "[3/5] 檢查 hidapi.dll..." -ForegroundColor Yellow
$hidapiFound = $false
try {
    python -c "from StreamDeck.DeviceManager import DeviceManager; DeviceManager()" 2>$null
    $hidapiFound = $true
    Write-Host "  OK: hidapi.dll 已就緒" -ForegroundColor Green
} catch {
    # 嘗試自動下載
    Write-Host "  找不到 hidapi.dll，正在下載..." -ForegroundColor Yellow
    $hidapiUrl = "https://github.com/libusb/hidapi/releases/download/hidapi-0.14.0/hidapi-win.zip"
    $zipPath = "$env:TEMP\hidapi-win.zip"
    $extractPath = "$env:TEMP\hidapi-tmp"

    Invoke-WebRequest -Uri $hidapiUrl -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    # 放到 .local\bin（使用者 PATH）
    $binDir = "$env:USERPROFILE\.local\bin"
    if (!(Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }
    Copy-Item "$extractPath\x64\hidapi.dll" "$binDir\hidapi.dll" -Force

    # 清理暫存
    Remove-Item $zipPath -ErrorAction SilentlyContinue
    Remove-Item $extractPath -Recurse -ErrorAction SilentlyContinue

    # 檢查 .local\bin 是否在 PATH
    if ($env:PATH -notlike "*$binDir*") {
        [Environment]::SetEnvironmentVariable("PATH", "$binDir;$([Environment]::GetEnvironmentVariable('PATH', 'User'))", "User")
        $env:PATH = "$binDir;$env:PATH"
        Write-Host "  已將 $binDir 加入 PATH" -ForegroundColor Yellow
    }

    Write-Host "  OK: hidapi.dll 已安裝到 $binDir" -ForegroundColor Green
}

# --- Step 4: 建立 config.json ---
Write-Host "[4/5] 檢查設定檔..." -ForegroundColor Yellow
$configPath = Join-Path $ScriptDir "config.json"
if (!(Test-Path $configPath)) {
    Copy-Item "$ScriptDir\config.json.example" $configPath
    Write-Host "  已建立 config.json（預設 MQTT: 192.168.88.10:1883）" -ForegroundColor Green
    Write-Host "  如需修改，請編輯: $configPath" -ForegroundColor Yellow
} else {
    Write-Host "  OK: config.json 已存在" -ForegroundColor Green
}

# --- Step 5: 設定 Task Scheduler ---
Write-Host "[5/5] 設定開機自動啟動..." -ForegroundColor Yellow

# 移除舊的排程（如果有）
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$scriptPath = Join-Path $ScriptDir "streamdeck_mqtt.py"
$action = New-ScheduledTaskAction `
    -Execute $pythonwPath `
    -Argument "`"$scriptPath`"" `
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
    -Description "Stream Deck MQTT Monitor - 顯示 Claude Code 開發狀態" `
    | Out-Null

Write-Host "  OK: 已建立排程工作 '$TaskName'" -ForegroundColor Green

# --- 完成 ---
Write-Host ""
Write-Host "=== 安裝完成 ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  手動啟動: python `"$scriptPath`"" -ForegroundColor White
Write-Host "  自動啟動: 登入 Windows 時自動執行" -ForegroundColor White
Write-Host "  停止排程: Unregister-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host ""

# 詢問是否立即啟動
$answer = Read-Host "現在要啟動嗎？(Y/n)"
if ($answer -ne "n") {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "已啟動！檢查 Stream Deck 左上角按鍵。" -ForegroundColor Green
}
