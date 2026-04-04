#!/bin/bash

# Toggle caffeine mode: start/stop a Wayland idle inhibitor
# The idle daemon (hypridle/swayidle) stays running so that
# loginctl lock-session always works, even with caffeine ON.

INHIBITOR="$HOME/.local/bin/wayland-idle-inhibitor.py"
STATE_FILE="/tmp/caffeine-state"

if pgrep -f "$INHIBITOR" &>/dev/null; then
    pkill -f "$INHIBITOR" || true
    echo off > "$STATE_FILE"
    notify-send -u low "Caffeine" "OFF — idle resumed" || true
else
    nohup "$INHIBITOR" &>/dev/null & disown
    echo on > "$STATE_FILE"
    notify-send -u low "Caffeine" "ON — idle inhibited" || true
fi
