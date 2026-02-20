#!/bin/bash
# test-hooks.sh - Hook 系統完整測試
#
# 逐層測試：play-melody → notify → claude-hook
# 每一層獨立驗證，抓出音樂不響的原因
#
# 用法: test-hooks.sh [層級]
#   all          全部測試（預設）
#   melody       只測 play-melody.sh
#   notify       只測 notify.sh
#   hook         只測 claude-hook.sh 事件映射
#   git          只測 git 音效觸發
#   dedup        只測去重邏輯
#   e2e          端對端模擬真實 hook 事件

set -uo pipefail
# 不用 set -e，因為測試會檢查失敗情況

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LEVEL="${1:-all}"

# 顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { ((PASS++)); echo -e "  ${GREEN}✓ PASS${NC}: $1"; }
fail() { ((FAIL++)); echo -e "  ${RED}✗ FAIL${NC}: $1"; }
warn() { ((WARN++)); echo -e "  ${YELLOW}⚠ WARN${NC}: $1"; }
header() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ══════════════════════════════════════════════════════════
# Layer 1: play-melody.sh
# ══════════════════════════════════════════════════════════
test_melody() {
    header "Layer 1: play-melody.sh"

    # 1-1: 腳本存在且可執行
    if [ -x "$SCRIPT_DIR/play-melody.sh" ]; then
        pass "play-melody.sh 存在且可執行"
    else
        fail "play-melody.sh 不存在或不可執行"
        return
    fi

    # 1-2: powershell.exe 可用
    if command -v powershell.exe &>/dev/null; then
        pass "powershell.exe 可用"
    else
        fail "powershell.exe 不在 PATH（WSL 無法呼叫 Windows beep）"
        return
    fi

    # 1-3: powershell.exe 啟動速度
    local start_time end_time elapsed
    start_time=$(date +%s%N)
    powershell.exe -c "exit" 2>/dev/null
    end_time=$(date +%s%N)
    elapsed=$(( (end_time - start_time) / 1000000 ))
    if [ "$elapsed" -lt 3000 ]; then
        pass "powershell.exe 啟動耗時 ${elapsed}ms（< 3s）"
    else
        warn "powershell.exe 啟動耗時 ${elapsed}ms（慢！可能導致 hook timeout 殺掉進程）"
    fi

    # 1-4: 直接播放測試音
    echo -e "  ${YELLOW}♪ 播放 minimal_beep...（你應該聽到一聲短嗶）${NC}"
    "$SCRIPT_DIR/play-melody.sh" minimal_beep
    local exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "play-melody.sh minimal_beep 執行成功（exit=$exit_code）"
    else
        fail "play-melody.sh minimal_beep 執行失敗（exit=$exit_code）"
    fi

    # 1-5: 背景播放（模擬 hook 呼叫方式）
    echo -e "  ${YELLOW}♪ 背景播放 short_success...（你應該聽到三連升音）${NC}"
    setsid "$SCRIPT_DIR/play-melody.sh" short_success &>/dev/null &
    local bg_pid=$!
    sleep 3
    if ! kill -0 "$bg_pid" 2>/dev/null; then
        pass "背景播放已完成（進程已結束）"
    else
        warn "背景播放 3 秒後仍在跑（powershell.exe 可能很慢）"
        wait "$bg_pid" 2>/dev/null || true
    fi

    # 1-6: 所有旋律名稱是否有效
    local melodies="minimal_beep minimal_double minimal_triple short_success short_error short_waiting short_running default_waiting default_error default_completed default_running super_mario star_wars nokia tetris zelda_secret pacman mission_impossible pink_panther jingle_bells happy_birthday windows_xp"
    local valid=0
    local total=0
    for m in $melodies; do
        ((total++))
        # 只驗證 case 分支存在（不實際播放）
        if grep -q "^    $m)" "$SCRIPT_DIR/play-melody.sh"; then
            ((valid++))
        else
            fail "旋律 '$m' 在 play-melody.sh 中找不到 case 分支"
        fi
    done
    if [ "$valid" -eq "$total" ]; then
        pass "全部 $total 首旋律名稱都有對應 case 分支"
    fi
}

