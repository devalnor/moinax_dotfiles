#!/bin/bash

# Dark/Light mode dispatcher
# Usage: apply-dark-mode.sh [dark|light]
# If no argument given, reads from state file (defaults to dark)
#
# Design: KDE/Qt is the canonical source of truth for dark/light mode.
# plasma-apply-colorscheme updates the system appearance, and this script only
# manages repo-local theme files in addition to that KDE scheme switch.

. "$HOME/.local/lib/compositor.sh"

STATE_FILE="$HOME/.local/share/dark-light-mode"

# Determine mode
if [ -n "$1" ]; then
    MODE="$1"
else
    MODE=$(cat "$STATE_FILE" 2>/dev/null || echo "dark")
fi

if [ "$MODE" != "dark" ] && [ "$MODE" != "light" ]; then
    echo "Usage: apply-dark-mode.sh [dark|light]" >&2
    exit 1
fi

FLAVOR=$( [ "$MODE" = "dark" ] && echo "mocha" || echo "latte" )
# ---------- State ----------

mkdir -p "$(dirname "$STATE_FILE")"
echo "$MODE" > "$STATE_FILE"

CHEZMOI_CONF="$HOME/.config/chezmoi/chezmoi.toml"
if [ -f "$CHEZMOI_CONF" ]; then
    if grep -q 'dark_mode = ' "$CHEZMOI_CONF"; then
        sed -i 's/dark_mode = .*/dark_mode = "'"$MODE"'"/' "$CHEZMOI_CONF"
    else
        sed -i '/^\[data\]/a\    dark_mode = "'"$MODE"'"' "$CHEZMOI_CONF"
    fi
fi

# ---------- KDE color scheme ----------
KDE_SCHEME=$( [ "$MODE" = "dark" ] && echo "BreezeDark" || echo "BreezeLight" )
if command -v plasma-apply-colorscheme &>/dev/null; then
    plasma-apply-colorscheme "$KDE_SCHEME" 2>/dev/null || true
fi

# ---------- GNOME color-scheme ----------
# Keep gsettings in sync so GTK/GNOME-aware apps reading
# org.gnome.desktop.interface color-scheme don't hold a stale value.
GNOME_SCHEME=$( [ "$MODE" = "dark" ] && echo "prefer-dark" || echo "prefer-light" )
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface color-scheme "$GNOME_SCHEME" 2>/dev/null || true
fi

# ---------- Kitty ----------
KITTY_THEME_SRC="$HOME/.config/kitty/themes/${MODE}.conf"
if [ -f "$KITTY_THEME_SRC" ]; then
    cp "$KITTY_THEME_SRC" "$HOME/.config/kitty/current-theme.conf"
    pkill -SIGUSR1 -x kitty 2>/dev/null || true
fi

# ---------- Eza ----------
EZA_THEME_SRC="$HOME/.config/eza/theme-${MODE}.yml"
if [ -f "$EZA_THEME_SRC" ]; then
    cp "$EZA_THEME_SRC" "$HOME/.config/eza/theme.yml"
fi

# ---------- SwayNC ----------
SWAYNC_SRC="$HOME/.config/swaync/style-${MODE}.css"
if [ -f "$SWAYNC_SRC" ]; then
    cp "$SWAYNC_SRC" "$HOME/.config/swaync/style.css"
    if pgrep -x swaync &>/dev/null; then
        swaync-client -rs 2>/dev/null || true
    fi
fi

# ---------- SwayOSD ----------
SWAYOSD_SRC="$HOME/.config/swayosd/style-${MODE}.css"
if [ -f "$SWAYOSD_SRC" ]; then
    cp "$SWAYOSD_SRC" "$HOME/.config/swayosd/style.css"
    if pgrep -x swayosd-server &>/dev/null; then
        pkill -x swayosd-server 2>/dev/null || true
        swayosd-server -s "$HOME/.config/swayosd/style.css" &disown
    fi
fi

# ---------- Rofi ----------
ROFI_SRC="$HOME/.local/share/rofi/themes/moinax-${MODE}.rasi"
if [ -f "$ROFI_SRC" ]; then
    cp "$ROFI_SRC" "$HOME/.local/share/rofi/themes/moinax.rasi"
fi

# ---------- Wlogout ----------
WLOGOUT_SRC="$HOME/.config/wlogout/style-${MODE}.css"
if [ -f "$WLOGOUT_SRC" ]; then
    cp "$WLOGOUT_SRC" "$HOME/.config/wlogout/style.css"
fi

# ---------- Waybar CSS ----------
WAYBAR_CSS_SRC="$HOME/.config/waybar/style-${MODE}.css"
if [ -f "$WAYBAR_CSS_SRC" ]; then
    cp "$WAYBAR_CSS_SRC" "$HOME/.config/waybar/style.css"
fi

# ---------- Compositor borders ----------
if is_hyprland; then
    if [ "$MODE" = "dark" ]; then
        hyprctl keyword general:col.active_border "rgba(ff64ff80) rgba(9696ffff) 45deg" 2>/dev/null || true
        hyprctl keyword general:col.inactive_border "rgba(6464ff4d)" 2>/dev/null || true
    else
        hyprctl keyword general:col.active_border "rgba(8839efcc) rgba(1e66f5cc) 45deg" 2>/dev/null || true
        hyprctl keyword general:col.inactive_border "rgba(7287fd4d)" 2>/dev/null || true
    fi
elif is_niri; then
    niri msg action load-config-file 2>/dev/null || true
fi

# ---------- Neovim ----------
NVIM_THEME_FILE="$HOME/.local/share/nvim-theme"
echo "$FLAVOR" > "$NVIM_THEME_FILE"
for addr in /run/user/$(id -u)/nvim.*.0 /tmp/nvim.*/0; do
    [ -S "$addr" ] || continue
    nvim --server "$addr" --remote-send "<Cmd>lua local c = require('catppuccin'); c.options.flavour = '${FLAVOR}'; c.compile(); vim.cmd.colorscheme('catppuccin')<CR>" 2>/dev/null || true
done

# ---------- Chezmoi templated configs ----------
if command -v chezmoi &>/dev/null; then
    chezmoi apply \
        ~/.gitconfig \
        ~/.config/gh-dash/config.yml \
        ~/.config/starship.toml \
        ~/.config/yazi/theme.toml \
        ~/.config/niri/config.kdl \
        2>/dev/null || true
fi

# ---------- Waybar restart ----------
if [ "$APPLY_DARK_MODE_NO_RESTART" != "1" ]; then
    if [ -x "$HOME/.config/hypr/scripts/reload-waybar.sh" ]; then
        "$HOME/.config/hypr/scripts/reload-waybar.sh"
    fi
fi
