#!/bin/bash

# Toggle caffeine mode: prevent the session from going idle (lock/dpms/suspend).
#
# Strategy differs per compositor:
#   - Hyprland: start a wl_surface-backed idle inhibitor; Hyprland honors it
#     even when the surface is unmapped, so hypridle stops receiving idle events.
#   - Niri: follows the idle-inhibit spec strictly and ignores inhibitors on
#     unmapped surfaces, so the same trick is silently ineffective. Instead,
#     stop swayidle while caffeine is on and respawn it when turning off.

. "$HOME/.local/lib/compositor.sh"

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/caffeine-state"
INHIBITOR="$HOME/.local/bin/wayland-idle-inhibitor.py"

turn_on() {
    echo on > "$STATE_FILE"
    notify-send -u low "Caffeine" "ON — idle inhibited" || true
}

turn_off() {
    echo off > "$STATE_FILE"
    notify-send -u low "Caffeine" "OFF — idle resumed" || true
}

if is_hyprland; then
    if pgrep -f "$INHIBITOR" &>/dev/null; then
        pkill -f "$INHIBITOR" || true
        turn_off
    else
        nohup "$INHIBITOR" &>/dev/null & disown
        turn_on
    fi
elif is_niri; then
    if pgrep -x swayidle >/dev/null; then
        pkill -x swayidle || true
        turn_on
    else
        nohup swayidle -w &>/dev/null & disown
        turn_off
    fi
else
    notify-send -u critical "Caffeine" "Unsupported compositor: ${XDG_CURRENT_DESKTOP:-unknown}" || true
    exit 1
fi
