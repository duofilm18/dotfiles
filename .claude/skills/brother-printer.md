---
name: brother-printer
description: >
  Brother 網路印表機無法列印、離線、或 Claude/Codex 想先亂查 CUPS/LPSTAT 時的固定排查流程。
  這台環境的已知根因是 Windows Print Spooler 停掉或 Brother 驅動衝突；先讀既有文檔，
  再用 Windows PowerShell 診斷與修復，不要先發明 Linux/CUPS 路線。
---

# Brother 印表機修復流程

## 適用情境

- 使用者說 Brother 印表機無法連線、無法列印、突然離線
- 使用者已經多次遇過同類問題，要走既有流程，不接受即興排查
- 裝置在 Windows 11，印表機是 Brother DCP-T820DW 系列，走網路埠列印
- 代理想先用 `lpstat`、CUPS、IPP、USB driver 亂試時

## 核心規則

1. **先讀既有文檔**：`/home/duofilm/.claude/projects/-home-duofilm-dotfiles/memory/brother-printer.md`
2. **預設根因是 Windows Print Spooler**，不是 WSL、不是 CUPS
3. **優先用 Windows PowerShell**：`Get-Service`、`Get-Printer`、`Get-PrinterPort`、`Get-WinEvent`
4. **如果 WSL 內 `powershell.exe` 失敗**，不要改走 Linux 列印系統；改成沙箱外或提權執行 Windows 指令
5. **遇到管理員權限需求時直接提權**，不要卡在「WSL 沒權限所以做不到」

## 已知故障模式

這台環境反覆出現的是：

- `Print Spooler` 自己停掉
- Windows Update 更新 `prnms003.inf` 後，Brother 驅動相容性出錯
- PrintService/Admin 事件常見：
  - `318`：`PrintConfig.dll` 升級失敗
  - `372`：Win32 Error `14007`
  - `372`：Win32 Error `2`
- 歷史上曾同時出現：
  - `Brother DCP-T820DW`
  - `Brother DCP-T820DW Printer`

看到這些訊號時，直接沿用下面流程，不要重新探索。

## 一鍵修復（快速路徑）

如果使用者只想趕快印東西，不關心過程：

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(wslpath -w ~/dotfiles/windows/brother-printer/repair.ps1)"
```

會跳 UAC 視窗，按「是」即可。腳本會 idempotent 跑完：自動重啟設定 → 啟動 Spooler → 移除重複印表機 → 跑 healthcheck 驗證。

桌面有 `Brother Printer Repair.lnk` 捷徑可直接雙擊。新機器或捷徑不見了，跑：

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(wslpath -w ~/dotfiles/windows/brother-printer/install-shortcut.ps1)"
```

不通過或要排查根因時，再走下面的固定流程。

## 自動驗證（regression check）

修完後或 commit 前驗證：

```bash
bats ~/dotfiles/windows/brother-printer/tests/brother_printer.bats
```

對應 `windows/brother-printer/healthcheck.ps1`，預設只檢查 regression 項目（自動重啟設定 + 無重複印表機），加 `-Full` 旗標可額外檢查當下健康（Spooler 在跑、印表機 Normal、IP 可達）。

## 固定流程

### 第一步：讀既有文檔

先開：

```bash
sed -n '1,260p' /home/duofilm/.claude/projects/-home-duofilm-dotfiles/memory/brother-printer.md
```

如果文檔內容和使用者當前環境一致，就照文檔走，不要換策略。

### 第二步：查 Spooler

```bash
powershell.exe -Command "Get-Service -Name Spooler | Format-List Name,Status,StartType"
```

判斷：

- `Running`：繼續查印表機和事件日誌
- `Stopped`：先啟動它

### 第三步：查印表機與埠

```bash
powershell.exe -Command "Get-Printer | Format-List Name,DriverName,PortName,PrinterStatus"
powershell.exe -Command "Get-PrinterPort | Format-List Name,Description,PrinterHostAddress"
```

重點看：

- 是否只有一台有效的 Brother 印表機
- `PortName` 是否為正確網路埠，例如 `IP_192.168.88.81`
- 是否又冒出重複項目 `Brother DCP-T820DW Printer`

### 第四步：查事件日誌

```bash
powershell.exe -Command "Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-PrintService/Admin'; Level=2,3} -MaxEvents 10 | Format-List TimeCreated,Id,Message"
```

如果看到 `318` / `372`，視為已知 Brother/Spooler 問題，不要轉去查 CUPS。

### 第五步：修復 Spooler

先嘗試一般啟動：

```bash
powershell.exe -Command "Start-Service -Name Spooler; Get-Service -Name Spooler | Format-List Name,Status,StartType"
```

若需要管理員權限，直接用提權 PowerShell：

```bash
powershell.exe -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-Command','Start-Service -Name Spooler; sc.exe failure Spooler reset= 86400 actions= restart/60000/restart/60000/restart/60000'"
```

這一步包含兩件事：

- 啟動 `Spooler`
- 設定故障後 60 秒自動重啟三次

驗證：

```bash
powershell.exe -Command "Get-Service -Name Spooler | Format-List Name,Status,StartType"
powershell.exe -Command "sc.exe qfailure Spooler"
```

### 第六步：如果還是不行

如果 `Spooler` 起來後仍無法列印，再處理重複印表機項目：

```powershell
Remove-Printer -Name "Brother DCP-T820DW Printer"
```

這一步只在確認真的存在重複項目時才做。

如果文檔也明示要重裝 Brother 驅動，再讓使用者走 Brother 官方最新版，不要自己換 generic Linux driver。

## 裝置可達性驗證

`Spooler` 修好後，才驗證印表機本體：

```bash
ping -c 2 -W 2 192.168.88.81
curl -I --max-time 5 http://192.168.88.81/
```

如果印表機 IP 可達、HTTP 有回應、`Get-Printer` 顯示 `Normal`，就算修復完成。

## 禁止事項

- 不要先跑 `lpstat -t`
- 不要先推論是 WSL CUPS 壞掉
- 不要先研究 USB 驅動
- 不要在已有文檔時重新設計排查樹
- 不要因為 WSL 裡 `powershell.exe` 出錯，就放棄 Windows 端修復

## 成功條件

以下條件同時成立才算修好：

- `Spooler` 是 `Running`
- `sc.exe qfailure Spooler` 顯示自動重啟已設定
- `Get-Printer` 顯示 Brother 印表機狀態 `Normal`
- 印表機 IP 可 ping
- 使用者確認已成功印出
