#!/bin/bash
set -e

# Copy notification body text to clipboard
# Called by SwayNC's script system with the notification body as $1

BODY="$1"

if [ -z "$BODY" ]; then
    exit 0
fi

echo -n "$BODY" | wl-copy

notify-send -u low -t 2000 -a "swaync-copy" "Copied" "Notification text copied to clipboard"
