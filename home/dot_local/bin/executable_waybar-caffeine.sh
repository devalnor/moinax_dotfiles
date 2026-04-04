#!/bin/bash

# Waybar custom module: caffeine status (JSON output)
# Checks if wayland-idle-inhibitor is running (compositor-agnostic)

INHIBITOR="$HOME/.local/bin/wayland-idle-inhibitor.py"

ICON_SLEEP=$(printf '\U000f04b2')
ICON_COFFEE=$(printf '\uf0f4')

if pgrep -f "$INHIBITOR" &>/dev/null; then
    printf '{"text": "%s", "class": "activated", "tooltip": "Caffeine ON (idle inhibited)"}\n' "$ICON_COFFEE"
else
    printf '{"text": "%s", "class": "deactivated", "tooltip": "Caffeine OFF (idle active)"}\n' "$ICON_SLEEP"
fi
