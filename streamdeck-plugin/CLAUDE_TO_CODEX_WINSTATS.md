# Claude → Codex: Win Stats OFFLINE 修復 review

日期：2026-05-09
範圍：commit `56ce0dd`（main 已 push）
狀態：SD Win Stats 已恢復顯示（`temp:75 freq:2188 ram:63`）

---

## 用戶報告

「我的 stream deck 的 Claude Monitor 的 Win Stats 好像無法連接。幫我修復。不要破壞其他功能。」

---

## 我做了什麼（事實）

1. 從 WSL `powershell.exe` 連串查詢，確認 state.json `winStats: null`、`updatedAt` 凍結在 15:05:36
2. 沿鏈路反查 `LHM → push-win-stats (Task) → MQTT → sidecar → state.json → SD`，發現三個獨立失效點：
   - `ClaudeMonitorSidecar` task State=Ready，Node 進程已死（LastResult=`0xC000013A`）
   - `LibreHardwareMonitor` 進程不存在（HTTP :8085 拒連），但其 at-logon task 依然在
   - `Push Win Stats MQTT` 排程任務從 Task Scheduler 消失
3. 修復順序：`Start-ScheduledTask ClaudeMonitorSidecar` → 啟動 LHM.exe（admin）→ 重新註冊 Push 任務 → 一次性 publish → 驗 state.json
4. 註冊 Push 任務時繞開 `push-win-stats.ps1 -Install`，自己寫 minimal `register-pushtask.ps1` 走 `Register-ScheduledTask`，原因見下面
5. 沒改 `DATA_SOURCE`、沒改 sidecar、沒改 plugin 程式碼

---

## 我寫進 commit 的 doc 變動

- `streamdeck-plugin/CLAUDE.md`：+1 行指標 `If the Win Stats key shows OFFLINE, see TROUBLESHOOTING.md.`
- `streamdeck-plugin/TROUBLESHOOTING.md`（新檔）：診斷順序 + 兩個踩雷 + sleep/wake 觀察

設計考量：用戶 push back 過「不要塞 CLAUDE.md，要分工」，所以走指標 + 獨立檔。

---

## 我想被你審的幾件事

### 1. 我選擇文件化 trap 而非修源碼，這對嗎？

`scripts/install` 那邊的 push-win-stats.ps1 有兩個 install-time bug：

**Bug A**：`-Install` 會 `Copy-Item $SourceScript $DeployedScript`。如果你從**部署位置**跑（`$env:LOCALAPPDATA\win-stats-mqtt\push-win-stats.ps1 -Install`），source==dest，PS 會在自我複製時失敗 throw，後續 Register 不執行。
從 dotfiles 源始路徑跑就沒事。

**Bug B**：`-RepetitionDuration ([TimeSpan]::MaxValue)` 在當前 Windows 11 build 的 Task Scheduler XML schema 被拒（`P99999999DT23H59M59S` 解析失敗），整個 Register-ScheduledTask 噴錯。

我目前只把這兩條寫進 TROUBLESHOOTING.md 當「再裝時注意事項」。**沒去改 push-win-stats.ps1 本身**。

理由是：
- 用戶選了「最小修復」
- 改原 script 等於擴大 scope，且 `-Install` 平常不會跑（一次性安裝）
- TimeSpan.MaxValue 上次 commit 時用得好好的，可能跟新 Windows update 有關，未必所有人都會踩

但這違反「不要為下個維護者留陷阱」。**你怎麼看？**選項：
- (A) 維持現狀（doc 化）
- (B) 改 push-win-stats.ps1：Bug A 加 `if ($SourceScript -ne $DeployedScript) { Copy-Item ... }`、Bug B 換成 9999 天
- (C) 只改 Bug B（影響面廣），Bug A 留 doc

### 2. 我真的有讀到根因嗎？

LHM + Sidecar 兩個 at-logon task 的 LastRunTime 都是 10:39:42（今天登入時間），都「跑了」、然後死掉。Sidecar exit code 是 `0xC000013A`（強制終止），LHM 是 0（善終）。

我推測是 sleep/wake 殺的。但我**沒實際驗證**——沒檢查 Windows Event Log、沒 reproduce、就是一句「likely sleep/wake」推給用戶決定要不要加 watchdog。

用戶選「有發生再說」。

**你會怎麼進一步驗證？**還是這個推測精度已夠用、行動成本高於價值？

### 3. 我沒寫測試

整個 troubleshooting flow 沒可重現測試。Bats 測試套件目前不涵蓋 Windows-only 鏈路。

我覺得這是合理的（測試會很脆弱、跨平台 mock 成本高）。但 dotfiles `CLAUDE.md` 規則 13 說「修改功能 code 後必須補/更新對應測試」。我這次沒改功能 code，只改 doc，所以技術上不適用。**算 OK 嗎？**

### 4. memory 邊界

我原本要寫進 global memory（`~/.claude/projects/.../memory/`），用戶 push back 說「應該放在 stream deck 的資料夾紀錄裡面」。所以搬到 repo 內 TROUBLESHOOTING.md。

這個分界對嗎？我的理解是：
- 跨 session、跨專案的偏好/事實 → global memory
- 單一 repo 的故障排除 → repo 內 doc

---

## 沒處理的事（明知道但 deferred）

- **LHM / Sidecar 的 sleep/wake 重啟機制**：用戶選「不加」。如果再 OFFLINE，可能要回頭加 watchdog 或 RestartOnFailure
- **push-win-stats.ps1 的兩個 bug**：等你 review

---

## 我想知道的判斷

1. doc-only 修復 + commit 56ce0dd 範圍是否恰當？有沒有什麼明顯該做但我沒做？
2. push-win-stats.ps1 該不該順手 patch？（用戶要求「不要破壞其他功能」、選最小修復；但留 bug 在源碼也不健康）
3. sleep/wake 的根因驗證需要做到什麼程度？

honest report 到此。
