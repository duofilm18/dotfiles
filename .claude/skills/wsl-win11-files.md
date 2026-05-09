---
name: wsl-win11-files
description: >
  WSL 讀取 Windows / Win11 檔案契約。當使用者提供 `C:\...` 路徑、OneDrive 路徑、
  或說明原始檔案在 Windows 時，必須先轉成 `/mnt/c/...` 進行查找，不可先假設 WSL 看不到。
---

# WSL 讀取 Win11 檔案

## 核心規則

> 使用者給 Windows 路徑時，先嘗試對應到 `/mnt/c/...`，不要先說看不到。

## 基本映射

- `C:\Users\duofilm\...` -> `/mnt/c/Users/duofilm/...`
- OneDrive 路徑在 WSL 通常仍可直接從 `/mnt/c/Users/.../OneDrive - .../` 讀取

## 必做順序

1. 若使用者貼 `C:\...` 路徑，先手動轉成 `/mnt/c/...`
2. 用 `test -f` 或 `ls` 驗證檔案是否存在
3. 若是原始資料檔，優先讀原始檔，不先猜衍生物
4. 若需要長期使用，再複製進專案內作為正式 source

## 何時用

- `zipcode.xlsx`
- OneDrive 原始資料
- Windows only export
- 使用者說「WSL 應該看得到 Windows 檔案」

## 反模式

不要這樣做：
- 看到 `C:\...` 就直接回覆看不到
- 跳過原始檔直接只看 YAML / CSV / 匯出產物
- 把 Windows 路徑當成純文字備註而不驗證
