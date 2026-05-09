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
