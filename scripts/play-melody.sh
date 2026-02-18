#!/bin/bash
# play-melody.sh - 在 HP 電腦喇叭播放旋律（透過 PowerShell）
# 用法: play-melody.sh <melody_name>
#
# 旋律移植自 https://github.com/alonw0/claude-monitor-esp32/src/melodies.py
# 完整 23 首旋律，1:1 對齊原版頻率與時值

MELODY="$1"

if [ -z "$MELODY" ]; then
    exit 0
fi

# 通用播放函式：接收 "freq,dur freq,dur ..." 格式
play() {
    local ps_cmds=""
    for note in $1; do
        local freq="${note%,*}"
        local dur="${note#*,}"
        if [ "$freq" -eq 0 ]; then
            ps_cmds+="Start-Sleep -Milliseconds $dur; "
        else
            ps_cmds+="[console]::Beep($freq,$dur); "
        fi
    done
    powershell.exe -c "$ps_cmds" 2>/dev/null
}

case "$MELODY" in
    # === Classic Themes ===
    super_mario)
        play "659,150 659,150 0,150 659,150 0,150 523,150 659,150 0,150 784,150 0,450 392,150 0,450"
        ;;
    star_wars)
        play "440,500 440,500 440,500 349,350 523,150 440,500 349,350 523,150 440,650 0,150 659,500 659,500 659,500 698,350 523,150"
        ;;
    nokia)
        play "659,125 587,125 370,250 415,250 554,125 494,125 294,250 330,250 494,125 440,125 277,250 330,250 440,500"
        ;;
    tetris)
        play "659,400 494,200 523,200 587,400 523,200 494,200 440,400 440,200 523,200 659,400 587,200 523,200 494,600 523,200 587,400 659,400"
        ;;
    zelda_secret)
        play "784,135 740,135 622,135 440,135 415,135 659,135 831,135 1047,450"
        ;;
    pacman)
        play "494,250 988,250 740,250 622,250 988,125 740,125 622,250 523,250 1047,250 784,250 659,250 1047,125 784,125 659,250"
        ;;
    mission_impossible)
        play "587,250 622,250 587,250 622,250 587,250 622,250 587,250 622,250 587,500 0,250 587,250 587,250 698,250 740,250 784,500"
        ;;
    pink_panther)
        play "0,250 311,250 330,375 0,125 370,250 392,375 0,125 311,250 0,250 311,125 0,125 311,125 0,125 311,125 0,125 311,125"
        ;;
    jingle_bells)
        play "659,250 659,250 659,500 659,250 659,250 659,500 659,250 784,250 523,250 587,250 659,1000"
        ;;
    happy_birthday)
        play "262,250 262,125 294,375 262,375 349,375 330,750 262,250 262,125 294,375 262,375 392,375 349,750"
        ;;
    windows_xp)
        play "311,400 392,450 466,500 622,650"
        ;;

    # === Default Melodies ===
    default_waiting)
        play "440,180 523,180 659,180 523,180 440,220 392,260"
        ;;
    default_error)
        play "200,300 0,50 200,300"
        ;;
    default_completed)
        play "523,100 0,50 659,100 0,50 784,150"
        ;;
    default_running)
        play "1000,150"
        ;;

    # === Short Variations ===
    short_success)
        play "523,100 659,100 784,150"
        ;;
    short_error)
        play "200,200 0,50 200,200"
        ;;
    short_waiting)
        play "440,150 523,150 659,150"
        ;;
    short_running)
        play "880,100 1000,100"
        ;;

    # === Minimal Variations ===
    minimal_beep)
        play "1000,100"
        ;;
    minimal_double)
        play "800,80 0,40 800,80"
        ;;
    minimal_triple)
        play "600,60 0,30 600,60 0,30 600,60"
        ;;

    *)
        play "800,200"
        ;;
esac

exit 0
