#!/usr/bin/env bash
# Emoji picker wrapper around rofimoji.
# Uses --action copy so the emoji stays in the clipboard, then simulates
# Ctrl+V after a short delay to let focus return to the previous window.
set -e

rofimoji --action copy --clipboarder wl-copy

# Give the compositor time to return focus to the previous window
sleep 0.15
wtype -M ctrl v -m ctrl
