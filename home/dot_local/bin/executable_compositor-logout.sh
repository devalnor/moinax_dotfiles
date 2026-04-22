#!/bin/bash

. "$HOME/.local/lib/compositor.sh"

if is_hyprland; then
    hyprctl dispatch exit
elif is_niri; then
    niri msg action quit
else
    loginctl terminate-session "${XDG_SESSION_ID}"
fi
