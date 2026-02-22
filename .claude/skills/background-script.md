---
name: background-script
description: >
  背景常駐腳本的進程管理規範。當撰寫或修改由 tmux run-shell -b 或其他方式啟動的
  常駐背景腳本時使用。適用場景：MQTT 訂閱者、blink loop、狀態監控等需要長期執行
  且可能因 tmux reload 而重複啟動的腳本。
---

# 背景常駐腳本：進程組管理

## 問題

tmux reload 會重新執行 `run-shell -b`，但不殺舊腳本。
只用 PID file 檢查會導致子進程（`mosquitto_sub`、loop）變孤兒，多組進程互打。

## Pattern：進程組 Singleton

```bash
#!/bin/bash

# ── Singleton：殺舊進程組，接管 PID file ──
PIDFILE="/tmp/my-script.pid"
if [ -f "$PIDFILE" ]; then
    OLD_PID="$(cat "$PIDFILE")"
    if [ "$$" != "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill -- -"$OLD_PID" 2>/dev/null
        sleep 0.2
    fi
fi
echo $$ > "$PIDFILE"

# ── 退出清理 ──
trap 'rm -f "$PIDFILE"; kill 0 2>/dev/null' EXIT

# ── 背景子任務 ──
my_loop() {
    while true; do
        # ...
        tmux refresh-client -S 2>/dev/null   # 即時推送
        sleep 1
    done
}
my_loop &

# ── 主迴圈（前景，阻塞） ──
mosquitto_sub -h "$HOST" -t "topic" -v | while IFS= read -r line; do
    # ...
    tmux refresh-client -S 2>/dev/null       # 即時推送
done
```

## 規則

| 規則 | 做法 | 原因 |
|------|------|------|
| 殺舊進程組 | `kill -- -"$OLD_PID"` | 連同子進程一起清掉 |
| 退出清理 | `trap 'kill 0' EXIT` | 不管怎麼退出都清理 |
| 即時推送 | `tmux refresh-client -S` | 不等 `status-interval` 輪詢 |
| Last-writer-wins | 新實例主動殺舊的 | 永遠只有一組進程在跑 |

## 除錯

```bash
# 檢查重複進程
ps aux | grep -E 'tmux-mqtt|mosquitto_sub' | grep -v grep

# 手動清理
pkill -f tmux-mqtt-colors.sh
pkill -f 'mosquitto_sub.*claude'
rm -f /tmp/tmux-mqtt-colors.pid
```

## 參考實作

`scripts/tmux-mqtt-colors.sh`
