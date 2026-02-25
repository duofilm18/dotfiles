#!/bin/bash
# test-ime-local-hub.sh - IME 檔案介面測試
#
# 驗證 IME 資料流：IME_Indicator → C:\Temp\ime_state → tmux @ime_state
# TDD: 先寫測試 → 紅燈 → 改 code → 綠燈
#
# 測試分兩層：
#   靜態檢查（T1-T6）：驗證 code 設定正確
#   E2E 測試（T7-T8）：寫檔案模擬 IME_Indicator，驗證 tmux 即時收到

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓ PASS${NC}: $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗ FAIL${NC}: $1"; ((FAIL++)); }

echo "=== IME 檔案介面測試 ==="
echo ""

# ────────────────────────────────────
# 靜態檢查
# ────────────────────────────────────
echo -e "${CYAN}── 靜態檢查 ──${NC}"

# ── T1: tmux-mqtt-colors.sh ime_loop 讀 IME_STATE_FILE ──
echo "[T1] tmux-mqtt-colors.sh: ime_loop 讀取 IME_STATE_FILE"
if grep -q 'cat "$IME_STATE_FILE"' "$SCRIPT_DIR/tmux-mqtt-colors.sh"; then
    pass "ime_loop 讀取檔案"
else
    fail "ime_loop 未讀取 IME_STATE_FILE"
fi

# ── T2: tmux-mqtt-colors.sh ime_loop 不使用 mosquitto_sub ──
echo "[T2] tmux-mqtt-colors.sh: ime_loop 無 mosquitto_sub"
IME_LOOP=$(sed -n '/^ime_loop()/,/^}/p' "$SCRIPT_DIR/tmux-mqtt-colors.sh")
if echo "$IME_LOOP" | grep -q 'mosquitto_sub'; then
    fail "ime_loop 仍使用 mosquitto_sub（應改為讀檔案）"
else
    pass "ime_loop 無 mosquitto_sub（讀檔案）"
fi

# ── T2b: ime_loop 不含 mosquitto_pub（純讀取，不發 LED） ──
echo "[T2b] tmux-mqtt-colors.sh: ime_loop 無 mosquitto_pub"
if echo "$IME_LOOP" | grep -q 'mosquitto_pub'; then
    fail "ime_loop 仍含 mosquitto_pub（應只做 tmux bridge）"
else
    pass "ime_loop 無 mosquitto_pub（純讀取）"
fi

# ── T2c: 不使用 IME_INTERRUPT_FILE（改用 epoch 變數） ──
echo "[T2c] tmux-mqtt-colors.sh: 無 IME_INTERRUPT_FILE"
if grep -q 'IME_INTERRUPT_FILE' "$SCRIPT_DIR/tmux-mqtt-colors.sh"; then
    fail "仍使用 IME_INTERRUPT_FILE（應改用 epoch 變數）"
else
    pass "無 IME_INTERRUPT_FILE（epoch-based）"
fi

# ── T3: IME_Indicator config.py 無 MQTT 設定（已移除） ──
echo "[T3] IME_Indicator config.py: 無 MQTT 設定"
CONFIG_FILE="$SCRIPT_DIR/../IME_Indicator/python_indicator/config.py"
if [ ! -f "$CONFIG_FILE" ]; then
    fail "config.py 不存在: $CONFIG_FILE"
else
    if grep -q 'MQTT_BROKER\|MQTT_PORT\|MQTT_ENABLE\|MQTT_IME_TOPIC' "$CONFIG_FILE"; then
        fail "config.py 仍有 MQTT 設定（應已移除）"
    else
        pass "config.py 無 MQTT 設定"
    fi
fi

# ── T4: IME_Indicator config.py 有 IME_STATE_FILE ──
echo "[T4] IME_Indicator config.py: 有 IME_STATE_FILE"
if [ -f "$CONFIG_FILE" ]; then
    if grep -q 'IME_STATE_FILE' "$CONFIG_FILE"; then
        pass "config.py 有 IME_STATE_FILE"
    else
        fail "config.py 無 IME_STATE_FILE"
    fi
