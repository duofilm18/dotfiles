# .bash_aliases - WSL 常用別名

# 基本導航
alias h='cd ~'
alias c='clear'
alias ..='cd ..'
alias ...='cd ../..'

# 常用指令
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias hosts='sudo vim /etc/hosts'
alias sb='source ~/.bashrc'

# Python
alias python=python3
alias pip=pip3

# Tmux
alias ta='tmux attach -t'
alias tl='tmux list-sessions'
alias tk='tmux kill-session -t'
alias tka='tmux kill-session -a'  # 殺掉所有 session

# Git 快捷（帶音效）
alias gs='git status'
alias gl='git lg'

ga() {
    git add "$@"
    local rc=$?
    if [ $rc -eq 0 ]; then
        setsid ~/dotfiles/scripts/play-melody.sh minimal_beep &>/dev/null &
        disown
    fi
    return $rc
}

gc() {
    git commit "$@"
    local rc=$?
    if [ $rc -eq 0 ]; then
        setsid ~/dotfiles/scripts/play-melody.sh short_success &>/dev/null &
        disown
    fi
    return $rc
}

gp() {
    git push "$@"
    local rc=$?
    if [ $rc -eq 0 ]; then
        setsid ~/dotfiles/scripts/play-melody.sh windows_xp &>/dev/null &
        disown
    fi
    return $rc
}

# Docker
alias dc='docker compose'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dps='docker ps'

# 安全檢查
alias safe='~/dotfiles/scripts/safe-check.sh'

# WSL 專用：複製到 Windows 剪貼板
alias clip='clip.exe'
