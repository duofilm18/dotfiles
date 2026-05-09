# Axis 1a — hardware-only render target

**Hypothesis:** Stream Deck app 7.4.x updates both hardware and software preview
on every `setImage` / `setTitle` by default. Software preview repaint is what
drives `dwm.exe` and possibly `StreamDeck.exe` CPU.

**Implementation:** `ws-send-patch.ts` intercepts outgoing `setImage` / `setTitle`
commands and merges `payload.target = 1` (Target.Hardware). All other commands
(register, getSettings, sendToPropertyInspector, etc.) pass through unchanged.

**Activation:** set `CURRENT_AXIS = "1a"` in `_config.ts`, rebuild, deploy.

**Expected if hypothesis true:**
- `dwm.exe` CPU drops by >5 percentage points
- `StreamDeck.exe` CPU may also drop
- Plugin Node CPU unchanged (work upstream of patch is identical)

**Expected if hypothesis false:**
- All three CPU figures within ±2pp of T0
- Implies regression is upstream of preview repaint (SDK IPC, MQTT path, host
  message routing)

**Disable:** `CURRENT_AXIS = "off"`, rebuild, verify CPU returns to T0 ±2pp.
