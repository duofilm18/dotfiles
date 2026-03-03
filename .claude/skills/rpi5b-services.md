---
name: rpi5b-services
description: >
  RPi5B 上所有服務的外部介面與 API 約束。當新增/修改 RPi5B 服務、
  手機推播/ntfy 收不到通知、連接 Uptime Kuma / Mosquitto API、
  或處理 paho-mqtt 版本問題時使用。
---

# RPi5B 服務介面

## 服務清單

| 服務 | 類型 | Port | 管理方式 |
|------|------|------|----------|
| mosquitto | systemd | 1883 | apt 安裝，systemd 管理 |
| mqtt-led | systemd | — | Ansible `rpi_mqtt_services` role |
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

## paho-mqtt 版本

RPi5B 上 apt 裝的是 paho-mqtt **1.x**（`import paho.mqtt.client as mqtt; mqtt.Client()`）。

- mqtt-led 使用 1.x API
- **不要升級到 2.x**（API 不相容：`Client()` 建構式改為必傳 `CallbackAPIVersion`）
- `requirements.txt` 用 `paho-mqtt<2` 鎖版本

## Ansible 部署

```bash
cd ~/dotfiles/ansible
ansible-playbook rpi5b.yml --tags mqtt       # mqtt-led
ansible-playbook rpi5b.yml --tags docker     # Pi-hole / ntfy / Uptime Kuma
```

## 注意事項

- RPi5B 電源鍵很敏感，意外按到會關機 → Uptime Kuma 離線告警
- Docker 只跑在 RPi5B，WSL 不跑 Docker
- mosquitto 設定檔在 `/etc/mosquitto/mosquitto.conf`，允許匿名連線
