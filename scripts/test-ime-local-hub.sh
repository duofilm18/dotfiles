#!/bin/bash
# test-ime-local-hub.sh - IME 本機 MQTT HUB 測試
#
# 驗證 IME 資料流：IME_Indicator → localhost:1883 → tmux @ime_state
# TDD: 先寫測試 → 紅燈 → 改 code → 綠燈
#
# 測試分兩層：
#   靜態檢查（T1-T6）：驗證 code 設定正確
#   E2E 測試（T7-T8）：模擬 IME_Indicator publish，驗證 tmux 即時收到

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓ PASS${NC}: $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗ FAIL${NC}: $1"; ((FAIL++)); }

echo "=== IME 本機 MQTT HUB 測試 ==="
echo ""

# ────────────────────────────────────
# 靜態檢查
# ────────────────────────────────────
echo -e "${CYAN}── 靜態檢查 ──${NC}"

# ── T1: tmux-mqtt-colors.sh ime_loop 連 localhost ──
echo "[T1] tmux-mqtt-colors.sh: ime_loop 使用 localhost"
if grep -q 'mosquitto_sub -h "localhost".*-t "ime/state"' "$SCRIPT_DIR/tmux-mqtt-colors.sh"; then
    pass "ime_loop 連 localhost"
else
    fail "ime_loop 未連 localhost（仍使用 \$MQTT_HOST）"
fi

# ── T2: tmux-mqtt-colors.sh ime_loop 訂閱 ime/state 走 localhost（不走 $MQTT_HOST） ──
echo "[T2] tmux-mqtt-colors.sh: ime_loop 訂閱 ime/state 走 localhost"
IME_LOOP=$(sed -n '/^ime_loop()/,/^}/p' "$SCRIPT_DIR/tmux-mqtt-colors.sh")
if echo "$IME_LOOP" | grep 'mosquitto_sub' | grep -q '\$MQTT_HOST'; then
    fail "ime_loop 訂閱仍使用 \$MQTT_HOST（應走 localhost）"
else
    pass "ime_loop 訂閱走 localhost"
fi

# ── T2b: ime_loop 不含 mosquitto_pub（純 subscriber，不發 LED） ──
echo "[T2b] tmux-mqtt-colors.sh: ime_loop 無 mosquitto_pub"
IME_LOOP=$(sed -n '/^ime_loop()/,/^}/p' "$SCRIPT_DIR/tmux-mqtt-colors.sh")
if echo "$IME_LOOP" | grep -q 'mosquitto_pub'; then
    fail "ime_loop 仍含 mosquitto_pub（應只做 tmux bridge）"
else
    pass "ime_loop 無 mosquitto_pub（純 subscriber）"
fi

# ── T2c: 不使用 IME_INTERRUPT_FILE（改用 epoch 變數） ──
echo "[T2c] tmux-mqtt-colors.sh: 無 IME_INTERRUPT_FILE"
if grep -q 'IME_INTERRUPT_FILE' "$SCRIPT_DIR/tmux-mqtt-colors.sh"; then
    fail "仍使用 IME_INTERRUPT_FILE（應改用 epoch 變數）"
else
    pass "無 IME_INTERRUPT_FILE（epoch-based）"
fi

# ── T3: IME_Indicator config.py MQTT_BROKER 是 localhost ──
echo "[T3] IME_Indicator config.py: MQTT_BROKER = localhost"
CONFIG_FILE="$SCRIPT_DIR/../IME_Indicator/python_indicator/config.py"
if [ ! -f "$CONFIG_FILE" ]; then
    fail "config.py 不存在: $CONFIG_FILE"
else
    BROKER=$(grep '^MQTT_BROKER' "$CONFIG_FILE" | head -1)
    if echo "$BROKER" | grep -q '"localhost"'; then
        pass "MQTT_BROKER = \"localhost\""
    else
        fail "MQTT_BROKER 不是 localhost（目前: $BROKER）"
    fi
fi

# ── T4: IME_Indicator config.py 使用 ime/state topic ──
echo "[T4] IME_Indicator config.py: MQTT_IME_TOPIC = ime/state"
if [ -f "$CONFIG_FILE" ]; then
    if grep -q 'MQTT_IME_TOPIC.*"ime/state"' "$CONFIG_FILE"; then
        pass "MQTT_IME_TOPIC = \"ime/state\""
    else
        fail "MQTT_IME_TOPIC 不是 ime/state"
    fi
