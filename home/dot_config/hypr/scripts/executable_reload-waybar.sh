#!/bin/bash
systemctl --user restart waybar.service
notify-send -u low "Waybar" "Reloaded" 2>/dev/null || true
