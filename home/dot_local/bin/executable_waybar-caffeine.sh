#!/bin/bash

# Waybar custom module: caffeine status (continuous JSON output)
# Watches /tmp/caffeine-state via inotifywait and emits new JSON on change.
# Waybar runs this as a long-lived process (continuous exec mode).

STATE_FILE="/tmp/caffeine-state"
ICON_SLEEP=$(printf '\U000f04b2')
ICON_COFFEE=$(printf '\uf0f4')

emit_status() {
    if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "on" ]; then
        printf '{"text": "%s", "class": "activated", "tooltip": "Caffeine ON (idle inhibited)"}\n' "$ICON_COFFEE"
    else
        printf '{"text": "%s", "class": "deactivated", "tooltip": "Caffeine OFF (idle active)"}\n' "$ICON_SLEEP"
    fi
}

# Ensure state file exists with current state
[ -f "$STATE_FILE" ] || echo off > "$STATE_FILE"

# Emit initial state
emit_status

# Watch for state file writes and re-emit
while inotifywait -qq -e close_write "$STATE_FILE" 2>/dev/null; do
    emit_status
done
