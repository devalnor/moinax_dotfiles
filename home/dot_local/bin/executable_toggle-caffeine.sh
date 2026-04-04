#!/bin/bash
set -e

# Toggle caffeine mode: start/stop a Wayland idle inhibitor
# The idle daemon (hypridle/swayidle) stays running so that
# loginctl lock-session always works, even with caffeine ON.

INHIBITOR="wayland-idle-inhibitor.py"
INHIBITOR_PATH=$(command -v "$INHIBITOR" 2>/dev/null) || {
    notify-send -u critical "Caffeine" "$INHIBITOR not found — install wayland-idle-inhibitor-git (AUR)"
    exit 1
}

if pgrep -f "$INHIBITOR_PATH" &>/dev/null; then
    pkill -f "$INHIBITOR_PATH" || true
    notify-send -u low "Caffeine" "OFF — idle resumed"
else
    nohup "$INHIBITOR_PATH" &>/dev/null & disown
    notify-send -u low "Caffeine" "ON — idle inhibited"
fi

pkill -RTMIN+10 waybar || true
