# Technical Spec

## Goal

建立一個 Win11 原生桌面小工具，用來即時查看：

- CPU 使用率
- RAM 使用率與已用容量
- 網路下載速度
- 網路上傳速度
- 下載 / 上傳占合約頻寬百分比

此工具需支援標準 Windows 視窗框、右鍵操作、設定檔復用、位置與大小記憶、釘選狀態保存。

## Tech Stack

- Language: `C#`
- UI Framework: `WPF`
- Runtime: `.NET 8`
- OS Target: `Windows 11`

## Project Layout

- [CpuUsageWidget.Wpf.csproj](/home/duofilm/dotfiles/windows/cpu-usage-widget-wpf/CpuUsageWidget.Wpf.csproj)
- [App.xaml](/home/duofilm/dotfiles/windows/cpu-usage-widget-wpf/App.xaml)
- [App.xaml.cs](/home/duofilm/dotfiles/windows/cpu-usage-widget-wpf/App.xaml.cs)
- [MainWindow.xaml](/home/duofilm/dotfiles/windows/cpu-usage-widget-wpf/MainWindow.xaml)
- [MainWindow.xaml.cs](/home/duofilm/dotfiles/windows/cpu-usage-widget-wpf/MainWindow.xaml.cs)
- [settings.txt](/home/duofilm/dotfiles/windows/cpu-usage-widget-wpf/settings.txt)

## Functional Requirements

### Window Behavior

- 啟動後顯示為標準 Windows 視窗框。
- 視窗需顯示標準控制按鈕：最小化、最大化、關閉。
- 預設位置在主螢幕工作區右下角，需避開 taskbar。
- 視窗預設顯示於 taskbar。
- 視窗支援一般 Windows 拖動與縮放。
- 視窗支援 `TopMost` 置頂。
- 當 `pinned=true` 時，需維持 `Topmost=true`。
- 視窗變小時，版面需自動切成更精簡的顯示模式。

### Displayed Data

- `CPU`: 顯示整體 CPU 使用率，格式如 ` 23%`
- `RAM`: 顯示使用百分比與已用 / 總量，格式如 ` 38% (12.1/32.0 GB)`
- `DOWN`: 顯示即時下載速度與占合約頻寬百分比，格式如 `8.4 MB/s (13%)`
- `UP`: 顯示即時上傳速度與占合約頻寬百分比，格式如 `0.6 MB/s (1%)`
- Header 下方顯示方案資訊，格式如 `Plan 500/500 Mbps`

### Context Menu

右鍵選單至少包含：

- `Pin to top` / `Unpin from top`
- `Lock position` / `Unlock position`
- `Exit`

### Persistence

以下狀態需寫入 `settings.txt`：

- `download_mbps`
- `upload_mbps`
- `pinned`
- `locked`
- `pos_x`
- `pos_y`
- `window_width`
- `window_height`

工具重新啟動後需恢復：

- 視窗位置
- 視窗大小
- 釘選狀態
- 鎖定狀態
- 頻寬設定

## Non-Functional Requirements

- 啟動時間應短，適合常駐使用。
- 更新週期為 `1 秒`。
- 無需額外安裝 Python、Node.js 或 Electron。
- 即使某次取樣失敗，程式也不應崩潰；畫面可暫時顯示 `ERR`。
- 設定檔應維持文字格式，方便手動修改與復用。

## Data Sources

### CPU

- Source: `.NET PerformanceCounter`
- Counter: `Processor`, `% Processor Time`, `_Total`

### RAM

- Source: `Microsoft.VisualBasic.Devices.ComputerInfo`
- 欄位：
  - `TotalPhysicalMemory`
  - `AvailablePhysicalMemory`

計算方式：

- `used = total - available`
- `usedPercent = used / total * 100`

### Network

- Source: `System.Net.NetworkInformation.NetworkInterface`
- 過濾條件：
  - `OperationalStatus == Up`
  - 排除 `Loopback`
  - 排除 `Tunnel`

計算方式：

- 每秒抓一次所有有效網卡的累積收發位元組
- 與上一筆快照做差
- 差值除以經過秒數，得到 `bytes/sec`

