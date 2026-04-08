#!/bin/bash

# Dark/Light mode dispatcher
# Usage: apply-dark-mode.sh [dark|light]
# If no argument given, reads from state file (defaults to dark)

STATE_FILE="$HOME/.local/share/dark-light-mode"

# Determine mode
if [ -n "$1" ]; then
    MODE="$1"
else
    MODE=$(cat "$STATE_FILE" 2>/dev/null || echo "dark")
fi

# Validate
if [ "$MODE" != "dark" ] && [ "$MODE" != "light" ]; then
    echo "Usage: apply-dark-mode.sh [dark|light]" >&2
    exit 1
fi

# Map mode to catppuccin flavor
if [ "$MODE" = "dark" ]; then
    FLAVOR="mocha"
else
    FLAVOR="latte"
fi

# 1. Write state
mkdir -p "$(dirname "$STATE_FILE")"
echo "$MODE" > "$STATE_FILE"

# 2. Update chezmoi config so chezmoi diff stays clean for templated files
CHEZMOI_CONF="$HOME/.config/chezmoi/chezmoi.toml"
if [ -f "$CHEZMOI_CONF" ]; then
    if grep -q 'dark_mode = ' "$CHEZMOI_CONF"; then
        sed -i 's/dark_mode = .*/dark_mode = "'"$MODE"'"/' "$CHEZMOI_CONF"
    else
        sed -i '/^\[data\]/a\    dark_mode = "'"$MODE"'"' "$CHEZMOI_CONF"
    fi
fi

# 3. Portal color-scheme (tells browsers prefers-color-scheme via xdg-desktop-portal)
# Each portal backend monitors its own settings store; write to the correct one.
if [ "$MODE" = "dark" ]; then
    GNOME_SCHEME='prefer-dark'
else
    GNOME_SCHEME='prefer-light'
fi

# 3a. GTK/GNOME portal backend — monitors dconf
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface color-scheme "$GNOME_SCHEME" 2>/dev/null || true
elif command -v dconf &>/dev/null; then
    dconf write /org/gnome/desktop/interface/color-scheme "'$GNOME_SCHEME'" 2>/dev/null || true
fi

# 3b. KDE portal backend — monitors kdeglobals
if command -v plasma-apply-colorscheme &>/dev/null; then
    if [ "$MODE" = "dark" ]; then
        plasma-apply-colorscheme BreezeDark 2>/dev/null || true
    else
        plasma-apply-colorscheme BreezeLight 2>/dev/null || true
    fi
fi

# 4. Kitty
KITTY_THEME_SRC="$HOME/.config/kitty/themes/${MODE}.conf"
if [ -f "$KITTY_THEME_SRC" ]; then
    cp "$KITTY_THEME_SRC" "$HOME/.config/kitty/current-theme.conf"
    pkill -SIGUSR1 -x kitty 2>/dev/null || true
fi

# 5-6. Starship & Yazi — handled by chezmoi apply in step 14

# 7. Eza
EZA_THEME_SRC="$HOME/.config/eza/theme-${MODE}.yml"
if [ -f "$EZA_THEME_SRC" ]; then
    cp "$EZA_THEME_SRC" "$HOME/.config/eza/theme.yml"
fi

# 8. SwayNC
SWAYNC_SRC="$HOME/.config/swaync/style-${MODE}.css"
if [ -f "$SWAYNC_SRC" ]; then
    cp "$SWAYNC_SRC" "$HOME/.config/swaync/style.css"
    if pgrep -x swaync &>/dev/null; then
        swaync-client -rs 2>/dev/null || true
    fi
fi

# 9. Rofi
ROFI_SRC="$HOME/.local/share/rofi/themes/moinax-${MODE}.rasi"
if [ -f "$ROFI_SRC" ]; then
    cp "$ROFI_SRC" "$HOME/.local/share/rofi/themes/moinax.rasi"
fi

# 10. Wlogout
WLOGOUT_SRC="$HOME/.config/wlogout/style-${MODE}.css"
if [ -f "$WLOGOUT_SRC" ]; then
    cp "$WLOGOUT_SRC" "$HOME/.config/wlogout/style.css"
fi

# 11. Waybar CSS
WAYBAR_CSS_SRC="$HOME/.config/waybar/style-${MODE}.css"
if [ -f "$WAYBAR_CSS_SRC" ]; then
    cp "$WAYBAR_CSS_SRC" "$HOME/.config/waybar/style.css"
fi

# 12. Compositor borders
if pgrep -xi hyprland &>/dev/null; then
    if [ "$MODE" = "dark" ]; then
        hyprctl keyword general:col.active_border "rgba(ff64ff80) rgba(9696ffff) 45deg" 2>/dev/null || true
        hyprctl keyword general:col.inactive_border "rgba(6464ff4d)" 2>/dev/null || true
    else
        hyprctl keyword general:col.active_border "rgba(8839efcc) rgba(1e66f5cc) 45deg" 2>/dev/null || true
        hyprctl keyword general:col.inactive_border "rgba(7287fd4d)" 2>/dev/null || true
    fi
elif pgrep -xi niri &>/dev/null; then
    # Niri border colors handled by chezmoi apply in step 14; just reload
    niri msg action load-config-file 2>/dev/null || true
fi

# 13. Neovim
NVIM_THEME_FILE="$HOME/.local/share/nvim-theme"
echo "$FLAVOR" > "$NVIM_THEME_FILE"
# Best-effort remote send to running nvim instances
for addr in /run/user/$(id -u)/nvim.*.0 /tmp/nvim.*/0; do
    [ -S "$addr" ] || continue
    nvim --server "$addr" --remote-send "<Cmd>lua local c = require('catppuccin'); c.options.flavour = '${FLAVOR}'; c.compile(); vim.cmd.colorscheme('catppuccin')<CR>" 2>/dev/null || true
done

# 14. Apply chezmoi for all dark_mode-templated config files
if command -v chezmoi &>/dev/null; then
    chezmoi apply \
        ~/.gitconfig \
        ~/.config/gh-dash/config.yml \
        ~/.config/starship.toml \
        ~/.config/yazi/theme.toml \
        ~/.config/niri/config.kdl \
        2>/dev/null || true
fi

# 15. Waybar restart (skipped when called from installer)
if [ "$APPLY_DARK_MODE_NO_RESTART" != "1" ]; then
    if [ -x "$HOME/.config/hypr/scripts/reload-waybar.sh" ]; then
        "$HOME/.config/hypr/scripts/reload-waybar.sh"
    fi
fi
