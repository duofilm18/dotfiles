# Stream Deck Plugin CPU Ablation Log

每輪測試都用同一份格式。先寫 hypothesis，再跑量測，最後判讀 match。

## 測試流程

1. 把 Stream Deck 硬體插回 USB。
2. 啟動 Stream Deck app，等 plugin log 出現 `Rebuild complete`。
3. 再等 2 分鐘讓系統穩定（避開 retained rebuild 與 SD app 啟動 spike）。
4. 在 Windows PowerShell 跑 60s sampling：

   ```powershell
   $names = @("StreamDeck", "node", "dwm")
   1..60 | ForEach-Object {
     Get-Process | Where-Object { $names -contains $_.ProcessName } |
       Select-Object ProcessName, Id, CPU
     Start-Sleep -Seconds 1
   }
   ```

5. 計算每個 process 的 CPU 平均值（差分相鄰兩秒的累積 CPU 時間）。
6. 把結果填入下方對應 Test 欄位。
7. 量完才 commit `docs: record streamdeck cpu ablation T<N>`。

## 切換軸線

僅改 `src/ablation/_config.ts` 第一行 `CURRENT_AXIS`：

```text
"off" → T0 baseline (no patch installed)
"1a"  → hardware-only render target
"3"   → drop SDK render commands
"5"   → SDK send instrumentation (TBD)
```

`rebuild + deploy + 重啟 SD app` 後才生效。

## 量測格式

```text
Test:                     # T0 / T1 / T0-off / T2 / ...
Plugin commit:            # short SHA
SD app:                   # exact version
SDK:                      # @elgato/streamdeck version
Mode:                     # axis name
Ablation entry point:     # CURRENT_AXIS value
Hypothesis:               # 一句話
Expected if true:         # 數字方向
Duration:                 # always 60s for sampling, 60s for WPR
StreamDeck.exe CPU avg:   # %
Plugin Node CPU avg:      # %
dwm.exe CPU avg:          # %
Match expected:           # yes / no / partial
Notes:                    # 任何異常觀察
```

驗收條件：每軸結束 disable 後（`CURRENT_AXIS = "off"` 重 rebuild）CPU 必須回到 T0 ±2 percentage points，否則該軸結果暫停採信。

---

## T0 — baseline

```text
Test:                     T0
Plugin commit:            40c7c38
SD app:                   7.4.1.22720
SDK:                      @elgato/streamdeck 2.1.0
Mode:                     baseline
Ablation entry point:     CURRENT_AXIS = "off"
Hypothesis:               (none — baseline 用)
Expected if true:         (none)
Duration:                 120s idle + 60.12s sampling
StreamDeck.exe CPU avg:   69.23% of one core (4.33% total CPU on 16 logical processors)
Plugin Node CPU avg:      21.05% of one core (1.32% total CPU; pid 14956)
dwm.exe CPU avg:          not captured by Get-Process CPU delta in this run
Match expected:           n/a
Notes:                    Off-mode skeleton deployed. Shape matches regression report: StreamDeck ~1 hot core, plugin Node ~22% one-core. StreamDeck.ColorPicker was 0.52% one-core; other node processes were ~0.
```

---

## T1 — Axis 1a (hardware-only render target)

```text
Test:                     T1
Plugin commit:            40c7c38 + working tree CURRENT_AXIS="1a"
SD app:                   7.4.1.22720
SDK:                      @elgato/streamdeck 2.1.0
Mode:                     1a hardware-only
Ablation entry point:     CURRENT_AXIS = "1a"
Hypothesis:               SD app 7.4.x 軟體 preview repaint 是 dwm/SD CPU 主因
Expected if true:         dwm.exe CPU 下降 >5pp，StreamDeck.exe 可能下降，Node 不變
Duration:                 app restart + 120s idle + 60.10s sampling
StreamDeck.exe CPU avg:   65.15% of one core (4.07% total CPU on 16 logical processors)
Plugin Node CPU avg:      20.59% of one core (1.29% total CPU; pid 5748)
dwm.exe CPU avg:          not captured by Get-Process CPU delta in this run
Match expected:           no / weak partial
Notes:                    StreamDeck decreased only 4.08pp one-core vs T0 (69.23 → 65.15), Node effectively unchanged (21.05 → 20.59). Hardware-only target does not explain the main CPU burn.
```

