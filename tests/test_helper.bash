# test_helper.bash - Bats 共用 setup/teardown/fire/assert
#
# 每個 .bats 的 setup() 呼叫 common_setup，teardown() 呼叫 common_teardown。
# fire() 同時觸發狀態機（claude-hook.sh）和音效 dispatch（play-melody.sh）。

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
EFFECTS_FILE="$SCRIPT_DIR/../rpi5b/mqtt-led/led-effects.json"
MQTT_HOST="${MQTT_HOST:-192.168.88.10}"
MQTT_PORT="${MQTT_PORT:-1883}"
TEST_PROJECT="bats-$$"
STATE_FILE="/tmp/claude-led-state-${TEST_PROJECT}"
DEDUP_FILE="/tmp/claude-led-dedup-${TEST_PROJECT}"
IDLE_PENDING="/tmp/claude-idle-pending-${TEST_PROJECT}"
ACTIVITY_FILE="/tmp/claude-activity-${TEST_PROJECT}"
LOCK_FILE="/tmp/claude-led-${TEST_PROJECT}.lock"
MELODY_LOG="/tmp/test-melody-capture.log"

common_setup() {
    rm -f "$STATE_FILE" "$DEDUP_FILE" "$IDLE_PENDING" \
          "$ACTIVITY_FILE" "$LOCK_FILE" "$MELODY_LOG"
    touch /tmp/test-melody-log-mode
}

common_teardown() {
    rm -f "$STATE_FILE" "$DEDUP_FILE" "$IDLE_PENDING" \
          "$ACTIVITY_FILE" "$LOCK_FILE" "$MELODY_LOG"
    rm -f /tmp/test-melody-log-mode
}

# 觸發 hook 事件（狀態機 + 音效 dispatch，對齊 claude-dispatch.sh）
fire() {
    local event="$1"
    local matcher="${2:-}"
    local json='{}'
    [ $# -ge 3 ] && json="$3"

    # 狀態機
    echo "$json" | "$SCRIPT_DIR/claude-hook.sh" "$event" "$matcher" "$TEST_PROJECT" 2>/dev/null || true

    # 音效決策（對齊 claude-dispatch.sh）
    local melody=""
    case "$event/$matcher" in
        UserPromptSubmit/)              melody="short_running" ;;
        PreToolUse/AskUserQuestion)     melody="nokia" ;;
        Notification/permission_prompt) melody="nokia" ;;
        Notification/idle_prompt)       melody="minimal_double" ;;
        Stop/)                          melody="star_wars" ;;
    esac
    if [ -z "$melody" ] && [ "$event" = "PostToolUse" ]; then
        local git_cmd
        git_cmd=$(echo "$json" | jq -r '.tool_input.command // empty' 2>/dev/null) || true
        case "${git_cmd:-}" in
            *"git push"*)   melody="windows_xp" ;;
            *"git commit"*) melody="short_success" ;;
            *"git add"*)    melody="minimal_double" ;;
        esac
    fi
    if [ -n "$melody" ]; then
        "$SCRIPT_DIR/play-melody.sh" "$melody" 2>/dev/null || true
    fi
}

# 驗證 STATE_FILE 第一行
assert_state() {
    local expected="$1"
    local actual
    actual=$(head -1 "$STATE_FILE" 2>/dev/null)
    [ "$actual" = "$expected" ]
}

# 驗證 MELODY_LOG 最後一行含 pattern
assert_melody() {
    local expected="$1"
    [ -f "$MELODY_LOG" ] && tail -1 "$MELODY_LOG" | grep -q "$expected"
}

# 驗證 MELODY_LOG 行數未增加
assert_no_melody() {
    local before="$1"
    local after
    after=$(melody_line_count)
    [ "$before" = "$after" ]
}

# 回傳 MELODY_LOG 目前行數
melody_line_count() {
    if [ -f "$MELODY_LOG" ]; then
        wc -l < "$MELODY_LOG"
    else
        echo 0
    fi
}
