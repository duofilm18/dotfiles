---
name: deploy-guard
description: >
  RPi5B 部署安全防護。當修改 rpi5b/ 目錄下的檔案時適用，
  確保改動有部署到 RPi5B 才會生效。
  適用場景：改了 LED 效果、mqtt_led.py、系統設定等但忘記部署。
---

# 部署防護：修改 rpi5b/ 必須部署

## 問題

修改 `rpi5b/` 的檔案只改了本地 git repo，RPi5B 上的服務不會自動更新。
忘記部署 = 改了等於沒改，且 Ansible 不報錯（`changed=0` 看起來正常）。

## 規則

1. 修改 `rpi5b/` 下任何檔案後，**必須跑 Ansible 部署**
2. 部署前**必須先 commit + push**（Ansible 用 synchronize 同步，未 commit 的也會送，但 push 才是備份）

## 部署指令

```bash
# 只改 mqtt-led 相關（led-effects.json, mqtt_led.py, melodies.py）
ansible-playbook rpi5b.yml --tags mqtt

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
- 有問題就輸出警告，Claude Code 會看到並提醒用戶

### Deploy Marker

- 路徑：`~/.cache/rpi5b-last-deploy`
- 內容：最後一次成功部署時的 commit hash
- 寫入時機：`ansible/rpi5b.yml` post_tasks（`always` tag）
- 讀取時機：Stop hook 比對 marker 與 HEAD

### 流程圖

```
修改 rpi5b/ 檔案
  ↓
git commit + push
  ↓
ansible-playbook rpi5b.yml --tags mqtt
  ↓
pre_tasks: synchronize (always) → 同步到 RPi5B
  ↓
role: copy + restart service
  ↓
post_tasks: 寫 deploy marker ← Stop hook 讀這個判斷是否已部署
```

## 常見踩坑

| 操作 | 結果 | Hook 能擋？ |
|------|------|-------------|
| 改了 led-effects.json 沒跑 Ansible | RPi5B 用舊值 | **是** — 警告 undeployed |
| 跑了 `--tags mqtt` 但 sync 沒跑 | 舊檔覆蓋新檔 | 不會發生 — sync 已改 `always` tag |
| 新增檔案忘記加 Ansible copy loop | 檔案不會到 `/root/mqtt-led/` | **否** — 需人工檢查 |
