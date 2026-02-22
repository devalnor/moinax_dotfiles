#!/bin/bash
killall -9 waybar
~/.config/waybar/launch-waybar.sh &
notify-send -u low "Waybar" "Reloaded"
