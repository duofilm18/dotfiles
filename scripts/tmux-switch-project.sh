#!/bin/bash
# tmux-switch-project.sh - 切換到指定 @project 的 tmux window
# 用法: tmux-switch-project.sh <project_name>
# 供 Stream Deck 透過 wsl.exe 呼叫（外部無 tmux session context）

PROJECT="$1"
[ -z "$PROJECT" ] && exit 1

# 外部呼叫時需明確指定 session
SESSION=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1)
[ -z "$SESSION" ] && exit 1

idx=$(tmux list-windows -t "$SESSION" -F '#{window_index} #{@project}' \
    | grep " ${PROJECT}$" | head -1 | cut -d' ' -f1)

[ -n "$idx" ] && tmux select-window -t "${SESSION}:${idx}"
