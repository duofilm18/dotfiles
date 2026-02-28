---
name: deploy-integrity
description: >
  部署完整性免疫系統。三層防護確保 Ansible 管理的服務不會「寫了沒部署」。
  適用場景：新增/修改 Ansible role、systemd service、deploy script。
---

# 部署完整性免疫系統

## 三層防護架構

| 層 | 機制 | 時機 | 擋住什麼 |
|----|------|------|----------|
| **Pre-commit** | `bats tests/deploy_integrity.bats` | 每次 commit | 部署成品不完整（缺 template、缺 handler） |
| **Stop hook** | `scripts/check-deploy.sh` | Claude 回應結束 | 改了沒部署（commit 後沒跑 playbook） |
| **Deploy marker** | `~/.cache/{wsl,rpi5b}-last-deploy` | playbook post_tasks | 提供 Stop hook 比對基準 |

## 新增服務 Checklist（加抗體）

新增一個 Ansible 管理的 systemd service 時，必須同時加對應的 DI-* 測試：

1. **腳本存在** — `[ -f "$DOTFILES/scripts/xxx.sh" ]`
2. **Template 存在** — `[ -f "$DOTFILES/ansible/roles/xxx/templates/xxx.service.j2" ]`
3. **Task 引用 template** — `grep -q 'xxx.service' .../tasks/main.yml`
4. **Handler 存在** — `grep -q 'Restart xxx' .../handlers/main.yml`

DI-9 會自動檢查所有 `.service.j2` 都有對應 handler，但前 4 項是人工確認腳本⟷Ansible 的完整鏈路。

## Deploy Marker 機制

```
ansible-playbook wsl.yml / rpi5b.yml
  ↓
post_tasks: git rev-parse HEAD > ~/.cache/{target}-last-deploy
  ↓
Stop hook: git log {marker}..HEAD | grep pattern
  ↓
有改動 → 警告 + 顯示部署指令
```

### Marker 檔案

| Target | Marker 路徑 | 寫入者 |
|--------|------------|--------|
| WSL | `~/.cache/wsl-last-deploy` | `ansible/wsl.yml` post_tasks |
| RPi5B | `~/.cache/rpi5b-last-deploy` | `ansible/rpi5b.yml` post_tasks |

### check-deploy.sh Pattern

| Target | Git diff pattern | 部署指令 |
|--------|-----------------|----------|
| RPi5B | `^(rpi5b/\|ansible/roles/rpi_)` | `ansible-playbook rpi5b.yml --tags mqtt` |
| WSL | `^(ansible/roles/(wsl\|common)/\|shared/)` | `ansible-playbook wsl.yml` |

## 反模式

| 反模式 | 正確做法 |
|--------|----------|
| 加了 service template 沒加 handler | template + handler + DI test 一起加 |
| 跑 playbook 但 post_tasks 沒寫 marker | 確認 playbook 有 `tags: [always]` 的 marker task |
| 只改 scripts/ 的腳本沒跑 Ansible | WSL 的 systemd service 要靠 Ansible 重啟 |
| 新增 target 忘記加 check-deploy.sh | 在 `check-deploy.sh` 加一行 `check_target` |
