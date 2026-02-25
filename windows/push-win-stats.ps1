# Windows PC 系統監控 → MQTT 發布
# 讀取 LibreHardwareMonitor HTTP API，用原生 TCP 發布到 RPi5B MQTT broker
# 零外部依賴，不需安裝 mosquitto
#
# 前置需求：
#   LibreHardwareMonitor 背景執行，且啟用 Options -> Remote Web Server (port 8085)
#
# 用法:
#   .\push-win-stats.ps1                # 單次發布
#   .\push-win-stats.ps1 -Install       # 下載 LHM + 註冊 Task Scheduler（每分鐘）
#   .\push-win-stats.ps1 -Uninstall     # 移除 Task Scheduler

param(
    [switch]$Install,
    [switch]$Uninstall
)

$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\deploy-paths.ps1"
$BrokerHost = "192.168.88.10"
$BrokerPort = 1883
$Topic = "system/stats/win"
$TaskName = "Push Win Stats MQTT"
$LhmDir = $DEPLOY_LHM_DIR
$LhmExe = $DEPLOY_LHM_EXE
$LhmPort = 8085

# --- MQTT PUBLISH (pure TCP, no external tools) ---
function Send-MqttPublish {
    param([string]$Broker, [int]$Port, [string]$Topic, [string]$Message)

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.Connect($Broker, $Port)
        $stream = $client.GetStream()
        $stream.ReadTimeout = 3000
        $stream.WriteTimeout = 3000

        # CONNECT packet (MQTT 3.1.1, clean session, no auth)
        $clientId = "winstat"
        $connectPayload = [System.Collections.Generic.List[byte]]::new()
        $connectPayload.AddRange([byte[]]@(0x00, 0x04))
        $connectPayload.AddRange([System.Text.Encoding]::UTF8.GetBytes("MQTT"))
        $connectPayload.AddRange([byte[]]@(0x04, 0x02, 0x00, 0x3C))
        $idBytes = [System.Text.Encoding]::UTF8.GetBytes($clientId)
        $connectPayload.AddRange([byte[]]@(0x00, [byte]$idBytes.Length))
        $connectPayload.AddRange($idBytes)

        $connectPacket = [byte[]]@(0x10, [byte]$connectPayload.Count) + $connectPayload.ToArray()
        $stream.Write($connectPacket, 0, $connectPacket.Length)

        # Wait for CONNACK
        $buf = New-Object byte[] 4
        $stream.Read($buf, 0, 4) | Out-Null

        # PUBLISH packet (retain flag = 0x31)
        $topicBytes = [System.Text.Encoding]::UTF8.GetBytes($Topic)
        $msgBytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
        $publishPayload = [byte[]]@(
            [byte]($topicBytes.Length -shr 8),
            [byte]($topicBytes.Length -band 0xFF)
        ) + $topicBytes + $msgBytes

        $publishPacket = [byte[]]@(0x31, [byte]$publishPayload.Length) + $publishPayload
        $stream.Write($publishPacket, 0, $publishPacket.Length)

        # DISCONNECT
        $stream.Write([byte[]]@(0xE0, 0x00), 0, 2)
    }
    catch { }
    finally { $client.Close() }
}

