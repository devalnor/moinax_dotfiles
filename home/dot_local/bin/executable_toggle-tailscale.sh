#!/bin/bash
set -e

# Toggle Tailscale VPN: connect or disconnect

if tailscale status &>/dev/null; then
    tailscale down
    notify-send -u low "Tailscale" "Disconnected"
else
    tailscale up
    notify-send -u low "Tailscale" "Connected"
fi

pkill -RTMIN+11 waybar || true
