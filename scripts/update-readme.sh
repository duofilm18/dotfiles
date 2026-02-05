#!/bin/bash
# update-readme.sh - 自動更新 README.md 目錄結構
# 用法: ~/dotfiles/scripts/update-readme.sh

set -e

DOTFILES="$HOME/dotfiles"
README="$DOTFILES/README.md"

echo "🔄 更新 README.md 目錄結構..."

# 生成樹狀目錄結構
generate_tree() {
    cd "$DOTFILES"

    cat << 'TREE'
dotfiles/
├── .claude/
│   └── skills/
│       └── add-hook.md
├── scripts/
TREE

    # scripts 目錄
    for f in scripts/*.sh; do
        echo "│   ├── $(basename "$f")"
    done | sed '$ s/├/└/'

    cat << 'TREE'
├── shared/
│   ├── .tmux.conf
│   └── .vimrc
├── wsl/
│   ├── .bash_aliases
│   └── claude-hooks.json.example
├── CLAUDE.md
└── README.md
TREE
}

TREE=$(generate_tree)

# 用 awk 替換 README 中 "## 目錄結構" 到下一個 "##" 之間的內容
awk -v tree="$TREE" '
/^## 目錄結構/ {
    print "## 目錄結構"
    print ""
    print "```"
    print tree
    print "```"
    print ""
    skip = 1
    next
}
/^## / && skip { skip = 0 }
!skip { print }
' "$README" > "$README.tmp" && mv "$README.tmp" "$README"

echo "✅ README.md 已更新"
