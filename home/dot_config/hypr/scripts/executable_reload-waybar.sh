#!/bin/bash
killall -9 waybar 2>/dev/null
~/.config/waybar/launch-waybar.sh &>/dev/null &
disown
notify-send -u low "Waybar" "Reloaded" 2>/dev/null || true
