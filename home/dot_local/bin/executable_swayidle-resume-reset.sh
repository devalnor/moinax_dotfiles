#!/bin/bash
set -e

# Restart swayidle after resume from sleep to reset idle timers.
# Without this, swayidle counts suspend time as idle time and
# immediately re-locks the session after the user unlocks.

gdbus monitor --system \
    --dest org.freedesktop.login1 \
    --object-path /org/freedesktop/login1 2>/dev/null |
while read -r line; do
    if [[ "$line" == *"PrepareForSleep"*"false"* ]]; then
        # Wait for user to unlock before restarting
        while pidof hyprlock > /dev/null 2>&1; do
            sleep 1
        done
        pkill -x swayidle 2>/dev/null || true
        sleep 0.5
        swayidle -w &
    fi
done