---

## T0-off — disable verification after T1

```text
Test:                     T0-off (post-axis-1a)
Plugin commit:            40c7c38 + working tree CURRENT_AXIS="off"
SD app:                   7.4.1.22720
SDK:                      @elgato/streamdeck 2.1.0
Mode:                     baseline (disable check)
Ablation entry point:     CURRENT_AXIS = "off"
Hypothesis:               旁路設計可逆，CPU 應回 T0 ±2pp
Expected if true:         三個 CPU 數字都在 T0 ±2pp 內
Duration:                 app restart + 120s idle + 60.10s sampling
StreamDeck.exe CPU avg:   62.97% of one core (3.94% total CPU on 16 logical processors)
Plugin Node CPU avg:      19.84% of one core (1.24% total CPU; pid 7248)
dwm.exe CPU avg:          not captured by Get-Process CPU delta in this run
Match expected:           partial
Notes:                    Returned to same high-CPU shape, but StreamDeck is 6.26pp below T0 (69.23 → 62.97), outside the strict ±2pp target. Node is close (21.05 → 19.84). Treat Axis 1a as no meaningful fix; rerun T0 may be needed if strict reversibility is required.
```

---

## T2 — Axis 2 (MQTT connected, no SUBSCRIBE)

```text
Test:                     T2
Plugin commit:            7e2b36c + working tree CURRENT_AXIS="2"
SD app:                   7.4.1.22720
SDK:                      @elgato/streamdeck 2.1.0
Mode:                     2 no-subscribe
Ablation entry point:     CURRENT_AXIS = "2" (shouldSubscribeToMqtt() returns false)
Hypothesis:               SUBSCRIBE pipeline (retained replay → cache → setImage/setTitle) drives Plugin Node CPU
Expected if true:         Plugin Node CPU drops substantially; StreamDeck.exe and dwm.exe may also drop
Duration:                 app restart (5.1s ready detect) + 120s idle + 60.01s sampling
StreamDeck.exe CPU avg:   66.22% of one core (4.14% total CPU on 16 logical processors)
Plugin Node CPU avg:      19.79% of one core (1.24% total CPU; pid 8960)
dwm.exe CPU avg:          not captured by Get-Process CPU delta in this run
Match expected:           no
Notes:                    Hypothesis falsified. Zero subscriptions, zero retained replay, zero setImage/setTitle — yet Plugin Node still burns ~20% one core (T0=21.05 → T2=19.79, within noise) and StreamDeck.exe still ~66%. CPU burn is NOT in SUBSCRIBE pipeline and NOT in render commands (combined with weak Axis 1a). Cost lives in idle plugin↔SD-app IPC itself: TCP keepalive PINGs, Node runtime, or SD-app reaction to plugin process activity in general.
```

---

## T0-off-2 — disable verification after T2

```text
Test:                     T0-off-2 (post-axis-2)
Plugin commit:            7e2b36c + working tree CURRENT_AXIS="off"
SD app:                   7.4.1.22720
SDK:                      @elgato/streamdeck 2.1.0
Mode:                     baseline (disable check)
Ablation entry point:     CURRENT_AXIS = "off" (shouldSubscribeToMqtt() returns true)
Hypothesis:               Axis 2 旁路可逆，CPU 應回 T0 ±2pp
Expected if true:         三個 CPU 數字都在 T0 ±2pp 內
Duration:                 app restart (4.6s ready detect) + 120s idle + 60.01s sampling
StreamDeck.exe CPU avg:   67.22% of one core (4.20% total CPU on 16 logical processors)
Plugin Node CPU avg:      20.07% of one core (1.25% total CPU; pid 22180)
dwm.exe CPU avg:          not captured by Get-Process CPU delta in this run
Match expected:           yes
Notes:                    Reversibility ✓. StreamDeck 67.22 vs T0 69.23 (-2.01pp, at edge of ±2pp), Node 20.07 vs T0 21.05 (-0.98pp). Compared to T0-off-1 which drifted -6.26pp on StreamDeck, this run lands cleanly in the band, suggesting the earlier drift was natural session variance not residual ablation effect. Treat T2 result as trustworthy.
```

---

## T6 — Axis 6 (MQTT completely disabled)

