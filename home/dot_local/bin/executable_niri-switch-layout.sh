#!/bin/bash
# Cycle to next Niri keyboard layout and notify the user.

# Layout display names — must match order in niri config: be,fr,us
declare -A LAYOUT_NAMES=(
    [be]="Belgian (BE)"
    [fr]="French (FR)"
    [us]="English (US)"
)

# Switch to next layout
niri msg action switch-layout next

# Query new active layout via JSON IPC
layout_json=$(niri msg --json keyboard-layouts 2>/dev/null)

# Extract current index and layout list, then look up display name
if command -v jq &>/dev/null && [ -n "$layout_json" ]; then
    current_idx=$(echo "$layout_json" | jq -r '.. | objects | .current_idx? // empty' | head -1)
    # Layouts in config order: be,fr,us
    layouts=("be" "fr" "us")
    current_code="${layouts[$current_idx]:-}"
    name="${LAYOUT_NAMES[$current_code]:-$current_code}"
else
    name="Layout changed"
fi

[ -z "$name" ] && name="Layout changed"

notify-send -u low "Keyboard Layout" "Switched to: $name"
