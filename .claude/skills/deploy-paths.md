---
name: deploy-paths
description: >
  Windows 部署路徑契約。當建立或修改任何涉及 Windows 路徑的腳本（.ps1, .sh, package.json）、
  或新增 Windows 端部署目標時，必須使用此 skill 確認路徑來源。
  防止「多個腳本寫不同路徑」導致部署不同步的問題。
---

# Windows 部署路徑契約

## 唯一規則

> **所有 Windows 部署路徑必須來自路徑登記表，禁止硬寫。**

| 登記表 | 用途 |
|--------|------|
| `windows/deploy-paths.ps1` | PowerShell 腳本引用（`. "$PSScriptRoot\deploy-paths.ps1"`） |
| `windows/deploy-paths.sh` | WSL 腳本引用（`source ~/dotfiles/windows/deploy-paths.sh`） |

兩個檔案定義相同路徑，格式不同。修改一個時必須同步另一個。

## 目前登記的路徑

| 變數 | Windows 路徑 | 用途 |
|------|-------------|------|
| `DEPLOY_IME_DIR` | `%LOCALAPPDATA%\IME_Indicator` | IME 中英指示器 |
| `DEPLOY_LHM_DIR` | `%LOCALAPPDATA%\LibreHardwareMonitor` | 硬體監控 |
| `DEPLOY_SD_PLUGIN` | `%USERPROFILE%\com.duofilm.claude-monitor.sdPlugin` | Stream Deck plugin |

## 新增路徑的流程

1. 在 `deploy-paths.ps1` 和 `deploy-paths.sh` 同時加新變數
2. 腳本中 `source` 或 `. ` 引用，使用變數
3. 更新本 skill 的路徑表格
4. `git commit` 時 pre-commit hook 會自動驗證無硬寫路徑

## 歷史教訓

- `install.ps1` 裝到 `AppData\Local\`，`deploy-ime-indicator.sh` 部署到 `C:\Users\duofilm\` → 兩邊不同步，修了 A 沒修到 B
- 此問題反覆發生 4-5 次，每次都是「以為部署了，實際執行的是另一份」
- 根因：路徑散落在各腳本，沒有單一來源 → 現在統一到登記表
