---
name: rpi-ssh-setup
description: >
  RPi SSH 連線設定。重灌 RPi OS 後恢復 SSH 存取的完整流程，
  包含 Windows/WSL 雙 key 授權、host key 清理、sudo 免密碼設定。
  適用場景：RPi 重灌、SSH 連不上、Ansible Permission denied。
---

# RPi SSH 設定

## 坑：Windows 與 WSL 是兩把不同的 SSH Key

```
C:\Users\duofilm\.ssh\id_ed25519     ← Windows 用的 key
/home/duofilm/.ssh/id_ed25519        ← WSL 用的 key（不同！）
```

即使 username 相同（`duofilm`），Windows 和 WSL 的 SSH key pair **完全不同**。
Ansible 從 WSL 執行，所以 RPi 必須授權 **WSL 的 key**，不能只授權 Windows 的。

### 症狀

- PowerShell `ssh duofilm@rpi` 成功
- WSL `ssh duofilm@rpi` 失敗 `Permission denied (publickey,password)`
- Ansible `Permission denied`

### 確認方式

```bash
# 比較兩邊 fingerprint — 不同就是兩把 key
ssh-keygen -lf ~/.ssh/id_ed25519                                          # WSL
powershell.exe -Command "ssh-keygen -lf C:\Users\duofilm\.ssh\id_ed25519" # Windows
```

### 修復

兩邊的 public key 都要加到 RPi 的 `~/.ssh/authorized_keys`：

```bash
# 從 WSL（需要密碼或透過 Windows SSH 代貼）
ssh-copy-id -i ~/.ssh/id_ed25519.pub duofilm@192.168.88.10

# Windows 沒有 ssh-copy-id，用 type + pipe
# 在 PowerShell 執行：
type C:\Users\duofilm\.ssh\id_ed25519.pub | ssh duofilm@192.168.88.10 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

## 坑：重灌後 Host Key 變更

重灌 RPi OS 後 SSH host key 會變，兩邊都要清：

```bash
# WSL
ssh-keygen -R 192.168.88.10

# Windows（PowerShell）
ssh-keygen -R 192.168.88.10 -f C:\Users\duofilm\.ssh\known_hosts
```

## 坑：Raspberry Pi OS Lite 預設不開 SSH

最小安裝（Lite）SSH 預設關閉。啟用方式：

1. **Raspberry Pi Imager**（推薦）— 燒錄時在 OS Customisation 勾選 Enable SSH
2. **SD 卡手動** — boot 分區根目錄建空檔案 `ssh`（無副檔名）
3. **接螢幕鍵盤** — `sudo systemctl enable --now ssh`

## Ansible 連線需求

Ansible 從 WSL 執行，需要：

1. WSL SSH key 已授權（加到 RPi `authorized_keys`）
2. RPi 用戶有 sudo 權限（Raspberry Pi OS 預設 duofilm 有 sudo）
3. `ansible.cfg` 設定 `become = True`（用 sudo 提權）
4. `inventory/hosts.yml` 的 `ansible_user` 與 RPi 用戶名一致
