#!/bin/bash
killall mako
mako &
notify-send -u low "Mako" "Reloaded"
