#!/bin/bash
set -e

# Toggle OLED burn-in prevention overlay
# Launches a fullscreen semi-transparent cmatrix animation

KITTY_CMD="kitty --class oled-saver -o hide_window_decorations=yes cmatrix -a -b -u 2 -C blue"

if pgrep -f "kitty --class oled-saver" &>/dev/null; then
    pkill -f "kitty --class oled-saver"
    notify-send -u low "OLED Saver" "OFF"
else
    if pgrep -x Hyprland &>/dev/null; then
        # Get focused monitor effective size (resolution / scale)
        read -r W H < <(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width / .scale | floor) \(.height / .scale | floor)"')
        hyprctl dispatch exec "[float; size ${W} ${H}; move 0 0; pin; group barred]" -- $KITTY_CMD
    else
        nohup $KITTY_CMD &>/dev/null & disown
    fi
    notify-send -u low "OLED Saver" "ON — burn-in prevention active"
fi
