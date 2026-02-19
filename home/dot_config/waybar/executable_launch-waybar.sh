#!/bin/bash
# Waybar launcher script that detects the compositor and uses the appropriate config

# Wait for the compositor socket to be ready before launching
sleep 2

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
    echo "Error: Waybar config not found: $CONFIG_FILE" >&2
    echo "Run 'chezmoi apply' to generate compositor-specific configs." >&2
    exit 1
fi
