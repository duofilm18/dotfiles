#!/bin/bash
# 快速查看樹莓派溫度
TEMP=$(($(cat /sys/class/thermal/thermal_zone0/temp)/1000))
echo "${TEMP}°C"
