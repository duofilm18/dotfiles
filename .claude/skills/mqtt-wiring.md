---
name: mqtt-wiring
description: >
  MQTT topic 接線契約與登記表。當新增/修改 MQTT topic 的 Publisher 或
  Consumer 時必須查閱，確認兩端都存在且 payload 格式一致。
---

# MQTT 接線契約

## 設計原則

- 每條 topic **必須有明確的 Publisher 和 Consumer**，缺任一端 → 孤兒
- 修改 payload 格式 → 必須同步更新所有 Consumer
- 新增/移除 topic → 必須更新本登記表

## Topic 登記表

| Topic | Publisher | Consumer | Payload | Retained |
|-------|----------|----------|---------|----------|
| `system/stats` | `push-temp.sh` (cron) | Uptime Kuma | `{temp, ram}` | Yes |

## Broker 拓撲

| Broker | Host | 用途 |
|--------|------|------|
| RPi5B | `192.168.88.10:1883` | 系統監控 |

## 歷史教訓

- **mqtt-ntfy 孤兒事件**：`notify.sh` 發 `claude/notify` → 重構後 dispatch.sh 接手但漏接 ntfy → 手機通知斷線數週無人發現。根因：沒有接線登記表，Publisher 被移除時無法檢查 Consumer 是否還存在。
- **解法**：通知改為 dispatch.sh 直接 curl ntfy.sh 雲端，不再經 MQTT。

## 修改前必做

1. 查本登記表，確認 Publisher / Consumer 兩端都存在
2. 修改 payload 格式 → grep 所有 Consumer 確認相容
3. 移除 topic → 確認無殘留 Consumer（否則變孤兒）
4. 完成後更新本表
