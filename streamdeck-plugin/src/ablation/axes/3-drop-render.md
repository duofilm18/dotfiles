# Axis 3 — drop SDK render commands

**Hypothesis:** MQTT receive / parse / in-memory state mutation is cheap. The
SDK IPC path (sending `setImage` / `setTitle` to Stream Deck host) is what
triggers host-side regression.

**Implementation:** `ws-send-patch.ts` drops outgoing `setImage` / `setTitle`
commands entirely (returns without calling original `send`). All MQTT receive,
JSON parse, action-internal cache, and `assignments` / `projectStates` mutation
still run normally. Other SDK commands (register, settings, etc.) pass through.

**Activation:** set `CURRENT_AXIS = "3"` in `_config.ts`, rebuild, deploy.

**Visual side-effect:** Stream Deck keys will not update (image and title stay
on whatever was last rendered before activation, or default if just installed).
This is expected and proves the patch is active.

**Expected if hypothesis true:**
- All three CPU figures drop substantially
- Implies SDK IPC / host repaint is the primary trigger

**Expected if hypothesis false:**
- Plugin Node CPU drops slightly (no setImage/setTitle work) but
  `StreamDeck.exe` and `dwm.exe` stay high
- Implies regression is in MQTT codec, plugin runtime, or host's reaction to
  plugin process activity (not to specific render commands)

**Disable:** `CURRENT_AXIS = "off"`, rebuild, verify CPU returns to T0 ±2pp and
keys resume rendering.
