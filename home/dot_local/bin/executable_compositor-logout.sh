#!/bin/bash
set -e

# Terminate the graphical session via logind. Compositor-agnostic and works
# across Hyprland 0.54/0.55 (where `hyprctl dispatch exit` is now parsed as
# Lua and the bare `exit` identifier doesn't resolve), niri, etc.
loginctl terminate-session "${XDG_SESSION_ID}"