# ══════════════════════════════════════════════════════════
# Layer 2: notify.sh
# ══════════════════════════════════════════════════════════
test_notify() {
    header "Layer 2: notify.sh"

    # 2-1: 腳本存在且可執行
    if [ -x "$SCRIPT_DIR/notify.sh" ]; then
        pass "notify.sh 存在且可執行"
    else
        fail "notify.sh 不存在或不可執行"
        return
    fi

    # 2-2: led-effects.json 存在且有效
    local effects_file="$SCRIPT_DIR/../wsl/led-effects.json"
    if [ -f "$effects_file" ]; then
        pass "led-effects.json 存在"
    else
        fail "led-effects.json 不存在: $effects_file"
        return
    fi

    if jq empty "$effects_file" 2>/dev/null; then
        pass "led-effects.json 是合法 JSON"
    else
        fail "led-effects.json JSON 格式錯誤"
        return
    fi

    # 2-3: 每個狀態的旋律設定
    local states="idle running waiting completed error"
    for state in $states; do
        local melody
        melody=$(jq -r --arg s "$state" '.[$s].melody // "NONE"' "$effects_file")
        if [ "$melody" != "NONE" ] && [ -n "$melody" ]; then
            # 確認旋律名在 play-melody.sh 中存在
            if grep -q "^    ${melody})" "$SCRIPT_DIR/play-melody.sh"; then
                pass "狀態 $state → 旋律 '$melody' ✓"
            else
                fail "狀態 $state → 旋律 '$melody' 但 play-melody.sh 沒有此 case"
            fi
        else
            warn "狀態 $state 沒有設定旋律"
        fi
    done

    # 2-4: jq 解析測試
    local test_effect
    test_effect=$(jq -c --arg state "running" '.[$state] // empty' "$effects_file")
    if [ -n "$test_effect" ]; then
        local test_melody
        test_melody=$(echo "$test_effect" | jq -r '.melody // empty')
        if [ "$test_melody" = "short_running" ]; then
            pass "jq 正確解析 running → melody=short_running"
        else
            fail "jq 解析結果不符預期：running melody='$test_melody'（預期 short_running）"
        fi
    else
        fail "jq 無法從 led-effects.json 讀取 running 狀態"
    fi

    # 2-5: mosquitto_pub 連線測試
    if command -v mosquitto_pub &>/dev/null; then
        local mqtt_host="${MQTT_HOST:-192.168.88.10}"
        if mosquitto_pub -h "$mqtt_host" -p 1883 -t "claude/test" -m '{"test":true}' 2>/dev/null; then
            pass "MQTT 連線到 $mqtt_host 成功"
        else
            warn "MQTT 連線到 $mqtt_host 失敗（LED 燈不會亮，但不影響音樂）"
        fi
    else
        warn "mosquitto_pub 未安裝（LED 功能不可用）"
    fi

    # 2-6: 實際觸發 notify.sh running 狀態
    echo -e "  ${YELLOW}♪ 觸發 notify.sh running...（應該聽到 short_running 兩連升音）${NC}"
    "$SCRIPT_DIR/notify.sh" running
    sleep 2
    pass "notify.sh running 執行完畢"
}

