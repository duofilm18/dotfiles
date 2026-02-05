#!/bin/bash
# install.sh - 一鍵設置開發環境
# 用法: ~/dotfiles/scripts/install.sh

set -e  # 遇到錯誤就停止

DOTFILES="$HOME/dotfiles"

echo "=========================================="
echo "  開始設置開發環境"
echo "=========================================="

# 檢查 dotfiles 目錄
if [ ! -d "$DOTFILES" ]; then
    echo "❌ 找不到 $DOTFILES，請先 clone dotfiles repo"
    exit 1
fi

# 1. 安裝基本工具
echo ""
echo "📦 安裝基本工具..."
sudo apt update -y
sudo apt install -y \
    git \
    vim \
    tmux \
    curl \
    build-essential \
    jq

# 2. 設定 Git
echo ""
echo "🔧 設定 Git..."
git config --global user.name "duofilm18"
git config --global user.email "duofilm18@gmail.com"
git config --global core.editor "vim"
git config --global credential.helper 'cache --timeout 86400'
# 別名
git config --global alias.co checkout
git config --global alias.ci commit
git config --global alias.st status
git config --global alias.br branch
git config --global alias.lg "log --graph --pretty=format:'%Cred%h - %Cgreen[%an]%Creset -%C(yellow)%d%Creset %s %C(yellow)<%cr>%Creset' --abbrev-commit --date=relative"

# 3. 設定 Vim
echo ""
echo "📝 設定 Vim..."
ln -sf "$DOTFILES/shared/.vimrc" ~/.vimrc
# 安裝 vim-plug
if [ ! -f ~/.vim/autoload/plug.vim ]; then
    curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    echo "  執行 vim +PlugInstall +qall 安裝插件"
fi

# 4. 設定 Tmux
echo ""
echo "🖥️  設定 Tmux..."
ln -sf "$DOTFILES/shared/.tmux.conf" ~/.tmux.conf
# 安裝 TPM
if [ ! -d ~/.tmux/plugins/tpm ]; then
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
    echo "  進入 tmux 後按 prefix + I 安裝插件"
fi

# 5. 設定 Bash aliases
echo ""
echo "⚡ 設定 Bash aliases..."
ln -sf "$DOTFILES/wsl/.bash_aliases" ~/.bash_aliases

# 確保 .bashrc 會載入 .bash_aliases
if ! grep -q "bash_aliases" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Load custom aliases" >> ~/.bashrc
    echo "[ -f ~/.bash_aliases ] && . ~/.bash_aliases" >> ~/.bashrc
fi

# 6. 設定腳本執行權限
chmod +x "$DOTFILES/scripts/"*.sh

echo ""
echo "=========================================="
echo "  ✅ 設置完成！"
echo "=========================================="
echo ""
echo "下一步："
echo "  1. source ~/.bashrc     # 載入新設定"
echo "  2. vim +PlugInstall     # 安裝 vim 插件"
echo "  3. tmux → prefix + I    # 安裝 tmux 插件"
echo ""
