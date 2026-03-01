---
name: deploy-guard
description: >
  RPi5B 部署安全防護。當修改 rpi5b/ 目錄下的檔案時適用，
  確保改動有部署到 RPi5B 才會生效。
  適用場景：改了 Docker 設定、系統設定等但忘記部署。
---

# 部署防護：修改 rpi5b/ 必須部署

## 問題

修改 `rpi5b/` 的檔案只改了本地 git repo，RPi5B 上的服務不會自動更新。
忘記部署 = 改了等於沒改。

## 規則

1. 修改 `rpi5b/` 下任何檔案後，**必須跑 Ansible 部署**
2. 部署前**必須先 commit + push**

## 部署指令

```bash
# 只改系統設定（boot, journald, log2ram）
ansible-playbook rpi5b.yml --tags system

# 不確定影響範圍 → 跑全部
ansible-playbook rpi5b.yml
```

## 自動檢測機制

### Stop Hook

`scripts/check-rpi5b-deploy.sh` 在每次 Claude Code 回應結束時執行：
- 檢查 `rpi5b/` 有無 uncommitted / staged 改動
- 比對 deploy marker，檢查已 commit 但未部署的改動

### Deploy Marker

- 路徑：`~/.cache/rpi5b-last-deploy`
- 內容：最後一次成功部署時的 commit hash
- 寫入時機：`ansible/rpi5b.yml` post_tasks（`always` tag）