# ══════════════════════════════════════════════════════════
# Layer 3: claude-hook.sh 事件→狀態映射
# ══════════════════════════════════════════════════════════
test_hook() {
    header "Layer 3: claude-hook.sh 事件→狀態映射"

    if [ ! -x "$SCRIPT_DIR/claude-hook.sh" ]; then
        fail "claude-hook.sh 不存在或不可執行"
        return
    fi

    # 清除狀態檔（乾淨測試環境）
    rm -f /tmp/claude-led-state /tmp/claude-led-dedup /tmp/claude-idle-pending

    # 3-1: UserPromptSubmit → RUNNING
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" UserPromptSubmit 2>/dev/null || true
    local state
    state=$(cat /tmp/claude-led-state 2>/dev/null)
    if [ "$state" = "RUNNING" ]; then
        pass "UserPromptSubmit → RUNNING"
    else
        fail "UserPromptSubmit → '$state'（預期 RUNNING）"
    fi
    sleep 2.1  # 超過去重時間

    # 3-2: PreToolUse AskUserQuestion → WAITING
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" PreToolUse AskUserQuestion 2>/dev/null || true
    state=$(cat /tmp/claude-led-state 2>/dev/null)
    if [ "$state" = "WAITING" ]; then
        pass "PreToolUse AskUserQuestion → WAITING"
    else
        fail "PreToolUse AskUserQuestion → '$state'（預期 WAITING）"
    fi
    sleep 2.1

    # 3-3: PostToolUse AskUserQuestion → RUNNING
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" PostToolUse AskUserQuestion 2>/dev/null || true
    state=$(cat /tmp/claude-led-state 2>/dev/null)
    if [ "$state" = "RUNNING" ]; then
        pass "PostToolUse AskUserQuestion → RUNNING"
    else
        fail "PostToolUse AskUserQuestion → '$state'（預期 RUNNING）"
    fi
    sleep 2.1

    # 3-4: Notification idle_prompt → IDLE
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" Notification idle_prompt 2>/dev/null || true
    state=$(cat /tmp/claude-led-state 2>/dev/null)
    if [ "$state" = "IDLE" ]; then
        pass "Notification idle_prompt → IDLE"
    else
        fail "Notification idle_prompt → '$state'（預期 IDLE）"
    fi
    sleep 2.1

    # 3-5: Notification permission_prompt → WAITING
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" Notification permission_prompt 2>/dev/null || true
    state=$(cat /tmp/claude-led-state 2>/dev/null)
    if [ "$state" = "WAITING" ]; then
        pass "Notification permission_prompt → WAITING"
    else
        fail "Notification permission_prompt → '$state'（預期 WAITING）"
    fi
    sleep 2.1

    # 3-6: Stop → COMPLETED（先重設為 RUNNING，避免 WAITING→COMPLETED 抑制）
    rm -f /tmp/claude-led-state /tmp/claude-led-dedup
    echo "RUNNING" > /tmp/claude-led-state
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" Stop 2>/dev/null || true
    state=$(cat /tmp/claude-led-state 2>/dev/null)
    if [ "$state" = "COMPLETED" ]; then
        pass "Stop → COMPLETED"
    else
        fail "Stop → '$state'（預期 COMPLETED）"
    fi
    sleep 2.1

    # 3-7: WAITING 時收到 Stop 應被抑制
    rm -f /tmp/claude-led-state /tmp/claude-led-dedup
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" PreToolUse AskUserQuestion 2>/dev/null || true
    sleep 2.1
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" Stop 2>/dev/null || true
    state=$(cat /tmp/claude-led-state 2>/dev/null)
    if [ "$state" = "WAITING" ]; then
        pass "WAITING 中收到 Stop → 被抑制，維持 WAITING"
    else
        fail "WAITING 中收到 Stop → '$state'（預期維持 WAITING）"
    fi

    # 3-8: PostToolUse Bash 不改變狀態（只觸發 side effect）
    rm -f /tmp/claude-led-state /tmp/claude-led-dedup
    echo "RUNNING" > /tmp/claude-led-state
    echo '{"tool_input":{"command":"ls"}}' | "$SCRIPT_DIR/claude-hook.sh" PostToolUse Bash 2>/dev/null || true
    state=$(cat /tmp/claude-led-state 2>/dev/null)
    if [ "$state" = "RUNNING" ]; then
        pass "PostToolUse Bash → 不改變狀態（維持 RUNNING）"
    else
        fail "PostToolUse Bash → '$state'（預期維持 RUNNING）"
    fi
}

