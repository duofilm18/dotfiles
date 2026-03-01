---
name: shared-contract
description: >
  跨腳本共用契約規範。當新建腳本需要用到已存在腳本的 payload 格式、設定載入、
  常數時使用。防止跨元件介面漂移。
  觸發場景：新建 publisher/consumer、修改 payload 格式、新增共用常數。
---

# 跨腳本共用契約

## 問題

多個腳本各自拼裝相同格式（payload、config、路徑常數），
沒有共用來源 → 其中一端改了另一端沒跟 → 介面漂移 → 執行期才爆。

## 規則

| 規則 | 做法 | 違反症狀 |
|------|------|----------|
| 宣告一次 | 共用邏輯放 `scripts/lib/*.sh`，用 `source` 引入 | payload 格式漂移 |
| 禁止複製 | 腳本不可自行定義 lib 已有的函式或常數 | guard test 爆掉 |
| guard test 當編譯器 | 靜態測試確保所有使用者都 source lib、不自行定義 | 新人複製貼上不會被擋 |

## 現有共用 lib

| 檔案 | 提供 | 使用者 |
|------|------|--------|
| `scripts/lib/pidfile.sh` | `pidfile_acquire()` | 背景常駐腳本 |

## 新建腳本的 checklist

1. 列出需要的 payload 格式 / config / 常數
2. 檢查 `scripts/lib/` 是否已有 → 有就 `source`，沒有就先建 lib 再建腳本
3. **禁止先複製再重構** — 一開始就用 lib

## 反模式

| 反模式 | 後果 | 正確做法 |
|--------|------|----------|
| 每個腳本各寫相同邏輯 | 格式漂移，改一邊忘另一邊 | 抽到 lib，用 source 引入 |
| 先複製再說、之後再重構 | 多燒一輪 token + 多一個 commit | 一開始就建 lib |
