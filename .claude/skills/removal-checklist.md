---
name: removal-checklist
description: >
  移除元件/功能時的掃描清單。當砍掉腳本、服務、hook、MQTT publisher/consumer
  或任何跨檔案元件時觸發，防止殘留引用變成孤兒。
---

# Removal Checklist

移除元件時，對元件名稱（腳本名、service 名、函式名）逐項掃描，確認無殘留。

## 掃描清單

| # | 檢查項目 | 位置 | 動作 |
|---|---------|------|------|
| 1 | **Hooks 引用** | `~/.claude/settings.json`、`scripts/claude-dispatch.sh`、`scripts/setup-claude-hooks.sh` | 移除對應 event/handler |
| 2 | **MQTT 接線** | `.claude/skills/mqtt-wiring.md` 登記表 | 移除 topic 行，確認對向 pub/sub 也一併處理 |
| 3 | **Ansible 引用** | `ansible/roles/`、`ansible/*.yml` | 移除 role/task/handler/template，含 `.service.j2` |
| 4 | **部署完整性測試** | `tests/deploy_integrity.bats` | 移除對應 DI-* test case |
| 5 | **其他測試** | `tests/` | 移除或更新相關 `.bats` 檔 |
| 6 | **Scripts 引用** | `scripts/`、`scripts/lib/` | 移除 source / 呼叫 / pidfile 註冊 |
| 7 | **文件** | `README.md`、`CLAUDE.md`、`.claude/skills/` | 移除提及與 skill 連結 |
| 8 | **全 repo grep 兜底** | `grep -r "<元件名>" --include='*.sh' --include='*.yml' --include='*.md' --include='*.json'` | 清除所有殘留引用 |

## 執行原則

- **先 grep 再砍** — 刪檔案之前先搜引用，不要刪完才發現斷鏈
- **pub/sub 成對處理** — 砍 publisher 必須同時處理 consumer，反之亦然
- **一次 commit** — 元件移除與殘留清理放同一個 commit，避免中間態
