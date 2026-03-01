---
name: rpi5b-services
description: >
  RPi5B 上所有服務的外部介面與 API 約束。當新增/修改 RPi5B 服務、
  手機推播/ntfy 收不到通知、連接 Uptime Kuma / Mosquitto API 時使用。
---

# RPi5B 服務介面

## 服務清單

| 服務 | 類型 | Port | 管理方式 |
|------|------|------|----------|
| mosquitto | systemd | 1883 | apt 安裝，systemd 管理 |
| Pi-hole | Docker | 53, 80 | `rpi5b/docker/docker-compose.yml` |
| ntfy | Docker | 8080 | `rpi5b/docker/docker-compose.yml` |
| Uptime Kuma | Docker | 3001 | `rpi5b/docker/docker-compose.yml` |

## 通知鏈路

```
WSL dispatch.sh → curl ntfy.sh 雲端 → 手機推播
Uptime Kuma    → 內建 ntfy provider → ntfy (localhost:8080) → 手機推播
```

- Claude 完成通知**不經 MQTT**，由 dispatch.sh 直接 curl ntfy.sh 雲端
- Uptime Kuma 告警用內建 ntfy notification provider，指向本機 `http://localhost:8080`

## Ansible 部署

```bash
cd ~/dotfiles/ansible
ansible-playbook rpi5b.yml --tags docker     # Pi-hole / ntfy / Uptime Kuma
ansible-playbook rpi5b.yml                   # 全部
```

## 注意事項

- RPi5B 電源鍵很敏感，意外按到會關機 → Uptime Kuma 離線告警
- Docker 只跑在 RPi5B，WSL 不跑 Docker
- mosquitto 設定檔在 `/etc/mosquitto/mosquitto.conf`，允許匿名連線
