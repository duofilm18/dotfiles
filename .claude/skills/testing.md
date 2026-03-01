---
name: testing
description: >
  全 repo 測試慣例：Bats 測試框架。當需要新增或修改測試時使用。
---

# Testing（Bats）

## 結構

```
tests/
├── test_helper.bash       # 共用 setup/teardown/fire/assert
├── state_machine.bats     # 狀態轉換 + 智慧抑制
├── dedup.bats             # 2 秒去重
├── dispatch.bats          # PROJECT 計算
├── deploy_integrity.bats  # 部署完整性靜態檢查
└── ...
```

## 執行

```bash
bats tests/                # 全跑
bats tests/dispatch.bats   # 單檔
bats tests/ --filter "T1"  # 過濾
```

## 新增測試步驟

1. 建立 `tests/<name>.bats`
2. `setup()` 內 `load test_helper; common_setup`
3. `teardown()` 內 `common_teardown`
4. 用 `@test "描述" { ... }` 撰寫測試
5. 每個 `@test` 獨立隔離，不依賴其他 test 的狀態

# TDD 工作流

修 bug 或加功能時，優先採用 RED → GREEN → REFACTOR 循環：

1. **RED** — 先寫測試重現問題（測試應 FAIL）
2. **GREEN** — 最小改動讓測試通過
3. **REFACTOR**（可選）— 通過後再整理
