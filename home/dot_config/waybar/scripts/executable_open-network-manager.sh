#!/usr/bin/env bash
set -euo pipefail

# Prefer a KDE GUI if available, then generic NetworkManager GUI, then TUI.
if command -v kcmshell6 >/dev/null 2>&1; then
    exec kcmshell6 kcm_networkmanagement
fi

if command -v kcmshell5 >/dev/null 2>&1; then
    exec kcmshell5 kcm_networkmanagement
fi

if command -v nm-connection-editor >/dev/null 2>&1; then
    exec nm-connection-editor
fi

if command -v kitty >/dev/null 2>&1 && command -v nmtui >/dev/null 2>&1; then
    exec kitty nmtui
fi

notify-send "Network settings" "No network configuration UI found"
