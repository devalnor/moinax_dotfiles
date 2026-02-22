#!/bin/bash
killall hyprpaper
hyprpaper &
notify-send -u low "Hyprpaper" "Reloaded"
