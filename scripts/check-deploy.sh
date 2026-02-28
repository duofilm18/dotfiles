#!/bin/bash
# check-deploy.sh - Stop hook: 檢查所有 target 是否有未部署的改動
#
# 泛化版 check-rpi5b-deploy.sh，支援多個部署目標。
# 每個 target 定義：pattern（git diff 過濾）、marker、部署指令。
#
# Deploy marker 由各 playbook 的 post_tasks 寫入：
#   WSL:   ~/.cache/wsl-last-deploy    ← ansible/wsl.yml
#   RPi5B: ~/.cache/rpi5b-last-deploy  ← ansible/rpi5b.yml

set -euo pipefail

DOTFILES="${HOME}/dotfiles"

cd "$DOTFILES" 2>/dev/null || exit 0

# ── 共用函數 ──

check_target() {
    local name="$1"
    local pattern="$2"
    local marker="$3"
    local deploy_cmd="$4"

    local uncommitted staged undeployed

    # 1. 未 commit 的改動
    uncommitted=$(git diff --name-only 2>/dev/null | grep -E "$pattern" || true)
    staged=$(git diff --cached --name-only 2>/dev/null | grep -E "$pattern" || true)

    # 2. 已 commit 但未部署的改動
    if [ -f "$marker" ]; then
        local last_hash
        last_hash=$(cat "$marker")
        if git cat-file -t "$last_hash" &>/dev/null; then
            undeployed=$(git log --name-only --format="" "${last_hash}..HEAD" 2>/dev/null \
                | grep -E "$pattern" | sort -u || true)
        else
            # marker 失效，檢查最近 10 個 commit
            undeployed=$(git log --name-only --format="" -10 2>/dev/null \
                | grep -E "$pattern" | sort -u || true)
        fi
    else
        # 從未部署過，檢查最近 5 個 commit
        undeployed=$(git log --name-only --format="" -5 2>/dev/null \
            | grep -E "$pattern" | sort -u || true)
    fi

    # 有任何未部署的改動就輸出警告
    if [ -n "$uncommitted" ] || [ -n "$staged" ] || [ -n "$undeployed" ]; then
        echo "⚠️ ${name} 有改動尚未部署："
        [ -n "$uncommitted" ] && echo "$uncommitted" | sed 's/^/  [uncommitted] /'
        [ -n "$staged" ] && echo "$staged" | sed 's/^/  [staged] /'
        [ -n "$undeployed" ] && echo "$undeployed" | sed 's/^/  [undeployed] /'
        echo ""
        echo "→ 部署指令: $deploy_cmd"
        echo ""
    fi
}

# ── 各 target 定義 ──

check_target "RPi5B" \
    "^(rpi5b/|ansible/roles/rpi_)" \
    "${HOME}/.cache/rpi5b-last-deploy" \
    "cd ~/dotfiles/ansible && ansible-playbook rpi5b.yml --tags mqtt"

check_target "WSL" \
    "^(ansible/roles/(wsl|common)/|shared/)" \
    "${HOME}/.cache/wsl-last-deploy" \
    "cd ~/dotfiles/ansible && ansible-playbook wsl.yml"
