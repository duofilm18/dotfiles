---
name: background-script
description: >
  背景常駐腳本的進程管理規範。當撰寫或修改需要長期執行的常駐背景腳本時使用。
  適用場景：狀態監控、訂閱者等需要長期執行且可能被重複啟動的腳本。
---

# 背景常駐腳本：進程組管理

## 問題

tmux reload 會重新執行 `run-shell -b`，但不殺舊腳本。
只用 PID file 檢查會導致子進程變孤兒，多組進程互打。

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

# ── 主迴圈 ──
while true; do
    # ...
    sleep 1
done
```

## 規則

| 規則 | 做法 | 原因 |
|------|------|------|
| 殺舊進程組 | `kill -- -"$OLD_PID"` | 連同子進程一起清掉 |
| 退出清理 | `trap 'kill 0' EXIT` | 不管怎麼退出都清理 |
| Last-writer-wins | 新實例主動殺舊的 | 永遠只有一組進程在跑 |
