# Axis 7 — Raw TCP socket only, no MQTT codec

**Hypothesis:** The CPU cost in T0/T2 lives in the `mqtt-connection` codec
event loop (parsing incoming bytes, maintaining decoder state, firing
'publish' / 'connack' events) and/or the 50s `setInterval` PING timer.
The bare TCP socket itself is cheap. T6 cannot tell us this because it
removed everything at once.

**Implementation:** `mqtt-adapter.ts` exports `shouldUseMqttCodec()`
returning `CURRENT_AXIS !== "7"`. `mqtt-handler.ts` `openSocket()` checks
the gate after creating the socket. When codec is disabled:
- Send a single hand-built MQTT 3.1.1 CONNECT packet with keepalive=0 so
  mosquitto keeps the connection forever without expecting PINGs.
- Attach a no-op `data` listener that drains and discards all incoming
  bytes (so the read buffer doesn't fill).
- Do NOT call `mqttCon(sock)`. No codec, no parser, no event emitters.
- Do NOT start the 50s PING `setInterval`.
- Keep `close` → reconnect handler in case the socket dies.

This validates the existing memory entry "raw TCP idle 連線只 1.5%" inside
the new ablation harness using the same broker, same SD plugin sandbox,
same Node version, same SDK version.

**Activation:** set `CURRENT_AXIS = "7"` in `_config.ts`, rebuild, deploy.

**Visual side-effect:** Plugin log shows
`MQTT ablation axis 7: raw TCP, no codec` after socket open. No
`MQTT connected, rebuilding...` line. Stream Deck keys never get state
updates (no SUBSCRIBE).

**Expected if hypothesis true (codec / PING is the cost):**
- Plugin Node CPU drops to near zero (matching T6) or to ~1-2% one core
- StreamDeck.exe CPU drops dramatically (close to T6's 1.12%)
- Confirms the fix path is: replace mqtt-connection with a minimal codec
  that does only CONNECT / SUBSCRIBE / PUBLISH / PINGRESP

**Expected if hypothesis false (raw socket itself is the cost):**
- Plugin Node CPU stays around T0/T2 level (~20% one core)
- StreamDeck.exe stays around T0/T2 level (~66% one core)
- Means just having an open TCP socket from plugin process is enough to
  trigger the regression. No amount of codec rewriting will help — the
  fix must move MQTT out of the plugin process entirely (sidecar,
  Stream Deck plugin running a thin SDK-only client that talks to a
  separate Windows-side bridge over a different channel).

**Disable:** `CURRENT_AXIS = "off"`, rebuild, verify CPU returns to T0
±2pp and MQTT subscribe/rebuild path resumes.
