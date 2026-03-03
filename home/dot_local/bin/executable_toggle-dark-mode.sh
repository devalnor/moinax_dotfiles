#!/bin/bash
set -e

# Toggle between dark and light mode

# Prevent overlapping runs when key is pressed rapidly
LOCK_FILE="/tmp/toggle-dark-mode.lock"
if [ -f "$LOCK_FILE" ]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null)
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

STATE_FILE="$HOME/.local/share/dark-light-mode"
CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "dark")

if [ "$CURRENT" = "dark" ]; then
    ~/.local/bin/apply-dark-mode.sh light
else
    ~/.local/bin/apply-dark-mode.sh dark
fi