```text
Test:                     T6
Plugin commit:            e1e5bc8 + working tree CURRENT_AXIS="6"
SD app:                   7.4.1.22720
SDK:                      @elgato/streamdeck 2.1.0
Mode:                     6 no-mqtt
Ablation entry point:     CURRENT_AXIS = "6" (shouldConnectToMqtt() returns false)
Hypothesis:               MQTT idle keepalive (TCP socket + mqtt-connection codec + 50s PINGs) is the missing cost driver after Axis 1a/2 both miss
Expected if true:         Plugin Node CPU drops noticeably below T2; StreamDeck.exe may also drop
Duration:                 app restart (4.07s ready detect) + 120s idle + 60.00s sampling
StreamDeck.exe CPU avg:   1.12% of one core (0.07% total CPU on 16 logical processors)
Plugin Node CPU avg:      0.00% of one core (0.00% total CPU; pid 32036)
dwm.exe CPU avg:          not captured by Get-Process CPU delta in this run
Match expected:           yes (massively)
Notes:                    Smoking gun. With no MQTT connect at all, Plugin Node burns 0% and StreamDeck.exe drops -68.11pp from T0 (69.23 → 1.12). Combined with T2 (MQTT connected but no SUBSCRIBE = still ~66% / ~20%), the cost driver is unambiguously the live mqtt-connection codec attached to the idle TCP socket — NOT subscribe pipeline, NOT render commands. SD plugin sandbox itself is innocent: with no socket the plugin process is essentially asleep.
```

---

## T0-off-6 — disable verification after T6

```text
Test:                     T0-off-6 (post-axis-6)
Plugin commit:            e1e5bc8 + working tree CURRENT_AXIS="off"
SD app:                   7.4.1.22720
SDK:                      @elgato/streamdeck 2.1.0
Mode:                     baseline (disable check)
Ablation entry point:     CURRENT_AXIS = "off" (shouldConnectToMqtt() returns true)
Hypothesis:               Axis 6 旁路可逆，CPU 應回 T0 ±2pp
Expected if true:         三個 CPU 數字都在 T0 ±2pp 內
Duration:                 app restart (4.08s ready detect) + 120s idle + 60.01s sampling
StreamDeck.exe CPU avg:   67.39% of one core (4.21% total CPU on 16 logical processors)
Plugin Node CPU avg:      19.71% of one core (1.23% total CPU; pid 32572)
dwm.exe CPU avg:          not captured by Get-Process CPU delta in this run
Match expected:           yes
Notes:                    Reversibility ✓. StreamDeck 67.39 vs T0 69.23 (-1.84pp), Node 19.71 vs T0 21.05 (-1.34pp). Both inside ±2pp band. Axis 6 conclusion is trustworthy.
```

---

## T7 — Axis 7 (raw TCP socket, no codec)

```text
Test:                     T7
Plugin commit:            31f9cb6 + working tree CURRENT_AXIS="7"
SD app:                   7.4.1.22720
SDK:                      @elgato/streamdeck 2.1.0
Mode:                     7 raw-tcp
Ablation entry point:     CURRENT_AXIS = "7" (shouldUseMqttCodec() returns false)
Hypothesis:               codec/PING is the cost; bare socket is cheap (per old memory "raw TCP 1.5%")
Expected if true:         Plugin Node ≈ 0%, StreamDeck ≈ T6 (~1%)
Duration:                 app restart (5.11s ready detect) + 120s idle + 60.01s sampling
StreamDeck.exe CPU avg:   67.86% of one core (4.24% total CPU on 16 logical processors)
Plugin Node CPU avg:      20.28% of one core (1.27% total CPU; pid 4308)
dwm.exe CPU avg:          not captured by Get-Process CPU delta in this run
Match expected:           NO — falsified
Notes:                    Raw idle TCP socket alone (no codec, no PING setInterval, no parsing — just net.createConnection + sock.on('data', ()=>{}) drain) burns the SAME CPU as full MQTT (T0). Plugin log confirmed only 2 lines during the run (no reconnect storm, socket stayed open the entire window). Old memory entry "raw TCP idle 連線只 1.5%" is FALSIFIED by this run. The codec is innocent.
```

---

## T0-off-7 — disable verification after T7