# --- Install ---
if ($Install) {
    $ErrorActionPreference = "Stop"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # 1. 下載 LHM（如果不存在）
    if (-not (Test-Path $LhmExe)) {
        Write-Host "[1/2] Downloading LibreHardwareMonitor..." -ForegroundColor Yellow
        $zipUrl = "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v0.9.6/LibreHardwareMonitor.zip"
        $zipPath = "$env:TEMP\LibreHardwareMonitor.zip"
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
        if (Test-Path $LhmDir) { Remove-Item -Recurse -Force $LhmDir }
        Expand-Archive -Path $zipPath -DestinationPath $LhmDir -Force
        Remove-Item $zipPath -ErrorAction SilentlyContinue
        Write-Host "  OK: installed to $LhmDir" -ForegroundColor Green
    } else {
        Write-Host "[1/2] LHM already installed at $LhmDir" -ForegroundColor Green
    }

    # 2. 註冊 Task Scheduler（push-win-stats 每分鐘）
    Write-Host "[2/2] Registering Task Scheduler..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    $pwsh = (Get-Command powershell.exe).Source

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    $action = New-ScheduledTaskAction `
        -Execute $pwsh `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration ([TimeSpan]::MaxValue)

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 1)

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Description "LibreHardwareMonitor stats -> MQTT (system/stats/win)" `
        | Out-Null

    Write-Host "  OK: '$TaskName' registered (every 1 min)" -ForegroundColor Green
    Write-Host ""
    Write-Host "=== Install complete ===" -ForegroundColor Cyan
    Write-Host "  NOTE: Run LHM as admin and enable Options -> Remote Web Server" -ForegroundColor White
    exit 0
}

# --- Uninstall ---
if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "OK: Task Scheduler '$TaskName' removed" -ForegroundColor Green
    exit 0
}

# --- 單次發布 ---

$temp = 0; $freq = 0; $ram = 0
$gotData = $false

try {
    $json = (Invoke-WebRequest -Uri "http://localhost:$LhmPort/data.json" -UseBasicParsing -TimeoutSec 3).Content
    $data = $json | ConvertFrom-Json

    # 遞迴走訪 LHM 樹狀結構，收集所有 sensor
    function Get-Sensors($node) {
        $results = @()
        if ($node.Children) {
            foreach ($child in $node.Children) {
                $results += Get-Sensors $child
            }
        }
        if ($node.Text -and $node.Value -and $node.Value -ne "") {
            $results += $node
        }
        return $results
    }

    $sensors = Get-Sensors $data

    # CPU 溫度：CPU Package > Core (Tctl/Tdie) > GPU Core fallback
    $tempNode = $sensors | Where-Object {
        $_.Text -match "CPU Package|Core \(Tctl" -and $_.Value -match "\d.*C"
    } | Select-Object -First 1
    if ($tempNode) {
        $tv = [double]($tempNode.Value -replace '[^\d.]')
        if ($tv -gt 0) { $temp = [int]$tv; $gotData = $true }
    }
    if ($temp -eq 0) {
        $gpuTempNode = $sensors | Where-Object {
            $_.Text -eq "GPU Core" -and $_.Value -match "\d.*C"
        } | Select-Object -First 1
        if ($gpuTempNode) {
            $tv = [double]($gpuTempNode.Value -replace '[^\d.]')
            if ($tv -gt 0) { $temp = [int]$tv; $gotData = $true }
        }
    }

    # CPU 頻率：LHM Core clocks > Win32_Processor fallback
    $freqNodes = $sensors | Where-Object {
        $_.Text -match "^Core #\d" -and $_.Value -match "\d.*MHz"
    }
    if ($freqNodes) {
        $freqValues = $freqNodes | ForEach-Object { [double]($_.Value -replace '[^\d.]') } |
            Where-Object { $_ -gt 0 }
        if ($freqValues) {
            $freq = [int](($freqValues | Measure-Object -Average).Average)
            $gotData = $true
        }
    }
    if ($freq -eq 0) {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($cpu -and $cpu.CurrentClockSpeed -gt 0) {
            $freq = [int]$cpu.CurrentClockSpeed
            $gotData = $true
        }
    }

    # RAM 使用率
    $ramNode = $sensors | Where-Object {
        $_.Text -eq "Memory" -and $_.Value -match "\d.*%"
    } | Select-Object -First 1
    if ($ramNode) {
        $ram = [int]($ramNode.Value -replace '[^\d.]' -replace '\..*')
        $gotData = $true
    }
} catch {
    exit 0
}

if (-not $gotData) { exit 0 }

$payload = "{`"temp`":$temp,`"freq`":$freq,`"ram`":$ram}"
Send-MqttPublish -Broker $BrokerHost -Port $BrokerPort -Topic $Topic -Message $payload
