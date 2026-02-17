#!/bin/bash

if [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ] || [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    hyprctl dispatch exit
elif [ "$XDG_CURRENT_DESKTOP" = "niri" ] || pgrep -x "niri" > /dev/null; then
    niri msg action quit
else
    loginctl terminate-session "${XDG_SESSION_ID}"
fi
