#!/bin/bash

# Waybar custom module: Tailscale VPN status (JSON output)

ICON_ON=$(printf '\U000f05a2')
ICON_OFF=$(printf '\U000f05a3')

if tailscale status &>/dev/null; then
    # Extract hostname and IP from first line of tailscale status
    INFO=$(tailscale status | head -1)
    IP=$(echo "$INFO" | awk '{print $1}')
    HOST=$(echo "$INFO" | awk '{print $2}')
    printf '{"text": "%s", "class": "connected", "tooltip": "Tailscale: %s (%s)"}\n' "$ICON_ON" "$HOST" "$IP"
else
    printf '{"text": "%s", "class": "disconnected", "tooltip": "Tailscale disconnected"}\n' "$ICON_OFF"
fi
