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
| `DEPLOY_LHM_DIR` | `%LOCALAPPDATA%\LibreHardwareMonitor` | 硬體監控 |

## 新增路徑的流程

1. 在 `deploy-paths.ps1` 和 `deploy-paths.sh` 同時加新變數
2. 腳本中 `source` 或 `. ` 引用，使用變數
3. 更新本 skill 的路徑表格

## 歷史教訓

- 路徑散落在各腳本，沒有單一來源 → 部署不同步。現在統一到登記表。
