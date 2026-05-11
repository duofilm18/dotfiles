# healthcheck.ps1 - Brother DCP-T820DW Win11 spooler fix regression check
#
# Default: regression checks only (verify the fix is preserved)
#   1. Spooler auto-restart configured (sc.exe qfailure shows RESTART)
#   2. No duplicate "Brother DCP-T820DW Printer" entries
#
# -Full: also check current health (Spooler running, printer Normal, IP reachable)

[CmdletBinding()]
param(
    [string]$PrinterName = "Brother DCP-T820DW",
    [string]$PrinterIP = "192.168.88.81",
    [switch]$Full
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"
$failures = @()
$warnings = @()

# 1. Spooler auto-restart (regression)
try {
    $qfailure = & sc.exe qfailure Spooler 2>&1 | Out-String
    if ($qfailure -notmatch "RESTART") {
        $failures += "Spooler failure actions not configured. Fix: sc.exe failure Spooler reset= 86400 actions= restart/60000/restart/60000/restart/60000"
    }
} catch {
    $failures += "sc.exe qfailure Spooler failed: $_"
}

# 2. No duplicate Brother printer entry (regression)
try {
    $brothers = @(Get-Printer -ErrorAction Stop | Where-Object { $_.Name -like "*Brother*" })
    $duplicates = @($brothers | Where-Object { $_.Name -like "* Printer" })
    if ($duplicates.Count -gt 0) {
        $names = ($duplicates | ForEach-Object { $_.Name }) -join ", "
        $failures += "Duplicate Brother printer entry detected: $names. Fix: Remove-Printer -Name '$names'"
    }
} catch {
    $failures += "Get-Printer failed: $_"
}

if ($Full) {
    # 3. Spooler is running
    try {
        $spooler = Get-Service -Name Spooler -ErrorAction Stop
        if ($spooler.Status -ne "Running") {
            $warnings += "Spooler status: $($spooler.Status) (expected Running)"
        }
    } catch {
        $warnings += "Get-Service Spooler failed: $_"
    }

    # 4. Brother printer exists and is Normal
    try {
        $brother = Get-Printer -Name $PrinterName -ErrorAction Stop
        if ($brother.PrinterStatus -ne "Normal") {
            $warnings += "Printer '$PrinterName' status: $($brother.PrinterStatus) (expected Normal)"
        }
    } catch {
        $warnings += "Printer '$PrinterName' not found"
    }

    # 5. Printer IP reachable
    if (-not (Test-Connection -ComputerName $PrinterIP -Count 1 -Quiet)) {
        $warnings += "Printer IP $PrinterIP unreachable"
    }
}

if ($warnings.Count -gt 0) {
    Write-Host "WARNINGS:" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

if ($failures.Count -gt 0) {
    Write-Host "FAILURES:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "OK: Brother printer regression checks passed" -ForegroundColor Green
exit 0
