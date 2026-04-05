#!/bin/bash

# Define the sink using wpctl's default
SINK="@DEFAULT_AUDIO_SINK@" # This is the wpctl default

# Get the action (up, down, mute) and amount
ACTION="$1"
AMOUNT="$2" # e.g., "5%" for volume up/down

# Function to get the current volume and mute status using wpctl
get_volume_info() {
    INFO=$(wpctl get-volume "$SINK")
    VOLUME_RAW=$(echo "$INFO" | awk '{print $2}')
    VOLUME=$(printf "%.0f" "$(echo "$VOLUME_RAW * 100" | bc)") # Convert 0.0-1.0 to 0-100%
    MUTE_STATUS=$(echo "$INFO" | grep -q "MUTED" && echo "yes" || echo "no")
    echo "$VOLUME $MUTE_STATUS"
}

# Apply the action
case "$ACTION" in
    up)
        # wpctl handles percentage directly
        wpctl set-volume "$SINK" "$AMOUNT"+
        ;;
    down)
        wpctl set-volume "$SINK" "$AMOUNT"-
        ;;
    mute)
        wpctl set-mute "$SINK" toggle
        ;;
    *)
        echo "Usage: $0 {up|down|mute} [amount]"
        exit 1
        ;;
esac