### Bandwidth Usage Percent

計算方式：

- `currentMbps = bytesPerSecond * 8 / 1024 / 1024`
- `usagePercent = currentMbps / configuredMbps * 100`

## Settings File Specification

檔案名稱：`settings.txt`

格式：

```txt
# Network plan limits for usage percentage
download_mbps=500
upload_mbps=500
pinned=true
locked=false
pos_x=-1
pos_y=-1
window_width=270
window_height=176
```

規則：

- `#` 開頭視為註解
- 空白行忽略
- `key=value` 格式
- 不合法值忽略，退回預設值

欄位定義：

- `download_mbps`: 下載合約頻寬，`double`，必須大於 `0`
- `upload_mbps`: 上傳合約頻寬，`double`，必須大於 `0`
- `pinned`: 是否置頂，`true/false`
- `locked`: 是否鎖定位置，`true/false`
- `pos_x`: 視窗左上角 X 座標，`int`
- `pos_y`: 視窗左上角 Y 座標，`int`
- `window_width`: 視窗寬度，`int`
- `window_height`: 視窗高度，`int`

特殊值：

- `pos_x=-1` 且 `pos_y=-1` 表示使用預設右下角位置

## UI Specification

### Visual Direction

- 深色面板
- 標準 Windows 視窗框
- 可縮放桌面工具視窗
- 小尺寸時自動切換精簡排版

### Typography

- Header: `Segoe UI Semibold`
- Metrics: `Consolas`

### Colors

- Background: 深灰透明
- CPU label: 橘色
- RAM label: 綠色
- DOWN label: 淺藍色
- UP label: 粉色
- Value text: 淺灰白

## Runtime Flow

1. 程式啟動
2. 讀取 `settings.txt`
3. 建立主視窗並套用位置與大小
4. 套用 pinned 狀態
5. 建立右鍵選單
6. 初始化 CPU counter 與第一筆 network snapshot
7. 啟動 1 秒 timer
8. 每秒刷新 CPU / RAM / Network
9. 使用者縮放、移動、Pin/Unpin、Lock/Unlock 時即時寫回設定檔
10. 視窗關閉時再次保存狀態

## Error Handling

- 若 `settings.txt` 不存在，使用預設值建立執行狀態。
- 若某欄位解析失敗，只忽略該欄位，不中止程式。
- 若效能計數器或網路資料抓取失敗，該輪顯示 `ERR`，下輪繼續重試。

## Build And Publish

開發編譯：

```powershell
dotnet build
```

發佈：

```powershell
dotnet publish -c Release -r win-x64 --self-contained false
```

如果要單檔發佈，可再評估：

```powershell
dotnet publish -c Release -r win-x64 -p:PublishSingleFile=true --self-contained true
```

## Windows Validation Checklist

必測項目：

- 一般啟動後是否出現在右下角
- 是否顯示標準 Windows 標題列與 `- □ X`
- 手動調整大小後重開是否記住尺寸
- 拖曳後重開是否記住位置
- `Pin to top` 切換後是否正確置頂
- 視窗縮小後是否切成精簡模式
- Chrome 最大化時是否仍維持預期層級
- 多螢幕環境下是否仍在合理可見範圍
- Windows DPI 125% / 150% 下排版是否正常
- 修改 `settings.txt` 後重開是否生效
- 網路上下傳速度是否與工作管理員量級接近

## Known Risks

- `PerformanceCounter` 在少數 Windows 環境可能需要重新初始化計數器。
- `TopMost` 在某些全螢幕應用情境下不保證壓過所有視窗。
- `SystemParameters.WorkArea` 目前以主螢幕為基準，若之後要更完整支援多螢幕，需改成依實際螢幕決定停靠位置。
- `NetworkInterface` 的統計會合併所有符合條件的介面；若使用者同時有多張有效網卡，顯示的是總量。

## Recommended Next Steps

- 在 Windows 11 安裝 `.NET 8 SDK`
- 實際編譯並執行 WPF 專案
- 驗證縮放、重開後尺寸恢復、多螢幕行為
