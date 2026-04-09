# Dark/Light Mode Toggle — Findings, Decision, and Current State

## Problem

After switching the portal default from `gtk` to `kde` (to reduce GNOME dependencies), the dark/light mode toggle broke for Chrome PWAs (WhatsApp, Facebook) and Slack. This document captures all findings from extensive debugging.

## Decision

The repo should treat KDE as the primary source of truth for appearance:

- `plasma-apply-colorscheme` is the canonical dark/light switch
- `xdg-desktop-portal-kde` is the primary Settings portal backend
- KDE's GTK integration (`kde-gtk-config`, `kded6` `gtkconfig`) is the compatibility layer for GTK/GSettings consumers

This is the preferred direction because the portal API is the Linux standard for dark/light preference, while Chromium on Linux still appears to depend partly on GTK/GSettings behavior in practice. The right fix is therefore to keep KDE in charge and ensure the distro ships the KDE GTK sync component, not to keep repo-side `gsettings` writes or permanently route Settings through the GTK portal.

## Current Setup

### Portal config (`~/.config/xdg-desktop-portal/niri-portals.conf`)
```
[preferred]
default=kde
org.freedesktop.impl.portal.Screenshot=hyprland
org.freedesktop.impl.portal.ScreenCast=hyprland
org.freedesktop.impl.portal.RemoteDesktop=hyprland
```
- KDE portal handles Settings, file chooser, notifications, etc.
- Hyprland portal for screen capture

### Environment
- `~/.config/environment.d/kde.conf` exports `QT_QPA_PLATFORMTHEME=kde` so systemd user services (including the KDE portal) get the right Qt platform theme
- Without this, xdg-desktop-portal-kde can't determine dark/light from `QApplication::palette()`

### Script (`~/.local/bin/apply-dark-mode.sh`)
Runs `plasma-apply-colorscheme`, updates GTK `settings.ini`, and applies repo-managed theme files. No repo-side `gsettings`/`dconf` writes.

## App Detection Mechanisms (Confirmed by Testing)

| App | Type | How it detects dark mode | What it reads |
|-----|------|------------------------|---------------|
| **Kitty** | Native terminal | Own theme files + SIGUSR1 | Always works, independent |
| **Zen browser** | Firefox-based | Portal `SettingChanged` D-Bus signal | `org.freedesktop.appearance color-scheme` from portal |
| **Slack content** | Electron (bundled Chromium) | GtkSettings in-memory | Updated by kded6 gtkconfig from kdeglobals |
| **Slack top bar** | Electron native frame | Unknown (inverted) | Cosmetic bug — shows opposite of content |
| **Chrome PWAs** | Google Chrome "Use GTK" | KDE GTK sync / GSettings compatibility path | In practice appears to depend on GTK/GSettings state as much as portal state |

### Chrome appearance setting
Chrome must be set to **"Use GTK"** in `chrome://settings/appearance` for it to follow system theme at all. "Chrome Colors" ignores system theme entirely.

## What kded6 gtkconfig Does and Doesn't Do

When `plasma-apply-colorscheme` changes `~/.config/kdeglobals`:

| Action | Does it? |
|--------|----------|
| Update GtkSettings in-memory (D-Bus) | **Yes** — Slack content responds |
| Write dconf `color-scheme` | **Yes** — `'prefer-dark'` / `'prefer-light'` |
| Write dconf `gtk-theme` | **No** — stays stale at previous value |
| Regenerate `~/.config/gtk-{3,4}.0/colors.css` | Yes (when it detects a change) |

## The Core Problem

Chrome PWAs with "Use GTK" read `dconf gtk-theme` to determine dark/light mode. kded6 gtkconfig does NOT update this key. After toggling:
- `dconf color-scheme` = `'prefer-light'` (correct, updated by kded6)
- `dconf gtk-theme` = `'Breeze-Dark'` (WRONG, stale from previous state)

Chrome sees `Breeze-Dark` in `gtk-theme` and shows dark mode even when everything else is light.

## What We Tried and Results

### 1. Writing `gsettings set gtk-theme` synchronously (before or after plasma-apply-colorscheme)
**Result**: Breaks Slack. The gsettings write conflicts with kded6 gtkconfig's async GtkSettings update, causing Slack to blink (briefly show correct theme, then revert).

### 2. Writing `gsettings set gtk-theme` in background with 1s delay
**Result**: Still broke things — even delayed writes interfere with kded6.

### 3. Unloading gtkconfig, writing gsettings ourselves, reloading gtkconfig
**Result**: Broke Chrome PWAs. Chrome relies on gtkconfig being loaded for GtkSettings change notifications.

### 4. No gsettings writes at all (current state)
**Result**: Best so far. Everything works EXCEPT Chrome PWAs (stuck on stale `gtk-theme`).

