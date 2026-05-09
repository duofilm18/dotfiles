# Stream Deck Claude Monitor Guardrails

This directory contains the Elgato Stream Deck plugin and its out-of-process
MQTT sidecar. Read this before changing runtime architecture.

## Current Production Architecture

The CPU regression is fixed by keeping MQTT out of the Stream Deck plugin
sandbox:

```text
RPi5B mosquitto -> Windows sidecar Node process -> state.json -> SD plugin
```

- Sidecar: `sidecar/sidecar.mjs`, bundled to
  `%LOCALAPPDATA%\claude-monitor\sidecar.js`.
- Plugin reader: `src/state-reader.ts`, polling
  `%LOCALAPPDATA%\claude-monitor\state.json` every 1000 ms.
- Runtime selector: `src/plugin.ts` has `DATA_SOURCE = "file"` for normal
  operation.
- Ablation selector: `src/ablation/_config.ts` must remain
  `CURRENT_AXIS = "off"` outside an active measurement.

Do not move MQTT back into the plugin process as an "optimization".

## Why This Exists

Measured result:

| Mode | StreamDeck.exe | Plugin Node | Sidecar Node |
|---|---:|---:|---:|
| T0 full in-plugin MQTT | 69.23% one-core | 21.05% one-core | n/a |
| T6 no MQTT in plugin | 1.12% one-core | 0.00% one-core | n/a |
| T7 raw TCP in plugin | 67.86% one-core | 20.28% one-core | n/a |
| T8/T9 sidecar + file snapshot | ~1% one-core | ~0% one-core | ~0% one-core |

Precise conclusion: a raw idle TCP socket opened from the Stream Deck plugin
process to the broker is sufficient to reproduce the CPU burn. The MQTT codec,
SUBSCRIBE path, render commands, and PING timer were ruled out by ablation.
The same MQTT workload outside the Stream Deck plugin sandbox is cheap.

Detailed evidence lives in `tests/cpu-ablation-log.md`.

## Do Not Do

- Do not set `DATA_SOURCE = "mqtt"` for production. That is legacy fallback
  and ablation support only.
- Do not open persistent TCP sockets from the plugin process unless you are
  intentionally running a documented ablation.
- Do not replace `mqtt-connection` to fix CPU; T7 proved the codec is not the
  driver.
- Do not use `fs.watch` before proving polling is a problem. The 1000 ms file
  poll measured near zero CPU.
- Do not spawn the sidecar from the plugin. The sidecar lifecycle is managed
  by Task Scheduler to keep it outside the Stream Deck sandbox.

## Build And Deploy

Plugin:

```bash
cd streamdeck-plugin
npm run build
```

Sidecar:

```bash
cd streamdeck-plugin
npm run build:sidecar
```

Register or update the Windows scheduled task after sidecar deploy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ..\windows\install-sidecar-task.ps1
```

Task name: `ClaudeMonitorSidecar`.

## Health Checks

```powershell
Get-ScheduledTask -TaskName ClaudeMonitorSidecar
Get-Content "$env:LOCALAPPDATA\claude-monitor\sidecar.log" -Tail 30
Get-Item "$env:LOCALAPPDATA\claude-monitor\state.json"
```

The sidecar log should show `alive` lines about every 30 seconds. The plugin
keeps the last known good state if `state.json` becomes stale.

Quick CPU check:

```powershell
Get-Process StreamDeck,node | Select-Object ProcessName,Id,CPU,Path
```

For a real measurement, compare CPU deltas over 30-60 seconds instead of
reading the cumulative `CPU` column directly.

## Safe Fallback

If the sidecar is broken and you need a temporary fallback:

1. Stop `ClaudeMonitorSidecar`.
2. Change `src/plugin.ts` `DATA_SOURCE` from `"file"` to `"mqtt"`.
3. Rebuild/deploy the plugin.
4. Expect CPU regression to return.
5. Revert to `"file"` as soon as the sidecar is fixed.

Document any fallback run in `tests/cpu-ablation-log.md` if it is used for
measurement.
