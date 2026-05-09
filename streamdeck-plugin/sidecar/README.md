# claude-monitor sidecar (PoC)

Out-of-process MQTT subscriber that decouples MQTT from the Stream Deck
plugin sandbox. Plugin polls `state.json`, sidecar writes it. See
[`../tests/cpu-ablation-log.md`](../tests/cpu-ablation-log.md) (T0..T8)
for why this exists.

## Build & deploy

```bash
cd streamdeck-plugin
npm run build:sidecar
```

That bundles `sidecar/sidecar.mjs` (with its `mqtt-connection`
dependency) to `sidecar/dist/sidecar.js` and copies it to
`%LOCALAPPDATA%\claude-monitor\sidecar.js` via `deploy-paths.sh`.

## Run

### Production: Task Scheduler (auto-start at logon)

After `npm run build:sidecar`, register the scheduled task once:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\install-sidecar-task.ps1
```

The task `ClaudeMonitorSidecar` is registered to run at every user logon
under the current user (so `%LOCALAPPDATA%` resolves correctly), with
auto-restart on failure (1 min interval, 3 retries). Output is captured
in `%LOCALAPPDATA%\claude-monitor\sidecar.log`.

Common operations after install:

```powershell
Start-ScheduledTask -TaskName ClaudeMonitorSidecar
Stop-ScheduledTask  -TaskName ClaudeMonitorSidecar
Get-ScheduledTask   -TaskName ClaudeMonitorSidecar | Format-List
Get-Content "$env:LOCALAPPDATA\claude-monitor\sidecar.log" -Tail 30 -Wait
Unregister-ScheduledTask -TaskName ClaudeMonitorSidecar -Confirm:$false
```

### Manual (debugging)

If you need to run without Task Scheduler:

```powershell
& "$env:APPDATA\Elgato\StreamDeck\NodeJS\20.20.0\node.exe" "$env:LOCALAPPDATA\claude-monitor\sidecar.js"
```

Using the SD bundled Node keeps the Node version identical to the plugin
sandbox.

The sidecar prints heartbeat lines every 30s, bumps the snapshot
`updatedAt` timestamp on each heartbeat (so the plugin can distinguish
"alive but idle" from "dead"), and writes `state.json` atomically after
every change.

## State file shape (version 1)

```json
{
  "version": 1,
  "updatedAt": "2026-05-09T03:30:00.000Z",
  "rebuildId": 1,
  "projects": { "<project>": "<state>" },
  "sysStats": { "temp": 0, "ram": 0 },
  "winStats": { "temp": 0, "freq": 0, "ram": 0 }
}
```

`rebuildId` increments after each MQTT (re)connect rebuild phase. The
plugin treats a changed `rebuildId` as a full reset and replays the
`projects` map; same `rebuildId` means apply incremental diff.

## Plugin pairing

The plugin `src/state-reader.ts` polls this file every 1000 ms by
default. To re-enable in-process MQTT (legacy / fallback), flip
`DATA_SOURCE` in `src/plugin.ts` from `"file"` to `"mqtt"`.

## Liveness

The plugin's `StateReader` treats a snapshot as stale if `updatedAt` is
more than 60 seconds old (= one missed sidecar heartbeat). Stale
snapshots are not applied — the keys keep showing the last known good
state until the sidecar comes back. A throttled warning is logged
(`[state-reader] snapshot stale: Ns old`) and a recovery line
(`[state-reader] snapshot fresh again, resuming updates`) when it
returns.

If the sidecar crashes outright, Task Scheduler restarts it after 1
minute (up to 3 retries). During the restart window the plugin keys
freeze at last known state.

## Not yet implemented (future)

- Render a "STALE" overlay on keys (currently only logs) — needs an
  action-side helper.
- Plugin → sidecar liveness probe (currently relies on file freshness).
- `fs.watch`-based reads (defer until polling CPU is verified flat at
  zero across more workloads — Codex Round 5 deferred this).
- Broker / port from SD globalSettings — currently hardcoded to
  `192.168.88.10:1883` in `sidecar.mjs`. Plumb via a sidecar config
  file when needed.
