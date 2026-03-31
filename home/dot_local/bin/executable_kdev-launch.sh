#!/bin/bash
# Launch kitty with the dev splits layout (1 top, 2 bottom) in $HOME.
# Called from compositor keybindings (Hyprland, Niri).
exec kitty --session ~/.config/kitty/dev-layout.session --directory "$HOME"
