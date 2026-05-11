# repair.ps1 - Brother DCP-T820DW one-click repair
#
# Usage:
#   - From WSL: powershell.exe -File "$(wslpath -w ~/dotfiles/windows/brother-printer/repair.ps1)"
#   - From Windows: right-click -> Run with PowerShell (auto UAC elevation)
#
# Steps:
#   1. Ensure Spooler auto-restart configured (idempotent)
#   2. Start Spooler (skip if running)
#   3. Remove duplicate "Brother DCP-T820DW Printer" entries
#   4. Run healthcheck.ps1 -Full to verify

[CmdletBinding()]
param([switch]$Elevated)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsElevated)) {
    Write-Host "Need admin privileges, requesting UAC elevation..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"", "-Elevated"
    ) -Wait
    exit
}

Write-Host ""
Write-Host "=== Brother Printer One-Click Repair ===" -ForegroundColor Cyan
Write-Host ""

# 1. Spooler auto-restart configuration
Write-Host "[1/4] Configure Spooler auto-restart..." -ForegroundColor Cyan
& sc.exe failure Spooler reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
Write-Host "  OK" -ForegroundColor Green

# 2. Start Spooler
Write-Host "[2/4] Start Spooler..." -ForegroundColor Cyan
$spooler = Get-Service -Name Spooler
if ($spooler.Status -eq "Running") {
    Write-Host "  Already running" -ForegroundColor Green
} else {
    try {
        Start-Service -Name Spooler -ErrorAction Stop
        Start-Sleep -Seconds 2
        Write-Host "  Started" -ForegroundColor Green
    } catch {
        Write-Host "  Start failed, stopping and retrying..." -ForegroundColor Yellow
        Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        try {
            Start-Service -Name Spooler -ErrorAction Stop
            Write-Host "  Started on retry" -ForegroundColor Green
        } catch {
            Write-Host "  Still cannot start: $_" -ForegroundColor Red
            Write-Host "  Next step: open services.msc manually, or reinstall Brother driver" -ForegroundColor Yellow
        }
    }
}

# 3. Remove duplicate Brother printers
Write-Host "[3/4] Check for duplicate Brother entries..." -ForegroundColor Cyan
try {
    $duplicates = @(Get-Printer -ErrorAction Stop |
        Where-Object { $_.Name -like "*Brother*" -and $_.Name -like "* Printer" })
    if ($duplicates.Count -eq 0) {
        Write-Host "  No duplicates" -ForegroundColor Green
    } else {
        foreach ($p in $duplicates) {
            Write-Host "  Removing: $($p.Name)" -ForegroundColor Yellow
            Remove-Printer -Name $p.Name -ErrorAction Continue
        }
    }
} catch {
    Write-Host "  Skipped (Get-Printer failed, Spooler may not be ready)" -ForegroundColor Yellow
}

# 4. Healthcheck
Write-Host "[4/4] Verify..." -ForegroundColor Cyan
& "$PSScriptRoot\healthcheck.ps1" -Full
$hcExit = $LASTEXITCODE

Write-Host ""
if ($hcExit -eq 0) {
    Write-Host "Repair complete" -ForegroundColor Green
} else {
    Write-Host "Repair finished but FAILURES remain, see output above" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Press Enter to close..."
$null = Read-Host
