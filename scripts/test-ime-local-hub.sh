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

# ── T2: tmux-mqtt-colors.sh ime_loop 不使用 $MQTT_HOST ──
echo "[T2] tmux-mqtt-colors.sh: ime_loop 不使用 \$MQTT_HOST"
IME_LOOP=$(sed -n '/^ime_loop()/,/^}/p' "$SCRIPT_DIR/tmux-mqtt-colors.sh")
if echo "$IME_LOOP" | grep -q '\$MQTT_HOST'; then
    fail "ime_loop 仍使用 \$MQTT_HOST"
else
    pass "ime_loop 不依賴 \$MQTT_HOST"
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

# ── 結果 ──
echo ""
echo "=== 結果: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