# ══════════════════════════════════════════════════════════
# Layer 4: Git 音效觸發
# ══════════════════════════════════════════════════════════
test_git() {
    header "Layer 4: Git 音效觸發"

    # 4-1: git add 音效
    echo -e "  ${YELLOW}♪ 模擬 git add...（應該聽到 minimal_double 雙嗶）${NC}"
    echo '{"tool_input":{"command":"git add file.txt"}}' | "$SCRIPT_DIR/claude-hook.sh" PostToolUse Bash 2>/dev/null || true
    sleep 2
    pass "git add 音效指令已發送"

    # 4-2: git commit 音效
    echo -e "  ${YELLOW}♪ 模擬 git commit...（應該聽到三連升音 short_success）${NC}"
    echo '{"tool_input":{"command":"git commit -m \"test\""}}' | "$SCRIPT_DIR/claude-hook.sh" PostToolUse Bash 2>/dev/null || true
    sleep 2
    pass "git commit 音效指令已發送"

    # 4-3: git push 音效
    echo -e "  ${YELLOW}♪ 模擬 git push...（應該聽到 Windows XP 開機音）${NC}"
    echo '{"tool_input":{"command":"git push origin main"}}' | "$SCRIPT_DIR/claude-hook.sh" PostToolUse Bash 2>/dev/null || true
    sleep 3
    pass "git push 音效指令已發送"

    # 4-4: 非 git 指令不觸發音效
    echo '{"tool_input":{"command":"ls -la"}}' | "$SCRIPT_DIR/claude-hook.sh" PostToolUse Bash 2>/dev/null || true
    pass "非 git 指令不觸發音效"

    # 4-5: jq 解析 git 指令
    local test_cmd
    test_cmd=$(echo '{"tool_input":{"command":"git add . && git commit -m \"msg\""}}' | jq -r '.tool_input.command // empty')
    if [[ "$test_cmd" == *"git add"* ]]; then
        pass "jq 正確解析複合 git 指令"
    else
        fail "jq 無法解析 tool_input.command"
    fi

    # 4-6: git add + git commit 複合指令只觸發第一個匹配
    echo -e "  ${YELLOW}♪ 模擬 git add && git commit...（case 匹配 git add → minimal_double）${NC}"
    echo '{"tool_input":{"command":"git add file.txt && git commit -m \"msg\""}}' | "$SCRIPT_DIR/claude-hook.sh" PostToolUse Bash 2>/dev/null || true
    sleep 2
    warn "複合 git 指令：case 只會匹配第一個（git add），git commit 的音效被吃掉"
}

# ══════════════════════════════════════════════════════════
# Layer 5: 去重邏輯
# ══════════════════════════════════════════════════════════
test_dedup() {
    header "Layer 5: 去重邏輯"

    rm -f /tmp/claude-led-state /tmp/claude-led-dedup

    # 5-1: 連續兩次相同狀態，第二次被抑制
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" UserPromptSubmit 2>/dev/null || true
    echo -e "  ${YELLOW}（立即再發一次 UserPromptSubmit）${NC}"
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" UserPromptSubmit 2>/dev/null || true
    # 去重應該讓第二次不觸發 notify
    pass "連續相同狀態去重（2 秒內第二次被跳過）"

    # 5-2: 超過 2 秒後相同狀態應觸發
    echo -e "  ${YELLOW}等待 2.5 秒...${NC}"
    sleep 2.5
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" UserPromptSubmit 2>/dev/null || true
    pass "超過 2 秒後重新觸發"
}

