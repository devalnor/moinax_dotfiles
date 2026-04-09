#!/bin/bash

# Dark/Light mode dispatcher
# Usage: apply-dark-mode.sh [dark|light]
# If no argument given, reads from state file (defaults to dark)
#
# Design: KDE is the canonical source of truth for dark/light mode.
# plasma-apply-colorscheme updates KDE state and kded6 gtkconfig keeps GTK
# compatibility in sync where the distro's KDE stack supports it. This script
# only manages repo-local theme files in addition to the KDE scheme switch.

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
GTK_DARK_PREF=$( [ "$MODE" = "dark" ] && echo "true" || echo "false" )
GTK_THEME_NAME=$( [ "$MODE" = "dark" ] && echo "Breeze-Dark" || echo "Breeze" )
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
    gdbus call --session --dest=org.kde.kded6 --object-path /kded \
        --method org.kde.kded6.loadModule "gtkconfig" 2>/dev/null || true
    plasma-apply-colorscheme "$KDE_SCHEME" 2>/dev/null || true
fi

# ---------- GTK/dconf compatibility ----------
# Managed by kde-gtk-config / kded6 gtkconfig instead of repo-side gsettings.

# ---------- GTK settings.ini ----------
for GTK_DIR in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
    GTK_INI="$GTK_DIR/settings.ini"
    if [ -f "$GTK_INI" ]; then
        sed -i -e "s/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=$GTK_DARK_PREF/" \
               -e "s/^gtk-theme-name=.*/gtk-theme-name=$GTK_THEME_NAME/" "$GTK_INI"
    fi
done

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
if pgrep -xi hyprland &>/dev/null; then
    if [ "$MODE" = "dark" ]; then
        hyprctl keyword general:col.active_border "rgba(ff64ff80) rgba(9696ffff) 45deg" 2>/dev/null || true
        hyprctl keyword general:col.inactive_border "rgba(6464ff4d)" 2>/dev/null || true
    else
        hyprctl keyword general:col.active_border "rgba(8839efcc) rgba(1e66f5cc) 45deg" 2>/dev/null || true
        hyprctl keyword general:col.inactive_border "rgba(7287fd4d)" 2>/dev/null || true
    fi
elif pgrep -xi niri &>/dev/null; then
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
