#!/bin/bash
# lib/mqtt.sh - MQTT 共用函式庫
#
# 所有 MQTT publisher 共用的宣告與函式。
# 修改 payload 格式只需改這裡，所有 publisher 自動同步。
#
# 用法: source "$SCRIPT_DIR/lib/mqtt.sh"

# ── 常數 ──
IME_STATE_FILE="/mnt/c/Temp/ime_state"

# ── MQTT broker 設定載入 ──
# 從 wsl/claude-hooks.json 讀取，檔案不存在則用預設值
load_mqtt_config() {
    local config="${1:-$SCRIPT_DIR/../wsl/claude-hooks.json}"
    if [ -f "$config" ]; then
        MQTT_HOST=$(jq -r '.MQTT_HOST // "192.168.88.10"' "$config")
        MQTT_PORT=$(jq -r '.MQTT_PORT // "1883"' "$config")
    else
        MQTT_HOST="192.168.88.10"
        MQTT_PORT="1883"
    fi
}

# ── 建構 MQTT payload（語意：domain + state + project）──
# 唯一定義點。所有 publisher 必須用此函式，禁止 inline jq 自行拼裝。
build_payload() {
    local domain="$1"
    local state="$2"
    local project="$3"
    jq -cn --arg domain "$domain" --arg state "$state" --arg project "$project" \
        '{domain: $domain, state: $state, project: $project}'
}
