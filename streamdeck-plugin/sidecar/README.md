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

## Run (PoC — manual)

From PowerShell:

```powershell
& "$env:APPDATA\Elgato\StreamDeck\NodeJS\20.20.0\node.exe" "$env:LOCALAPPDATA\claude-monitor\sidecar.js"
```

Using the SD bundled Node keeps the version identical to the plugin
sandbox so we are isolating only "in-sandbox vs out-of-sandbox", not
"different Node versions".

The sidecar prints heartbeat lines every 30s and writes
`%LOCALAPPDATA%\claude-monitor\state.json` after every state change.

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

## Not in PoC

- Task Scheduler auto-start.
- Health probe / liveness check from plugin to sidecar.
- Stale snapshot detection ("OFFLINE" overlay if `updatedAt` is too
  old).
- `fs.watch`-based reads (defer until polling CPU is verified flat at
  zero).
- Broker / port from settings — currently hardcoded to
  `192.168.88.10:1883`. Plumb via a sidecar config file when needed.
