# System Usage Widget

Windows 11 右下角小工具，顯示：

- CPU 使用率
- RAM 使用率與已用容量
- 網路下載速度
- 網路上傳速度
- 網路速度占合約頻寬百分比

## Run

在 Windows PowerShell 執行：

```powershell
powershell -ExecutionPolicy Bypass -File .\system-usage-widget.ps1
```

或直接雙擊 `run-widget.bat`。

第一次啟動後，程式會自動建立 Windows `Startup` 捷徑，之後開機會自動執行。

## Settings

可編輯同資料夾的 `settings.txt`：

```txt
download_mbps=500
upload_mbps=500
```

之後如果你換方案，只要改這個文字檔。

## Right Click Menu

主視窗右鍵：

- `Hide to tray`
- `Enable startup` / `Disable startup`
- `Open widget folder`
- `Exit`

通知區圖示右鍵：

- `Show widget`
- `Enable startup` / `Disable startup`
- `Open widget folder`
- `Exit`

## Behavior

- 視窗固定在右下角。
- 一般狀況下會維持在前景，避免被一般 Chrome 視窗蓋掉。
- 縮到通知區後，滑鼠移到圖示上仍可看到即時狀態摘要。
- 雙擊通知區圖示可叫回 widget。
- 不需要安裝 Python。

## Remove

如果你之後不想用了：

1. 在 widget 或通知區圖示右鍵選 `Disable startup`
2. 右鍵選 `Open widget folder`
3. 刪除整個資料夾即可

開機自啟使用的是 Windows `Startup` 捷徑，不是服務，也不是排程器。
