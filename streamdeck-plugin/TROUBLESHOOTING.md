# Stream Deck Claude Monitor — Troubleshooting

## Win Stats key shows OFFLINE

Walk the chain `LHM → push-win-stats (Task) → MQTT → sidecar → state.json → SD`
from top down:

1. `Get-Content "$env:LOCALAPPDATA\claude-monitor\state.json"` — is `winStats == null`?
2. `Get-ScheduledTask -TaskName 'ClaudeMonitorSidecar'` — `Ready` not `Running` → `Start-ScheduledTask`
3. `Invoke-WebRequest http://localhost:8085/data.json -TimeoutSec 3` — refused → `Start-ScheduledTask -TaskName LibreHardwareMonitor`
4. `Get-ScheduledTask -TaskName 'Push Win Stats MQTT'` — missing → re-register (see traps below)

### Known traps when re-registering Push Win Stats MQTT

- **Don't run `push-win-stats.ps1 -Install` from the deployed copy** — `Copy-Item $SourceScript $DeployedScript` becomes source==dest, file is locked, throws silently (Write-Host doesn't pipe). Run from dotfiles source, or call `Register-ScheduledTask` directly with the deployed path.
- `-RepetitionDuration ([TimeSpan]::MaxValue)` fails current Windows TS XML schema (`P99999999DT23H59M59S`). Use `(New-TimeSpan -Days 9999)`.
- `State=Ready` after registering is normal for a 1-min repetition trigger — not "broken".

### Sleep/wake fragility

LHM and ClaudeMonitorSidecar processes both die across sleep/wake despite healthy at-logon tasks. No auto-restart today. If recurring, add `RestartOnFailure` to the tasks or a small watchdog. (User declined 2026-05-09; revisit only if it happens again.)
