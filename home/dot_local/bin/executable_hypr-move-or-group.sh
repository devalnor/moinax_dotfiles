#!/bin/bash
# Replicates the old hyprlang `movewindoworgroup` dispatcher, which Hyprland
# 0.55's Lua API no longer ships as a single primitive:
#   - if the active window is in a group: move OUT of the group in <dir>
#   - otherwise: move INTO the adjacent group in <dir>
#     (no-op if there is no group in that direction)
#
# Must be invoked via `hl.exec_cmd` (async child) — NEVER via `io.popen` from
# within a Lua bind callback, which would deadlock Hyprland (the compositor
# blocks on read while hyprctl is waiting on Hyprland's IPC socket).
#
# Usage: hypr-move-or-group.sh <l|r|u|d>

set -e

dir="$1"
case "$dir" in
    l|r|u|d) ;;
    *) echo "usage: $0 <l|r|u|d>" >&2; exit 2 ;;
esac

in_group=$(hyprctl activewindow -j | jq -r '(.grouped // []) | length > 1')

if [ "$in_group" = "true" ]; then
    hyprctl dispatch "hl.dsp.window.move({ out_of_group = \"$dir\" })"
else
    hyprctl dispatch "hl.dsp.window.move({ into_group = \"$dir\" })"
fi
