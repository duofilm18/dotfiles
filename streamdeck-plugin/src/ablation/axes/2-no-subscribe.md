# Axis 2 — MQTT connected, no SUBSCRIBE

**Hypothesis:** Idle MQTT TCP connection is cheap, but the SUBSCRIBE path
(broker pushes retained messages → mqtt-connection codec parses → handler
mutates cache → `setImage` / `setTitle` to SDK) is what drives plugin Node
CPU. If SUBSCRIBE is the cost driver, skipping it should drop Plugin Node
CPU substantially without changing the StreamDeck.exe / dwm.exe baseline.

**Implementation:** `mqtt-adapter.ts` exports `shouldSubscribeToMqtt()`
returning `CURRENT_AXIS !== "2"`. `mqtt-handler.ts` gates the
`conn.subscribe(...)` call on it. CONNACK still completes, keepalive PING
still runs, socket stays open — only the subscription packet is suppressed.
No retained-message replay, no `publish` events, no rebuild phase, no
downstream `setImage` / `setTitle`.

**Activation:** set `CURRENT_AXIS = "2"` in `_config.ts`, rebuild, deploy.

**Visual side-effect:** Stream Deck keys never receive state updates from
MQTT, so they stay on whatever they were last rendered with (or default if
just installed). Log line `MQTT ablation axis 2: connected without
SUBSCRIBE` appears once per connect.

**Expected if hypothesis true:**
- Plugin Node CPU drops substantially (SUBSCRIBE pipeline is the cost)
- StreamDeck.exe CPU may also drop (no incoming render commands)
- dwm.exe CPU drops (no preview repaints)

**Expected if hypothesis false:**
- Plugin Node CPU stays near T0 (~21% one core)
- Implies cost is upstream of SUBSCRIBE — idle TCP keepalive, codec, or
  Node runtime overhead inside the SD plugin sandbox itself
- Combined with weak Axis 1a signal, points to a host-side regression
  that fires on plugin process activity in general, not on specific
  outgoing commands

**Disable:** `CURRENT_AXIS = "off"`, rebuild, verify CPU returns to T0
±2pp and keys resume rendering on next state change.
