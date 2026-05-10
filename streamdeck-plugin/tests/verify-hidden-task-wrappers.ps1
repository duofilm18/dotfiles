param(
    [switch]$SourceOnly
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$StreamDeckRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Assert-FileContains {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing file: $Path"
    }
    $content = Get-Content -LiteralPath $Path -Raw
    if ($content -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-TaskAction {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$ExpectedRunner
    )

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    $action = $task.Actions | Select-Object -First 1
    $execute = [System.IO.Path]::GetFileName($action.Execute).ToLowerInvariant()
    if ($execute -ne "wscript.exe") {
        throw "$TaskName must launch wscript.exe, got: $($action.Execute)"
    }
    if ($action.Arguments -notmatch [regex]::Escape($ExpectedRunner)) {
        throw "$TaskName must point at $ExpectedRunner, got: $($action.Arguments)"
    }
    if ($action.Arguments -notmatch "//B" -or $action.Arguments -notmatch "//Nologo") {
        throw "$TaskName must use //B //Nologo, got: $($action.Arguments)"
    }
}

$sidecarTask = Join-Path $Root "windows\install-sidecar-task.ps1"
$winStatsTask = Join-Path $Root "windows\push-win-stats.ps1"
$sidecarVbs = Join-Path $StreamDeckRoot "sidecar\run-sidecar.vbs"
$winStatsVbs = Join-Path $Root "windows\run-win-stats.vbs"
$packageJson = Join-Path $StreamDeckRoot "package.json"
$deployWinStats = Join-Path $Root "scripts\deploy-win-stats.sh"

Assert-FileContains $sidecarTask 'New-ScheduledTaskAction\s+`\s+-Execute "wscript\.exe"' `
    "ClaudeMonitorSidecar source task must launch wscript.exe."
Assert-FileContains $sidecarTask 'run-sidecar\.vbs' `
    "ClaudeMonitorSidecar source task must point at run-sidecar.vbs."
Assert-FileContains $winStatsTask '-Execute \$wscript' `
    "Push Win Stats source task must launch wscript.exe."
Assert-FileContains $winStatsTask 'run-win-stats\.vbs' `
    "Push Win Stats source task must point at run-win-stats.vbs."
Assert-FileContains $packageJson 'run-sidecar\.vbs' `
    "Sidecar deploy script must copy run-sidecar.vbs."
Assert-FileContains $deployWinStats 'run-win-stats\.vbs' `
    "Win stats deploy script must copy run-win-stats.vbs."
Assert-FileContains $sidecarVbs 'shell\.Run\(cmd, 0, True\)' `
    "run-sidecar.vbs must hide its PowerShell window."
Assert-FileContains $winStatsVbs 'shell\.Run\(cmd, 0, True\)' `
    "run-win-stats.vbs must hide its PowerShell window."

if (-not $SourceOnly -and (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
    Assert-TaskAction "ClaudeMonitorSidecar" "run-sidecar.vbs"
    Assert-TaskAction "Push Win Stats MQTT" "run-win-stats.vbs"
}

Write-Host "OK: Stream Deck monitor tasks use hidden wscript wrappers."
