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
    jq \
    zstd \
    bats

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

# 7. 設定 Git pre-commit hook（自動更新 README）
echo ""
echo "🔗 設定 Git pre-commit hook..."
cat > "$DOTFILES/.git/hooks/pre-commit" << 'EOF'
#!/bin/bash
# pre-commit hook - 自動更新 README.md 目錄結構

~/dotfiles/scripts/update-readme.sh
git add README.md
EOF
chmod +x "$DOTFILES/.git/hooks/pre-commit"

# 8. 安裝 Ollama（用於 safe-check.sh）
echo ""
echo "🦙 安裝 Ollama..."
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
    echo "📥 下載 qwen2.5-coder:1.5b 模型..."
    ollama pull qwen2.5-coder:1.5b
else
    echo "  Ollama 已安裝，跳過"
fi

# 9. 安裝測試依賴
echo ""
echo "🧪 安裝測試依賴..."
pip install -r "$DOTFILES/requirements-dev.txt" 2>/dev/null || \
    pip3 install -r "$DOTFILES/requirements-dev.txt" 2>/dev/null || \
    echo "  ⚠️  pip 未安裝，請手動執行: pip install -r requirements-dev.txt"

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
