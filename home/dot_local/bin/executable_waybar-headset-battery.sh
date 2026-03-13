#!/bin/bash

# Waybar custom module: Headset battery status (JSON output)
# Requires: headsetcontrol, jq

if ! command -v headsetcontrol &>/dev/null; then
    exit 0
fi

JSON=$(headsetcontrol -o json 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$JSON" ]; then
    exit 0
fi

STATUS=$(echo "$JSON" | jq -r '.devices[0].battery.status // empty')
LEVEL=$(echo "$JSON" | jq -r '.devices[0].battery.level // empty')
DEVICE=$(echo "$JSON" | jq -r '.devices[0].device // "Headset"')

ICON=$(printf '\U000f02ce') # 󰋎 headset (with mic boom)

case "$STATUS" in
    BATTERY_AVAILABLE)
        if [ "$LEVEL" -ge 75 ]; then
            CLASS="good"
        elif [ "$LEVEL" -ge 30 ]; then
            CLASS="warning"
        else
            CLASS="critical"
        fi
        printf '{"text": "%s %s%%", "class": "%s", "tooltip": "%s: %s%%"}\n' \
            "$ICON" "$LEVEL" "$CLASS" "$DEVICE" "$LEVEL"
        ;;
    BATTERY_CHARGING)
        printf '{"text": "%s", "class": "charging", "tooltip": "%s: Charging"}\n' \
            "$ICON" "$DEVICE"
        ;;
    *)
        # Headset off or unavailable — output nothing so module hides
        echo '{"text": "", "class": "disconnected"}'
        ;;
esac