### 5. The bounce trick (apply opposite scheme then target)
**Result**: Was the original cause of the race condition. kded6 fires async dconf write for the WRONG (opposite) value. Removed.

### 6. kwriteconfig6 to force ColorScheme key in kdeglobals
**Result**: When placed before `plasma-apply-colorscheme`, it makes the command think the scheme is "already set" and skip the work. When placed after, it triggers a second round of kded6 processing. Neither works well.

## What Works Right Now

With no repo-side `gsettings` writes:
- Kitty: works (own mechanism)
- Zen browser: works (portal SettingChanged from portal backend)
- Slack content: works (kded6 gtkconfig → GtkSettings in-memory)
- Slack top bar: inverted (Electron cosmetic bug, not fixable from system side)
- Chrome PWAs: depend on whether the distro's KDE GTK sync updates GSettings correctly

## Current Best Practice Direction

1. Keep KDE portal as the default Settings backend.
2. Keep `kde-gtk-config` (or Debian's `kde-config-gtk-style`) installed on KDE-backed tiling sessions.
3. Avoid repo-managed `gsettings` writes for `gtk-theme` or `color-scheme`.
4. Treat Chromium discrepancies as distro/version-specific KDE GTK sync issues first, not as a reason to move Settings back to the GTK portal.

## Historical Problem Statement

Earlier experimentation was focused on the question below.

### How to Update dconf `gtk-theme` Without Breaking Slack

The challenge: writing `gsettings set org.gnome.desktop.interface gtk-theme` to dconf at ANY point (before, after, or delayed) during the toggle causes kded6 gtkconfig to react and send conflicting GtkSettings updates that break Slack.

### Possible approaches not yet tried
1. **Change Chrome from "Use GTK" to something else** — maybe "Use Classic" or "Use QT" reads from a source kded6 does update
2. **Disable gtkconfig entirely** and handle ALL dconf/GtkSettings writes manually — but Chrome needs GtkSettings change notifications that only gtkconfig provides
3. **Patch kded6 gtkconfig** to also write `gtk-theme` to dconf (upstream fix)
4. **Use xdg-settings** or another mechanism to tell Chrome about the theme
5. **Launch Chrome PWAs with `--force-dark-mode` / `--disable-features=WebContentsForceDark`** flags
6. **Write dconf `gtk-theme` via `dconf write` instead of `gsettings set`** — maybe gsettings triggers additional change notifications that dconf doesn't
7. **Write dconf `gtk-theme` much later** (5-10 seconds) after kded6 has fully settled — ugly but might avoid the conflict window

## File Locations

- Script: `home/dot_local/bin/executable_apply-dark-mode.sh`
- Toggle wrapper: `home/dot_local/bin/executable_toggle-dark-mode.sh`
- Portal config (Niri): `home/dot_config/xdg-desktop-portal/niri-portals.conf`
- Portal config (Hyprland): `home/dot_config/xdg-desktop-portal/hyprland-portals.conf`
- Environment: `home/dot_config/environment.d/kde.conf`
- GTK settings: `~/.config/gtk-3.0/settings.ini`, `~/.config/gtk-4.0/settings.ini`
- KDE globals: `~/.config/kdeglobals`
- KDE defaults: `~/.config/kdedefaults/kdeglobals` (has `ColorScheme=BreezeLight` as default)
- State file: `~/.local/share/dark-light-mode`

## Useful Debug Commands

```bash
# Check all values at once
echo "Mode: $(cat ~/.local/share/dark-light-mode)"
echo "Portal: $(dbus-send --session --dest=org.freedesktop.portal.Desktop --print-reply /org/freedesktop/portal/desktop org.freedesktop.portal.Settings.Read string:'org.freedesktop.appearance' string:'color-scheme' 2>&1 | grep uint32)"
echo "dconf color-scheme: $(dconf read /org/gnome/desktop/interface/color-scheme)"
echo "dconf gtk-theme: $(dconf read /org/gnome/desktop/interface/gtk-theme)"
echo "kdeglobals: $(grep '^ColorScheme=' ~/.config/kdeglobals)"
echo "settings.ini: $(grep -E 'prefer-dark|gtk-theme-name' ~/.config/gtk-3.0/settings.ini)"

# Monitor portal signals during toggle
timeout 15 dbus-monitor --session "type='signal',member='SettingChanged'"

# Monitor dconf changes during toggle
timeout 15 dconf watch /org/gnome/desktop/interface/

# Check if gtkconfig is loaded
gdbus call --session --dest=org.kde.kded6 --object-path /kded --method org.kde.kded6.loadedModules 2>/dev/null | grep gtkconfig

# Check portal services
systemctl --user status xdg-desktop-portal xdg-desktop-portal-gtk plasma-xdg-desktop-portal-kde
```
