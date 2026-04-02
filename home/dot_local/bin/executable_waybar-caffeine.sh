#!/bin/bash

# Waybar custom module: caffeine status (JSON output)
# Icons match the existing idle_inhibitor module

if pgrep -xi hyprland &>/dev/null; then
    DAEMON="hypridle"
elif pgrep -xi niri &>/dev/null; then
    DAEMON="swayidle"
else
    printf '{"text": "%s", "class": "deactivated", "tooltip": "Unknown compositor"}\n' "$(printf '\U000f04b2')"
    exit 0
fi

ICON_SLEEP=$(printf '\U000f04b2')
ICON_COFFEE=$(printf '\uf0f4')

if pgrep -x "$DAEMON" &>/dev/null; then
    printf '{"text": "%s", "class": "deactivated", "tooltip": "Caffeine OFF (idle active)"}\n' "$ICON_SLEEP"
else
    printf '{"text": "%s", "class": "activated", "tooltip": "Caffeine ON (idle inhibited)"}\n' "$ICON_COFFEE"
fi
