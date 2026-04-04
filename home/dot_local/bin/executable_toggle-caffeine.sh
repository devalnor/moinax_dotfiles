#!/bin/bash
set -e

# Toggle caffeine mode: start/stop a Wayland idle inhibitor
# The idle daemon (hypridle/swayidle) stays running so that
# loginctl lock-session always works, even with caffeine ON.

INHIBITOR="$HOME/.local/bin/wayland-idle-inhibitor.py"

if pgrep -f "$INHIBITOR" &>/dev/null; then
    pkill -f "$INHIBITOR" || true
    notify-send -u low "Caffeine" "OFF — idle resumed"
else
    nohup "$INHIBITOR" &>/dev/null & disown
    notify-send -u low "Caffeine" "ON — idle inhibited"
fi

pkill -RTMIN+10 waybar || true
