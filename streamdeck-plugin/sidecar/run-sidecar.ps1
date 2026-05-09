# Wrapper that Task Scheduler invokes. Runs the sidecar with the SD bundled
# Node binary, redirects stdout+stderr to a rotating log file via cmd.exe
# so Node's UTF-8 output is preserved byte-for-byte (PowerShell's *>> would
# transcode to UTF-16 by default on Windows PowerShell 5).
#
# Deployed to %LOCALAPPDATA%\claude-monitor\run-sidecar.ps1 by `npm run build:sidecar`.
# Source of truth: streamdeck-plugin/sidecar/run-sidecar.ps1.

$ErrorActionPreference = "Continue"

$node   = "$env:APPDATA\Elgato\StreamDeck\NodeJS\20.20.0\node.exe"
$script = "$env:LOCALAPPDATA\claude-monitor\sidecar.js"
$log    = "$env:LOCALAPPDATA\claude-monitor\sidecar.log"

# Cheap log rotation: drop log if it grows past 10MB.
if ((Test-Path $log) -and (Get-Item $log).Length -gt 10MB) {
    Remove-Item $log -Force -ErrorAction SilentlyContinue
}

$marker = "--- sidecar starting at $(Get-Date -Format 'o') ---`r`n"
[System.IO.File]::AppendAllText($log, $marker, [System.Text.UTF8Encoding]::new($false))

# cmd.exe stdio redirection passes raw bytes (Node writes UTF-8). The "/d"
# disables AutoRun reg entries; "/c" runs and exits.
& cmd.exe /d /c "`"$node`" `"$script`" >>`"$log`" 2>&1"
$exit = $LASTEXITCODE

$marker = "--- sidecar exited at $(Get-Date -Format 'o') with code $exit ---`r`n"
[System.IO.File]::AppendAllText($log, $marker, [System.Text.UTF8Encoding]::new($false))
exit $exit
