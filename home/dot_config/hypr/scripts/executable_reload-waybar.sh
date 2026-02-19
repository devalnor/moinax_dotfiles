#!/bin/bash
killall -9 waybar
sleep 1
~/.config/waybar/launch-waybar.sh &
notify-send -u low "Waybar" "Reloaded"
