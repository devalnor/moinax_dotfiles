#!/bin/bash
set -e

# Stop the graphical session gracefully so sddm-helper finishes with status 0
# and SDDM re-spawns the greeter. Under uwsm, `uwsm stop` walks
# graphical-session.target down in dependency order (stops user services
# first, then the compositor) — no broken-pipe SIGABRTs, no drkonqi cascade.
. "$HOME/.local/lib/compositor.sh"

if is_hyprland && command -v uwsm >/dev/null && uwsm check is-active >/dev/null 2>&1; then
    uwsm stop
elif is_hyprland; then
    # Hyprland 0.55+ parses `hyprctl dispatch` args as Lua, so a bare
    # `exit` identifier no longer resolves. Passing an empty second arg
    # forces the legacy parser, which both 0.55 (Arch) and <0.55 (Fedora)
    # accept — so this single call works across versions.
    hyprctl dispatch exit ""
elif is_niri; then
    niri msg action quit --skip-confirmation
else
    loginctl terminate-session "${XDG_SESSION_ID}"
fi
