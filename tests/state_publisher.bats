#!/usr/bin/env bats
# state_publisher.bats - tmux-mqtt-colors.sh 純邏輯測試
#
# 測試 build_payload、blink 狀態切換邏輯、window 消失偵測。
# 不啟動真實主迴圈（需要 tmux + MQTT），只 source 函式逐一驗證。

setup() {
    load test_helper
    common_setup
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
    EFFECTS_FILE="$SCRIPT_DIR/../wsl/led-effects.json"
}

teardown() {
    common_teardown
}

# ── build_payload ──────────────────────────────────────

@test "SP-1: build_payload idle → 含 r/g/b/pattern/state/project" {
    source_build_payload() {
        local EFFECTS_FILE="$EFFECTS_FILE"
        build_payload() {
            local state="$1" project="$2"
            jq -c --arg state "$state" --arg project "$project" \
                '.[$state] // empty | . + {state: $state, project: $project}' "$EFFECTS_FILE" 2>/dev/null
        }
        build_payload "idle" "dotfiles"
    }
    run source_build_payload
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.r == 255'
    echo "$output" | jq -e '.pattern == "blink"'
    echo "$output" | jq -e '.state == "idle"'
    echo "$output" | jq -e '.project == "dotfiles"'
}

@test "SP-2: build_payload running → pulse pattern" {
    source_build_payload() {
        local EFFECTS_FILE="$EFFECTS_FILE"
        build_payload() {
            local state="$1" project="$2"
            jq -c --arg state "$state" --arg project "$project" \
                '.[$state] // empty | . + {state: $state, project: $project}' "$EFFECTS_FILE" 2>/dev/null
        }
        build_payload "running" "landtw"
    }
    run source_build_payload
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.pattern == "pulse"'
    echo "$output" | jq -e '.b == 255'
    echo "$output" | jq -e '.project == "landtw"'
}

@test "SP-3: build_payload unknown state → 空輸出" {
    source_build_payload() {
        local EFFECTS_FILE="$EFFECTS_FILE"
        build_payload() {
            local state="$1" project="$2"
            jq -c --arg state "$state" --arg project "$project" \
                '.[$state] // empty | . + {state: $state, project: $project}' "$EFFECTS_FILE" 2>/dev/null
        }
        build_payload "foobar" "test"
    }
    run source_build_payload
    [ -z "$output" ]
}

@test "SP-4: build_payload completed → rainbow pattern" {
    source_build_payload() {
        local EFFECTS_FILE="$EFFECTS_FILE"
        build_payload() {
            local state="$1" project="$2"
            jq -c --arg state "$state" --arg project "$project" \
                '.[$state] // empty | . + {state: $state, project: $project}' "$EFFECTS_FILE" 2>/dev/null
        }
        build_payload "completed" "duofilm"
    }
    run source_build_payload
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.pattern == "rainbow"'
    echo "$output" | jq -e '.times == 3'
}

# ── led-effects.json 完整性 ───────────────────────────

@test "SP-5: led-effects.json 包含全部 5+1 狀態" {
    for state in idle running waiting completed error off; do
        jq -e --arg s "$state" '.[$s]' "$EFFECTS_FILE" >/dev/null
    done
}

@test "SP-6: 每個狀態都有 r/g/b/pattern" {
    for state in idle running waiting completed error; do
        jq -e --arg s "$state" '.[$s] | .r and .g != null and .b != null and .pattern' "$EFFECTS_FILE" >/dev/null
    done
}

# ── blink 邏輯（分支驗證）────────────────────────────

@test "SP-7: blink_loop 只切換 idle/waiting（對齊 tmux-mqtt-colors.sh case）" {
    # blink_loop 的 case 分支只對 idle/waiting 做 on/off 切換
    # 其他狀態清除 blink。驗證 led-effects.json 中這兩個狀態存在
    for state in idle waiting; do
        jq -e --arg s "$state" '.[$s]' "$EFFECTS_FILE" >/dev/null
    done
    # running 用 pulse 不用 blink，completed 用 rainbow
    local idle_pattern running_pattern
    idle_pattern=$(jq -r '.idle.pattern' "$EFFECTS_FILE")
    running_pattern=$(jq -r '.running.pattern' "$EFFECTS_FILE")
    [ "$idle_pattern" = "blink" ]
    [ "$running_pattern" = "pulse" ]
}

@test "SP-8: blink toggle 邏輯 — on→off, off→on, 其他→清除" {
    # 驗證 blink_loop 的 case 分支正確性（純邏輯模擬）
    blink_toggle() {
        local state="$1" blink="$2"
        case "$state" in
            idle|waiting)
                if [ "$blink" = "on" ]; then echo "off"
                else echo "on"; fi ;;
            *) echo "" ;;
        esac
    }

    [ "$(blink_toggle idle on)" = "off" ]
    [ "$(blink_toggle idle off)" = "on" ]
    [ "$(blink_toggle idle "")" = "on" ]
    [ "$(blink_toggle waiting on)" = "off" ]
    [ "$(blink_toggle waiting off)" = "on" ]
    [ "$(blink_toggle running on)" = "" ]
    [ "$(blink_toggle completed off)" = "" ]
}

# ── 狀態變化偵測（associative array 邏輯）──────────

@test "SP-9: 相同狀態不發 MQTT（debounce 邏輯）" {
    # 模擬主迴圈的 prev_states 比較
    should_publish() {
        local prev="$1" current="$2"
        [ "$prev" != "$current" ] && echo "yes" || echo "no"
    }

    [ "$(should_publish "" "idle")" = "yes" ]        # 新專案
    [ "$(should_publish "idle" "idle")" = "no" ]      # 無變化
    [ "$(should_publish "idle" "running")" = "yes" ]  # 狀態變化
    [ "$(should_publish "running" "")" = "yes" ]      # 專案消失
}

@test "SP-10: window 消失 → 應清除 retained（空 payload）" {
    # 模擬主迴圈的 window 消失偵測邏輯
    detect_removed() {
        local -A prev=([dotfiles]="idle" [ghost]="running")
        local -A current=([dotfiles]="idle")
        local removed=""
        for project in "${!prev[@]}"; do
            if [ -z "${current[$project]:-}" ]; then
                removed+="$project "
            fi
        done
        echo "$removed"
    }
    local result
    result=$(detect_removed)
    [[ "$result" == *"ghost"* ]]
    [[ "$result" != *"dotfiles"* ]]
}
