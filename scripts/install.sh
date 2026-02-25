#!/bin/bash
# install.sh - Bootstrap：安裝 Ansible 後執行 playbook
# 用法: ~/dotfiles/scripts/install.sh
set -e

DOTFILES="$HOME/dotfiles"

if [ ! -d "$DOTFILES" ]; then
    echo "❌ 找不到 $DOTFILES，請先 clone dotfiles repo"
    exit 1
fi

echo "📦 安裝 Ansible..."
sudo apt update -y
sudo apt install -y ansible

echo "🚀 執行 Ansible playbook..."
cd "$DOTFILES/ansible"
ansible-playbook wsl.yml

echo ""
echo "✅ WSL 環境設置完成！"
echo ""
echo "下一步："
echo "  1. source ~/.bashrc"
echo "  2. vim +PlugInstall     # 安裝 vim 插件"
echo "  3. tmux → prefix + I    # 安裝 tmux 插件"
echo "  4. Windows 側執行 windows\\install.ps1  # IME 指示器"