fi

# ── T5: mosquitto broker 在 localhost:1883 可達 ──
echo "[T5] mosquitto broker: localhost:1883 可達"
if mosquitto_pub -h localhost -p 1883 -t "test/ping" -m "pong" 2>/dev/null; then
    pass "localhost:1883 可達"
else
    fail "localhost:1883 不可達（mosquitto 未安裝或未啟動）"
fi

# ── T6: Claude state publishing 仍用 $MQTT_HOST（不動 RPi5B） ──
echo "[T6] tmux-mqtt-colors.sh: 主迴圈 claude/led 仍用 \$MQTT_HOST"
if grep -A1 'mosquitto_pub.*\$MQTT_HOST' "$SCRIPT_DIR/tmux-mqtt-colors.sh" | grep -q 'claude/led'; then
    pass "claude/led 仍走 \$MQTT_HOST（RPi5B）"
else
    fail "claude/led 未使用 \$MQTT_HOST"
fi

# ── T6b: IME_Indicator config.py 無 MQTT_TOPIC="claude/led"（dead code 已移除） ──
echo "[T6b] IME_Indicator config.py: 無 MQTT_TOPIC claude/led"
if [ -f "$CONFIG_FILE" ]; then
    if grep -q '^MQTT_TOPIC' "$CONFIG_FILE"; then
        fail "config.py 仍有 MQTT_TOPIC（dead code 未移除）"
    else
        pass "config.py 無 MQTT_TOPIC（dead code 已清除）"
    fi
fi

# ── T6c: IME_Indicator main.py 有 on_connect callback（防止 MQTT 靜默失敗回歸） ──
# 今天的 incident：paho 自動重連 TCP，但無 on_connect → 不重發 ime/state → tmux 停滯
MAIN_FILE="$SCRIPT_DIR/../IME_Indicator/python_indicator/main.py"
echo "[T6c] IME_Indicator main.py: 有 on_connect callback"
if [ -f "$MAIN_FILE" ]; then
    if grep -q 'on_connect' "$MAIN_FILE"; then
        pass "main.py 有 on_connect callback"
    else
        fail "main.py 無 on_connect callback（MQTT 斷線後會靜默失敗）"
    fi
else
    fail "main.py 不存在: $MAIN_FILE"
fi

# ── T6d: on_connect 內重發 ime/state（確保重連恢復） ──
echo "[T6d] IME_Indicator main.py: on_connect 內 publish ime/state"
if [ -f "$MAIN_FILE" ]; then
    # 擷取 on_connect 函式，確認內含 publish
    ON_CONNECT=$(sed -n '/def on_connect/,/^[[:space:]]*def \|^[[:space:]]*client\./p' "$MAIN_FILE")
    if echo "$ON_CONNECT" | grep -q 'publish'; then
        pass "on_connect 內有 publish（重連自動恢復）"
    else
        fail "on_connect 內無 publish（重連後 ime/state 不會重發）"
    fi
fi

# ── T9: STATE_POLL_INTERVAL ≤ 50ms（防止回歸） ──
echo "[T9] IME_Indicator config.py: STATE_POLL_INTERVAL ≤ 50ms"
if [ -f "$CONFIG_FILE" ]; then
    INTERVAL=$(grep '^STATE_POLL_INTERVAL' "$CONFIG_FILE" | head -1 | grep -oP '[0-9]+\.[0-9]+')
    # awk: 1 if interval <= 0.05, 0 otherwise
    if [ -n "$INTERVAL" ] && [ "$(echo "$INTERVAL" | awk '{print ($1 <= 0.05)}')" = "1" ]; then
        pass "STATE_POLL_INTERVAL = ${INTERVAL}s (≤ 50ms)"
    else
        fail "STATE_POLL_INTERVAL = ${INTERVAL}s（超過 50ms，延遲會被感知）"
    fi
fi

# ────────────────────────────────────
# E2E 測試：模擬 IME_Indicator → tmux
# ────────────────────────────────────
echo ""
echo -e "${CYAN}── E2E 測試（模擬 IME 切換）──${NC}"