fi

# ── T5: IME_Indicator main.py 無 MQTT 程式碼 ──
MAIN_FILE="$SCRIPT_DIR/../IME_Indicator/python_indicator/main.py"
echo "[T5] IME_Indicator main.py: 無 MQTT 程式碼"
if [ -f "$MAIN_FILE" ]; then
    if grep -q 'mqtt\|paho\|MQTT' "$MAIN_FILE"; then
        fail "main.py 仍有 MQTT 程式碼（應已移除）"
    else
        pass "main.py 無 MQTT 程式碼"
    fi
else
    fail "main.py 不存在: $MAIN_FILE"
fi

# ── T6: Claude state publishing 仍用 $MQTT_HOST（不動 RPi5B） ──
echo "[T6] tmux-mqtt-colors.sh: 主迴圈 claude/led 仍用 \$MQTT_HOST"
if grep -A1 'mosquitto_pub.*\$MQTT_HOST' "$SCRIPT_DIR/tmux-mqtt-colors.sh" | grep -q 'claude/led'; then
    pass "claude/led 仍走 \$MQTT_HOST（RPi5B）"
else
    fail "claude/led 未使用 \$MQTT_HOST"
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

IME_STATE_PATH="/mnt/c/Temp/ime_state"

# 保存原始 ime_state，測試結束後恢復
ORIG_IME_STATE=$(tmux show -gv @ime_state 2>/dev/null)
ORIG_FILE_STATE=""
if [ -f "$IME_STATE_PATH" ]; then
    ORIG_FILE_STATE=$(cat "$IME_STATE_PATH" 2>/dev/null)
fi

# ── T7: 寫 "en" → tmux @ime_state 變成 "en" ──
echo "[T7] 寫 ime_state=en → tmux @ime_state 更新為 en"
echo -n "en" > "$IME_STATE_PATH" 2>/dev/null
sleep 0.5
STATE=$(tmux show -gv @ime_state 2>/dev/null)
if [ "$STATE" = "en" ]; then
    pass "tmux @ime_state = en"
else
    fail "tmux @ime_state = '$STATE'（預期 en）"
fi

# ── T8: 寫 "zh" → tmux @ime_state 變成 "zh" ──
echo "[T8] 寫 ime_state=zh → tmux @ime_state 更新為 zh"
echo -n "zh" > "$IME_STATE_PATH" 2>/dev/null
sleep 0.5
STATE=$(tmux show -gv @ime_state 2>/dev/null)
if [ "$STATE" = "zh" ]; then
    pass "tmux @ime_state = zh"
else
    fail "tmux @ime_state = '$STATE'（預期 zh）"
fi

# 恢復原始狀態
if [ -n "$ORIG_FILE_STATE" ]; then
    echo -n "$ORIG_FILE_STATE" > "$IME_STATE_PATH" 2>/dev/null
fi
if [ -n "$ORIG_IME_STATE" ]; then
    tmux set -g @ime_state "$ORIG_IME_STATE" 2>/dev/null
fi

# ────────────────────────────────────
# 一致性檢查
# ────────────────────────────────────
echo ""
echo -e "${CYAN}── 一致性檢查 ──${NC}"

# ── T10: IME state file 存在且格式正確 ──
echo "[T10] C:\\Temp\\ime_state 存在且格式正確"
if [ -f "$IME_STATE_PATH" ]; then
    FILE_STATE=$(cat "$IME_STATE_PATH" 2>/dev/null | tr -d '[:space:]')
    if [ "$FILE_STATE" = "zh" ] || [ "$FILE_STATE" = "en" ]; then
        pass "ime_state = $FILE_STATE（格式正確）"
    else
        fail "ime_state = '$FILE_STATE'（預期 zh 或 en）"
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
source "$SCRIPT_DIR/../windows/deploy-paths.sh"
WIN_DIR="$DEPLOY_IME_PYTHON"
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
