# Register / update the ClaudeMonitorSidecar scheduled task. Idempotent.
#
# The task runs at user logon, invokes the wrapper at
# %LOCALAPPDATA%\claude-monitor\run-sidecar.ps1 (deployed by
# `npm run build:sidecar`), and gets restarted by Task Scheduler if the
# sidecar process exits unexpectedly.
#
# Usage (from any directory, no dot-source dependency):
#     powershell -NoProfile -ExecutionPolicy Bypass -File install-sidecar-task.ps1
#
# Paths use $env:LOCALAPPDATA so the script is portable; the deployed
# %LOCALAPPDATA%\claude-monitor\ layout is the convention recorded in
# windows/deploy-paths.{sh,ps1}.

$ErrorActionPreference = "Stop"

$taskName     = "ClaudeMonitorSidecar"
$claudeDir    = "$env:LOCALAPPDATA\claude-monitor"
$runner       = "$claudeDir\run-sidecar.ps1"
$sidecarJs    = "$claudeDir\sidecar.js"
$sidecarLog   = "$claudeDir\sidecar.log"

if (-not (Test-Path $runner)) {
    Write-Error "Sidecar wrapper not found at $runner. Run 'npm run build:sidecar' first."
    exit 1
}
if (-not (Test-Path $sidecarJs)) {
    Write-Error "Sidecar bundle not found at $sidecarJs. Run 'npm run build:sidecar' first."
    exit 1
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runner`""

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -RestartCount 3 `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -Hidden

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Out-of-process MQTT subscriber for Stream Deck claude-monitor (CPU regression workaround). Pairs with src/state-reader.ts; writes %LOCALAPPDATA%\claude-monitor\state.json." `
    -Force | Out-Null

Write-Host "Registered scheduled task: $taskName"
Write-Host "Triggers at logon for user: $env:USERNAME"
Write-Host ""
Write-Host "Common operations:"
Write-Host "  Start now:   Start-ScheduledTask -TaskName $taskName"
Write-Host "  Stop:        Stop-ScheduledTask -TaskName $taskName"
Write-Host "  Status:      Get-ScheduledTask -TaskName $taskName | Format-List"
Write-Host "  Tail log:    Get-Content `"$sidecarLog`" -Tail 30 -Wait"
Write-Host "  Unregister:  Unregister-ScheduledTask -TaskName $taskName -Confirm:`$false"
