# Chrome CPU Usage Widget

用 Chrome 原生 `Document Picture-in-Picture` 顯示可拖動的小視窗。

## 特點

- 畫面更小、更精簡
- 浮動小窗可直接拖動
- 介面由 Chrome 原生小窗提供，不用 Electron
- PowerShell 只負責在本機提供 CPU / RAM / Down / Up 資料

## Run

直接雙擊：

```bat
run-widget.bat
```

或 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\stats-server.ps1
```

之後 Chrome 會打開本機頁面：

1. 按 `Open compact widget`
2. 會跳出小型浮動視窗
3. 之後可直接拖動該小窗

## Chrome 需求

- 建議使用最新版 Chrome
- 需要支援 `Document Picture-in-Picture`

如果按鈕顯示不可用，代表目前 Chrome 版本或設定不支援。
