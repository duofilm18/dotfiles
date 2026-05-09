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

### Process death after long uptime (root cause unverified)

Observed once on 2026-05-09: both LHM and ClaudeMonitorSidecar processes were gone despite their at-logon tasks being healthy. Exit codes (sidecar `0xC000013A`, LHM `0`) are *consistent with* a sleep/wake cycle but this remains a hypothesis — not yet verified against system events.

To verify when it recurs, cross-reference timestamps in:
- `Microsoft-Windows-TaskScheduler/Operational` log
- `Kernel-Power` and `Power-Troubleshooter` logs
- The sidecar log's last `alive` line vs the next sleep/resume event

Existing restart policy:
- **Sidecar:** `RestartInterval 1min / RestartCount 3` (see `windows/install-sidecar-task.ps1`). After 3 failed restarts Task Scheduler stops retrying. Check Task Scheduler history if the process is gone — restarts may have been exhausted.
- **LHM:** no restart policy. Once the GUI process dies, only logon revives it.

Don't add a watchdog or change restart counts unless this actually recurs. User declined 2026-05-09.
