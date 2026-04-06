#!/bin/bash

# Toggle wlogout — dismiss if already open, otherwise launch as centered vertical list
pkill -x wlogout && exit 0

if [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ] || [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    read -r W H < <(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width / .scale | floor) \(.height / .scale | floor)"')
elif [ "$XDG_CURRENT_DESKTOP" = "niri" ] || pgrep -x "niri" > /dev/null; then
    read -r W H < <(niri msg -j focused-output 2>/dev/null | jq -r '"\(.logical.width | floor) \(.logical.height | floor)"')
fi

W=${W:-2560}
H=${H:-1440}

LIST_W=420
LIST_H=400

LR=$(( (W - LIST_W) / 2 ))
TB=$(( (H - LIST_H) / 2 ))

exec wlogout -b 1 -n -s \
    -L "$LR" -R "$LR" \
    -T "$TB" -B "$TB" \
    -r 8