# 保存原始 ime_state，測試結束後恢復
ORIG_IME_STATE=$(tmux show -gv @ime_state 2>/dev/null)

# ── T7: publish "en" → tmux @ime_state 變成 "en" ──
echo "[T7] publish ime/state=en → tmux @ime_state 更新為 en"
mosquitto_pub -h localhost -p 1883 -t "ime/state" -m "en" 2>/dev/null
sleep 0.5
STATE=$(tmux show -gv @ime_state 2>/dev/null)
if [ "$STATE" = "en" ]; then
    pass "tmux @ime_state = en"
else
    fail "tmux @ime_state = '$STATE'（預期 en）"
fi

# ── T8: publish "zh" → tmux @ime_state 變成 "zh" ──
echo "[T8] publish ime/state=zh → tmux @ime_state 更新為 zh"
mosquitto_pub -h localhost -p 1883 -t "ime/state" -m "zh" 2>/dev/null
sleep 0.5
STATE=$(tmux show -gv @ime_state 2>/dev/null)
if [ "$STATE" = "zh" ]; then
    pass "tmux @ime_state = zh"
else
    fail "tmux @ime_state = '$STATE'（預期 zh）"
fi

# 恢復原始狀態
if [ -n "$ORIG_IME_STATE" ]; then
    tmux set -g @ime_state "$ORIG_IME_STATE" 2>/dev/null
fi

# ────────────────────────────────────
# 一致性檢查
# ────────────────────────────────────
echo ""
echo -e "${CYAN}── 一致性檢查 ──${NC}"

# ── T10: IME state file 與 MQTT retained 一致 ──
# 今天的 bug：IME_Indicator MQTT 斷線 → state file 更新但 MQTT 停滯 → tmux 不變
echo "[T10] C:\\Temp\\ime_state 與 MQTT ime/state retained 一致"
IME_STATE_PATH="/mnt/c/Temp/ime_state"
if [ -f "$IME_STATE_PATH" ]; then
    FILE_STATE=$(cat "$IME_STATE_PATH" 2>/dev/null | tr -d '[:space:]')
    MQTT_STATE=$(timeout 2 mosquitto_sub -h localhost -p 1883 -t "ime/state" -C 1 2>/dev/null | tr -d '[:space:]')
    if [ -n "$FILE_STATE" ] && [ -n "$MQTT_STATE" ]; then
        if [ "$FILE_STATE" = "$MQTT_STATE" ]; then
            pass "一致: file=$FILE_STATE, mqtt=$MQTT_STATE"
        else
            fail "不一致: file=$FILE_STATE, mqtt=$MQTT_STATE（IME_Indicator MQTT 可能斷線）"
        fi
    else
        fail "無法讀取: file='$FILE_STATE', mqtt='$MQTT_STATE'"
    fi
else
    pass "ime_state file 不存在（跳過，非 Windows 環境）"
fi

# ────────────────────────────────────
# 部署同步檢查
# ────────────────────────────────────
echo ""
echo -e "${CYAN}── 部署同步檢查 ──${NC}"

# ── T11: dotfiles 與 Windows 端 IME_Indicator 一致 ──
echo "[T11] dotfiles vs Windows: IME_Indicator python 檔案一致"
WIN_DIR="/mnt/c/Users/duofilm/IME_Indicator/python_indicator"
SRC_DIR="$SCRIPT_DIR/../IME_Indicator/python_indicator"
if [ ! -d "$WIN_DIR" ]; then
    pass "Windows 端不存在（跳過，非 Windows 環境）"
else
    drift=""
    for f in "$SRC_DIR"/*.py; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        if [ -f "$WIN_DIR/$name" ]; then
            if ! diff -q "$f" "$WIN_DIR/$name" >/dev/null 2>&1; then
                drift+="$name "
            fi
        else
            drift+="$name(missing) "
        fi
    done
    if [ -z "$drift" ]; then
        pass "所有 .py 檔案一致"
    else
        fail "不一致: ${drift}（執行 scripts/deploy-ime-indicator.sh 同步）"
    fi
fi

# ── 結果 ──
echo ""
echo "=== 結果: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
