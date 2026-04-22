#!/bin/bash
# Print current keyboard layout code for waybar

. "$HOME/.local/lib/compositor.sh"

if is_niri; then
    layout_json=$(niri msg --json keyboard-layouts 2>/dev/null)
    if command -v jq &>/dev/null && [ -n "$layout_json" ]; then
        current_idx=$(echo "$layout_json" | jq -r '.. | objects | .current_idx? // empty' | head -1)
        layouts=("BE" "FR" "US")   # must match niri config order: be,fr,us
        echo "${layouts[$current_idx]:-??}"
    else
        echo "??"
    fi
elif is_hyprland; then
    layout=$(grep -oP '(?<=kb_layout = )\S+' \
        "$HOME/.config/hypr/conf/input.conf" 2>/dev/null | head -1)
    echo "${layout^^}"
else
    echo "??"
fi
