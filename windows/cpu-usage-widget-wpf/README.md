# CpuUsageWidget.Wpf

Windows 11 的唯一保留版本，使用 `C# + WPF`。

## Run

在此資料夾執行：

```powershell
dotnet run
```

或發佈後執行 `CpuUsageWidget.Wpf.exe`。

## Build

```powershell
dotnet publish -c Release -r win-x64 --self-contained false
```

## Behavior

- 標準 Windows 視窗框，含 `- □ X`
- 可拖動、可縮放
- 視窗變小時自動切成更精簡版面
- 自動記住位置、大小、置頂與鎖定狀態

## Settings

`settings.txt` 會一起複製到輸出目錄：

```txt
download_mbps=500
upload_mbps=500
pinned=true
locked=false
pos_x=-1
pos_y=-1
window_width=270
window_height=176
```
