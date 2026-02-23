#!/usr/bin/env bats
# led_e2e.bats - LED 端到端: RPi5 ACK + GPIO 驗證
#
# 需要 RPi5B MQTT broker 在線，不通則 skip

setup() {
    load test_helper
    common_setup
    command -v mosquitto_pub &>/dev/null || skip "mosquitto not installed"
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "test/ping" -m "ping" 2>/dev/null \
        || skip "MQTT unreachable"
}

teardown() {
    common_teardown
}

# 發送燈效並等待 RPi5 ACK
send_and_get_ack() {
    local state="$1"
    mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" \
        -t "claude/led/ack" -C 1 -W 5 2>/dev/null &
    local sub_pid=$!
    sleep 0.3
    "$SCRIPT_DIR/notify.sh" "$state"
    wait "$sub_pid" 2>/dev/null
}

# 比對 ACK 的 RGB + pattern + is_lit
assert_led_ack() {
    local state="$1"
    local expect_lit="${2:-true}"

    local ack
    ack=$(send_and_get_ack "$state")
    [ -n "$ack" ]

    local expected
    expected=$(jq -c --arg s "$state" '.[$s]' "$EFFECTS_FILE")

    [ "$(echo "$ack" | jq '.r')" = "$(echo "$expected" | jq '.r')" ]
    [ "$(echo "$ack" | jq '.g')" = "$(echo "$expected" | jq '.g')" ]
    [ "$(echo "$ack" | jq '.b')" = "$(echo "$expected" | jq '.b')" ]
    [ "$(echo "$ack" | jq -r '.pattern')" = "$(echo "$expected" | jq -r '.pattern')" ]

    local is_lit
    is_lit=$(echo "$ack" | jq -r '.is_lit // empty')
    if [ "$expect_lit" = "true" ]; then
        [ "$is_lit" = "true" ]
    else
        [ "$is_lit" != "true" ]
    fi
}

@test "LED idle: ACK color + GPIO is_lit" {
    assert_led_ack "idle"
}

@test "LED running: ACK color + GPIO is_lit" {
    assert_led_ack "running"
}

@test "LED waiting: ACK color + GPIO is_lit" {
    assert_led_ack "waiting"
}

@test "LED completed: ACK color + GPIO is_lit" {
    assert_led_ack "completed"
}

@test "LED error: ACK color + GPIO is_lit" {
    assert_led_ack "error"
}

@test "LED off: ACK 且 LED 熄滅" {
    assert_led_ack "off" "false"
}
