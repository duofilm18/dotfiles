#!/bin/bash
# lib/pidfile.sh - 進程組管理共用函式庫
#
# 背景常駐腳本的 PID file 管理。殺舊進程組 → 寫 PID → trap 清理。
# 詳見 background-script.md。
#
# 用法:
#   source "$SCRIPT_DIR/lib/pidfile.sh"
#   pidfile_acquire "/tmp/my-script.pid"

# ── 取得 PID file（殺舊進程組 + 設 cleanup trap）──
pidfile_acquire() {
    local pidfile="$1"
    if [ -f "$pidfile" ]; then
        local old_pid
        old_pid="$(cat "$pidfile")"
        if [ "$$" != "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            kill -- -"$old_pid" 2>/dev/null   # 殺整個舊進程組
            sleep 0.2
        fi
    fi
    echo $$ > "$pidfile"

    # 確保退出時清理所有子進程
    trap "rm -f '$pidfile'; kill 0 2>/dev/null" EXIT
}
