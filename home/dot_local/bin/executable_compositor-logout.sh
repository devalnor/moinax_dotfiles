#!/bin/bash
set -e

# Cleanly quit the running Wayland compositor. Each compositor needs its native
# quit verb so it releases its DRM/seat resources before the session is torn
# down — terminating the systemd session first leaves the compositor alive but
# without GPU access, which manifests as a black screen looping on
# "Page flip commit failed (Permission denied)".

if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && command -v hyprctl &>/dev/null; then
    # Hyprland 0.55+ parses dispatch args as Lua; pass an empty string to force
    # the legacy parser so `exit` is treated as the dispatcher name, not an
    # unresolved identifier.
    exec hyprctl dispatch exit ""
fi

if [ -n "$NIRI_SOCKET" ] && command -v niri &>/dev/null; then
    exec niri msg action quit --skip-confirmation
fi

# Fallback for unknown compositors — terminate the logind session so seatd
# revokes the device leases. The compositor will die when its session goes.
exec loginctl terminate-session "${XDG_SESSION_ID}"
