# install-shortcut.ps1 - Create desktop shortcut for Brother printer repair
#
# Run from WSL:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass \
#       -File "$(wslpath -w ~/dotfiles/windows/brother-printer/install-shortcut.ps1)"
#
# Run from Windows: right-click -> Run with PowerShell

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$repairPath = Join-Path $PSScriptRoot "repair.ps1"
if (-not (Test-Path $repairPath)) {
    Write-Host "ERROR: repair.ps1 not found at $repairPath" -ForegroundColor Red
    exit 1
}

$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop "Brother Printer Repair.lnk"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$repairPath`""
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = "Brother DCP-T820DW one-click repair (Spooler restart + healthcheck)"
$shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,17"
$shortcut.Save()

Write-Host "Created: $shortcutPath" -ForegroundColor Green
Write-Host ""
Write-Host "Double-click the shortcut to repair Brother printer." -ForegroundColor Cyan
Write-Host "(UAC prompt will appear - click Yes)" -ForegroundColor Cyan