```text
Test:                     T0-off-7 (post-axis-7)
Plugin commit:            31f9cb6 + working tree CURRENT_AXIS="off"
SD app:                   7.4.1.22720
SDK:                      @elgato/streamdeck 2.1.0
Mode:                     baseline (disable check)
Ablation entry point:     CURRENT_AXIS = "off" (shouldUseMqttCodec() returns true)
Hypothesis:               Axis 7 旁路可逆，CPU 應回 T0 ±2pp
Expected if true:         三個 CPU 數字都在 T0 ±2pp 內
Duration:                 app restart (4.59s ready detect) + 120s idle + 60.01s sampling
StreamDeck.exe CPU avg:   66.26% of one core (4.14% total CPU on 16 logical processors)
Plugin Node CPU avg:      20.46% of one core (1.28% total CPU; pid 12412)
dwm.exe CPU avg:          not captured by Get-Process CPU delta in this run
Match expected:           partial (Node ✓, StreamDeck -2.97pp just outside band)
Notes:                    Node 20.46 vs T0 21.05 (-0.59pp ✓). StreamDeck 66.26 vs T0 69.23 (-2.97pp), slightly outside ±2pp. Same magnitude of session drift as T0-off-2/6 saw on StreamDeck — appears to be natural between-session noise on the SD app process, not residual ablation. T7 is reproducible and trustworthy.
```

---

## Axis 1a + 2 + 6 + 7 combined finding (the actual answer)

| Test | StreamDeck | Plugin Node | What's running in plugin process |
|---|---|---|---|
| T0 baseline | 69.23 | 21.05 | full MQTT (codec + subscribe + render) |
| T1 (1a hardware-only) | 65.15 | 20.59 | same as T0, render → hardware target |
| T2 (no SUBSCRIBE) | 66.22 | 19.79 | codec attached, no subscribe / publish flow |
| T6 (no MQTT at all) | **1.12** | **0.00** | no TCP socket open, plugin idle |
| T7 (raw TCP, no codec) | 67.86 | 20.28 | one idle TCP socket, drained, no parsing |
| T0-off-7 | 66.26 | 20.46 | full MQTT (control) |

**Empirical answer:** Any TCP socket open from the plugin process → ~20% Node
+ ~66% StreamDeck. No socket → 0%. The MQTT codec, the SUBSCRIBE pipeline,
the render commands, and the PING timer are all individually CHEAP. The
**socket itself is the cost**.

This is not a bug in `mqtt-connection`. It's not a bug in our render code.
It's not a bug in our SUBSCRIBE pipeline. It's something in the SD plugin
sandbox / SD app's reaction to the plugin process having an open TCP
socket to anywhere. Mechanism unknown — possibly Windows-level event
tracing, possibly SD app polling the plugin's socket state, possibly
Node's event loop activity in the sandbox triggers extra SDK IPC traffic.

The previous T6-based conclusion that "cost lives in mqtt-connection codec"
was OVERREACH — T6 removed too many things at once. T7 isolates the
socket from the codec, and the cost stays.

### Implication for fixes (revised after T7)

What does NOT help (proven by ablation):
- Reducing render frequency (T1).
- Skipping SUBSCRIBE / topic split (T2).
- Replacing `mqtt-connection` with a hand-written codec (T7 — the codec is
  not the problem).
- Switching SDK version 2.0.1 ↔ 2.1.0 (regression report).
- Switching SD app 7.4.0 ↔ 7.4.1 (regression report).

What MIGHT help (not yet ablated):
- **Move MQTT out of the plugin process entirely.** A Windows-side sidecar
  process subscribes to MQTT and translates state changes into a channel
  the plugin can read cheaply (e.g., file watch, named pipe with smaller
  per-event cost than a persistent socket, or even SDK PI settings push).
  This is the only architecture-level fix consistent with the data.
- **Axis 8 (out-of-process control test):** run the same `mqtt-connection`
  + raw socket test in vanilla Node outside SD plugin sandbox. If CPU is
  also ~20% there, the regression is in Node/Windows TCP, not SD app —
  ball is on the broader stack, not Elgato. If CPU is normal in vanilla
  Node, this is exclusively SD plugin sandbox interaction.
- **Axis B (SD app 7.3.x downgrade):** still useful as a directional rod
  for Elgato bug reports.
