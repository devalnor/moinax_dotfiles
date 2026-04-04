#!/bin/bash
# Waybar notification module wrapper for SwayNC
# Shows only the bell icon when count is 0, bell + count otherwise

BELL=$'\U000f009a'

swaync-client -swb | while read -r line; do
    count=$(echo "$line" | sed 's/.*"text": *"\([^"]*\)".*/\1/')
    if [ "$count" = "0" ]; then
        echo "$line" | sed "s/\"text\": *\"[^\"]*\"/\"text\": \"$BELL\"/"
    else
        echo "$line" | sed "s/\"text\": *\"[^\"]*\"/\"text\": \"$BELL $count\"/"
    fi
done
