# Dark/Light Mode Toggle — Findings and Current Direction

## Problem

After switching the portal default from `gtk` to `kde` (to reduce GNOME dependencies), the dark/light mode toggle initially looked broken in Chrome PWAs and Slack. Further testing on the current Fedora + Niri + KDE machine showed that Chrome works correctly when its appearance backend is set to `QT`, while Slack remains unreliable. This document captures the findings and the simplified direction.

## Decision

The repo should now treat KDE/Qt as the only supported source of truth for appearance:

- `plasma-apply-colorscheme` is the canonical dark/light switch
- `xdg-desktop-portal-kde` is the primary Settings portal backend
- Chromium-based apps should use the `QT` appearance setting when available

This is the preferred direction because the KDE/Qt path is the one that actually works cleanly on the current Fedora Niri machine. Chasing GTK/GSettings compatibility made the setup more complex without fixing Slack reliably.

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
Runs `plasma-apply-colorscheme` and applies repo-managed theme files. It no longer manages GTK `settings.ini`, `gsettings`, or `dconf`.

## App Detection Mechanisms (Confirmed by Testing)

| App | Type | How it detects dark mode | What it reads |
|-----|------|------------------------|---------------|
| **Kitty** | Native terminal | Own theme files + SIGUSR1 | Always works, independent |
| **Zen browser** | Firefox-based | Portal `SettingChanged` D-Bus signal | `org.freedesktop.appearance color-scheme` from portal |
| **Slack content** | Electron (bundled Chromium) | Unreliable in this setup | Not considered a target for system-level theme sync anymore |
| **Slack top bar** | Electron native frame | Unknown (inverted) | Cosmetic bug — shows opposite of content |
| **Chrome / Chrome PWAs** | Chromium-based | Chrome Appearance backend | `QT` works correctly on the current Fedora Niri KDE machine |

### Chrome appearance setting
Chrome should be set to **`QT`** in `chrome://settings/appearance` on KDE-backed tiling sessions. `GTK` was the source of the earlier confusion on this machine. "Chrome Colors" ignores the system theme entirely.

## Historical GTK Findings

Earlier debugging established the following when trying to make GTK-dependent apps behave:

- KDE GTK integration could update some runtime GTK state
- It did not provide a clean, reliable fix for Slack
- Manual `gsettings` writes created races and regressions
- None of that complexity was needed once Chrome was switched to `QT`

## Current Supported Model

The supported setup is now:
- KDE portal for `org.freedesktop.appearance color-scheme`
- `plasma-apply-colorscheme` for system theme switching
- `QT_QPA_PLATFORMTHEME=kde` for KDE-backed services
- Chrome configured to `QT`
- No attempt to keep Slack or generic GTK theme consumers perfectly synchronized

## What We Tried and Results

### 1. Writing `gsettings set gtk-theme` synchronously (before or after plasma-apply-colorscheme)
**Result**: Breaks Slack. The gsettings write conflicts with kded6 gtkconfig's async GtkSettings update, causing Slack to blink (briefly show correct theme, then revert).

### 2. Writing `gsettings set gtk-theme` in background with 1s delay
**Result**: Still broke things — even delayed writes interfere with kded6.

### 3. Unloading gtkconfig, writing gsettings ourselves, reloading gtkconfig
**Result**: Broke Chrome PWAs. Chrome relies on gtkconfig being loaded for GtkSettings change notifications.

### 4. No gsettings writes at all
**Result**: Better baseline than any manual GTK override.

### 5. The bounce trick (apply opposite scheme then target)
**Result**: Was the original cause of the race condition. kded6 fires async dconf write for the WRONG (opposite) value. Removed.

### 6. kwriteconfig6 to force ColorScheme key in kdeglobals
**Result**: When placed before `plasma-apply-colorscheme`, it makes the command think the scheme is "already set" and skip the work. When placed after, it triggers a second round of kded6 processing. Neither works well.

### 7. Switching Chrome appearance from `GTK` to `QT`
**Result**: Solved Chrome theming on the current Fedora + Niri + KDE machine.

## What Works Right Now

With the simplified KDE/Qt setup:
- Kitty: works (own mechanism)
- Zen browser: works (portal SettingChanged from portal backend)
- Chrome / Chrome PWAs: work when Chrome appearance is set to `QT`
- Slack: not reliable enough to justify extra theme-sync machinery

## Current Best Practice Direction

1. Keep KDE portal as the default Settings backend.
2. Keep `QT_QPA_PLATFORMTHEME=kde`.
3. Avoid repo-managed GTK, `gsettings`, or `dconf` theme synchronization.
4. Treat Chrome `QT` as the supported browser configuration on KDE-backed tiling sessions.
5. Do not optimize the system theme model around Slack.

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
