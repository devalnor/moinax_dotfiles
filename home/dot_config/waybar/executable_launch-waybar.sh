#!/bin/bash
# Waybar launcher script that detects the compositor and uses the appropriate config

# Detect which compositor is running
if [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ]; then
    COMPOSITOR="hyprland"
elif pgrep -x "niri" > /dev/null; then
    COMPOSITOR="niri"
else
    # Fallback: try to detect from environment
    if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
        COMPOSITOR="hyprland"
    else
        COMPOSITOR="niri"  # Default fallback
    fi
fi

# Launch Waybar with compositor-specific config
CONFIG_FILE="$HOME/.config/waybar/config-${COMPOSITOR}"

if [ -f "$CONFIG_FILE" ]; then
    exec waybar -c "$CONFIG_FILE"
else
    # Fallback to default config if specific one doesn't exist
    exec waybar
fi