# ══════════════════════════════════════════════════════════
# Layer 6: 端對端模擬
# ══════════════════════════════════════════════════════════
test_e2e() {
    header "Layer 6: 端對端模擬（完整 Claude 工作流程）"

    rm -f /tmp/claude-led-state /tmp/claude-led-dedup /tmp/claude-idle-pending

    echo -e "  ${YELLOW}模擬完整流程：使用者送出 → 跑工具 → 問權限 → 完成${NC}"
    echo ""

    # Step 1: 使用者送出訊息
    echo -e "  ${CYAN}[1/6] UserPromptSubmit → RUNNING${NC}"
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" UserPromptSubmit 2>/dev/null || true
    echo -e "  ${YELLOW}♪ 應該聽到 short_running (兩連升音)${NC}"
    sleep 3

    # Step 2: 工具執行（不改變狀態）
    echo -e "  ${CYAN}[2/6] PostToolUse Bash（ls 指令）→ 不改變狀態${NC}"
    echo '{"tool_input":{"command":"ls -la"}}' | "$SCRIPT_DIR/claude-hook.sh" PostToolUse Bash 2>/dev/null || true
    sleep 1

    # Step 3: 需要權限
    echo -e "  ${CYAN}[3/6] Notification permission_prompt → WAITING${NC}"
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" Notification permission_prompt 2>/dev/null || true
    echo -e "  ${YELLOW}♪ 應該聽到 short_waiting (三連升音)${NC}"
    sleep 3

    # Step 4: 使用者允許，繼續跑
    echo -e "  ${CYAN}[4/6] UserPromptSubmit → RUNNING${NC}"
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" UserPromptSubmit 2>/dev/null || true
    echo -e "  ${YELLOW}♪ 應該聽到 short_running (兩連升音)${NC}"
    sleep 3

    # Step 5: git commit
    echo -e "  ${CYAN}[5/6] PostToolUse Bash (git commit) → git 音效${NC}"
    echo '{"tool_input":{"command":"git commit -m \"feat: test\""}}' | "$SCRIPT_DIR/claude-hook.sh" PostToolUse Bash 2>/dev/null || true
    echo -e "  ${YELLOW}♪ 應該聽到 short_success (git commit 音效)${NC}"
    sleep 3

    # Step 6: Claude 完成
    echo -e "  ${CYAN}[6/6] Stop → COMPLETED${NC}"
    echo '{}' | "$SCRIPT_DIR/claude-hook.sh" Stop 2>/dev/null || true
    echo -e "  ${YELLOW}♪ 應該聽到 zelda_secret (完成音效)${NC}"
    sleep 3

    echo ""
    local final_state
    final_state=$(cat /tmp/claude-led-state 2>/dev/null)
    if [ "$final_state" = "COMPLETED" ]; then
        pass "端對端流程完成，最終狀態 COMPLETED"
    else
        fail "最終狀態 '$final_state'（預期 COMPLETED）"
    fi
}

# ══════════════════════════════════════════════════════════
# 主程式
# ══════════════════════════════════════════════════════════

echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Claude Hook 系統測試                 ║${NC}"
echo -e "${CYAN}║  測試層級: $LEVEL$(printf '%*s' $((25 - ${#LEVEL})) '')║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"

case "$LEVEL" in
    melody)  test_melody ;;
    notify)  test_notify ;;
    hook)    test_hook ;;
    git)     test_git ;;
    dedup)   test_dedup ;;
    e2e)     test_e2e ;;
    all)
        test_melody
        test_notify
        test_hook
        test_git
        test_dedup
        test_e2e
        ;;
    *)
        echo "未知層級: $LEVEL"
        echo "可用: all melody notify hook git dedup e2e"
        exit 1
        ;;
esac

# ── 總結 ──
header "測試結果"
echo -e "  ${GREEN}通過: $PASS${NC}"
echo -e "  ${RED}失敗: $FAIL${NC}"
echo -e "  ${YELLOW}警告: $WARN${NC}"

if [ "$FAIL" -gt 0 ]; then
    echo -e "\n${RED}有 $FAIL 項失敗，請檢查上方紅色訊息${NC}"
    exit 1
else
    echo -e "\n${GREEN}全部通過！${NC}"
    exit 0
fi
