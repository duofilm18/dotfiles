#!/bin/bash
# check-rpi5b-deploy.sh - Stop hook: 檢查 rpi5b/ 是否有未部署的改動
#
# 機制：
#   1. 檢查 uncommitted 改動（git diff）
#   2. 檢查 committed 但未部署的改動（比對 deploy marker）
#
# Deploy marker: ~/.cache/rpi5b-last-deploy
#   由 ansible/rpi5b.yml post_tasks 寫入，存最後一次部署的 commit hash

set -euo pipefail

DOTFILES="${HOME}/dotfiles"
MARKER="${HOME}/.cache/rpi5b-last-deploy"

cd "$DOTFILES" 2>/dev/null || exit 0

# 1. 未 commit 的改動
uncommitted=$(git diff --name-only 2>/dev/null | grep '^rpi5b/' || true)
staged=$(git diff --cached --name-only 2>/dev/null | grep '^rpi5b/' || true)

# 2. 已 commit 但未部署的改動
if [ -f "$MARKER" ]; then
    last_hash=$(cat "$MARKER")
    # 確認 hash 有效（可能因 reset 失效）
    if git cat-file -t "$last_hash" &>/dev/null; then
        undeployed=$(git log --name-only --format="" "${last_hash}..HEAD" 2>/dev/null \
            | grep '^rpi5b/' | sort -u || true)
    else
        # marker 失效，檢查最近 10 個 commit
        undeployed=$(git log --name-only --format="" -10 2>/dev/null \
            | grep '^rpi5b/' | sort -u || true)
    fi
else
    # 從未部署過，檢查最近 5 個 commit
    undeployed=$(git log --name-only --format="" -5 2>/dev/null \
        | grep '^rpi5b/' | sort -u || true)
fi

# 有任何未部署的改動就輸出警告
if [ -n "$uncommitted" ] || [ -n "$staged" ] || [ -n "$undeployed" ]; then
    echo "⚠️ rpi5b/ 有改動尚未部署到 RPi5B："
    [ -n "$uncommitted" ] && echo "$uncommitted" | sed 's/^/  [uncommitted] /'
    [ -n "$staged" ] && echo "$staged" | sed 's/^/  [staged] /'
    [ -n "$undeployed" ] && echo "$undeployed" | sed 's/^/  [undeployed] /'
    echo ""
    echo "→ 部署指令: cd ~/dotfiles/ansible && ansible-playbook rpi5b.yml --tags mqtt"
fi
