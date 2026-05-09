# Axis 6 — MQTT completely disabled

**Hypothesis:** With Axis 1a and Axis 2 both miss (render path and SUBSCRIBE
pipeline neither dominate CPU), the remaining suspects are the MQTT keepalive
loop (idle TCP socket + `mqtt-connection` codec PINGs every 50s) and the
SD-IPC layer (plugin↔SD-app `ws://127.0.0.1`). Axis 6 cuts MQTT entirely so
SD-IPC stands alone as the only persistent non-trivial work.

**Implementation:** `mqtt-adapter.ts` exports `shouldConnectToMqtt()` returning
`CURRENT_AXIS !== "6"`. `plugin.ts` `connectMqtt()` early-returns when the
gate denies. No socket open, no `MqttHandler.connect()`, no PING timer, no
codec instantiation. Stream Deck SDK plugin still starts, all actions still
register, the `setTimeout(connectMqtt, 500)` and
`onDidReceiveGlobalSettings` callback both no-op.

**Activation:** set `CURRENT_AXIS = "6"` in `_config.ts`, rebuild, deploy.

**Visual side-effect:** Stream Deck keys never receive any state updates.
Plugin log shows `MQTT ablation axis 6: connect skipped` instead of
`MQTT connecting to ...`.

**Expected if hypothesis true (MQTT keepalive is meaningful cost):**
- Plugin Node CPU drops noticeably below T2 (which still had idle MQTT socket
  + PINGs)
- StreamDeck.exe may also drop slightly (one fewer event source)

**Expected if hypothesis false (MQTT is innocent):**
- Plugin Node CPU stays near T0/T2 (~20% one core)
- StreamDeck.exe stays near T0/T2 (~66% one core)
- Conclusive evidence the burn is in SD plugin sandbox / SDK IPC itself,
  not in any work the plugin does. Ball moves entirely to Elgato.

**Disable:** `CURRENT_AXIS = "off"`, rebuild, verify CPU returns to T0 ±2pp
and MQTT reconnects on next plugin start.
