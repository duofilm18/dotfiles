#!/bin/bash
# tmux-switch-project.sh - 切換到指定 @project 的 tmux window
# 用法: tmux-switch-project.sh <project_name>
# 供 Stream Deck 透過 wsl.exe 呼叫（外部無 tmux session context）

PROJECT="$1"
[ -z "$PROJECT" ] && exit 1

TARGET=$(tmux list-windows -a -F '#{session_name}:#{window_index} #{@project}' 2>/dev/null \
    | grep " ${PROJECT}$" | head -1 | cut -d' ' -f1)

[ -n "$TARGET" ] && tmux select-window -t "$TARGET"
