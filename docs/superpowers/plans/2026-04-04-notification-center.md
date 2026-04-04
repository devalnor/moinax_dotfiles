# Notification Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Mako/Dunst with SwayNC across all distros, adding a notification center drawer, DND, copy-to-clipboard, Waybar integration, and custom Catppuccin styling.

**Architecture:** SwayNC is a GTK4 notification daemon with built-in control center. It replaces both Mako (Arch/Fedora) and Dunst (Debian/Ubuntu), eliminating distro-conditional branching. Two CSS theme files (dark/light) follow the existing file-copy toggle pattern. A Waybar custom module shows bell + count.

**Tech Stack:** SwayNC, GTK4 CSS, Waybar custom module, shell scripts, Chezmoi templates, YAML package definitions

---

### Task 1: Create SwayNC config.json

**Files:**
- Create: `home/dot_config/swaync/config.json`

- [ ] **Step 1: Create the SwayNC configuration file**

```json
{
  "$schema": "/etc/xdg/swaync/configSchema.json",
  "positionX": "right",
  "positionY": "top",
  "control-center-positionX": "right",
  "control-center-positionY": "top",
  "control-center-width": 380,
  "notification-window-width": 600,
  "timeout": 15000,
  "timeout-low": 3000,
  "timeout-critical": 30000,
  "fit-to-screen": true,
  "keyboard-shortcuts": true,
  "hide-on-clear": true,
  "hide-on-action": true,
  "notification-grouping": true,
  "scripts": {
    "copy-notification": {
      "exec": "~/.local/bin/swaync-copy.sh \"$SWAYNC_BODY\"",
      "app-name": ".*",
      "run-on": "action"
    }
  },
  "notification-visibility": {
    "volume-control": {
      "state": "transient",
      "app-name": "volume-control"
    }
  },
  "widgets": [
    "title",
    "dnd",
    "notifications",
    "mpris"
  ],
  "widget-config": {
    "title": {
      "text": "Notifications",
      "clear-all-button": true,
      "button-text": "Clear"
    },
    "dnd": {
      "text": "Do Not Disturb"
    },
    "mpris": {
      "image-size": 48,
      "blur": false
    }
  }
}
```

Create this file at `home/dot_config/swaync/config.json`.

- [ ] **Step 2: Commit**

```bash
git add home/dot_config/swaync/config.json
git commit -m "feat: add SwayNC config with drawer, DND, grouping, copy action"
```

---

### Task 2: Create SwayNC dark theme CSS

**Files:**
- Create: `home/dot_config/swaync/style-dark.css`

- [ ] **Step 1: Create the dark theme CSS**

Write `home/dot_config/swaync/style-dark.css` with the full Catppuccin Mocha styling. Key design tokens from the existing codebase:
- Font: `FiraCode Nerd Font`, 14px (matching waybar `style-dark.css:5-8`)
- Background: `rgba(30, 30, 46, 0.85)` (matching waybar `style-dark.css:15`)
- Module bg: `rgba(100, 100, 255, 0.3)` (matching waybar `style-dark.css:34`)
- Border radius: `8px` (matching waybar `style-dark.css:35`)
- Text: `#cdd6f4` primary, `#a6adc8` secondary, `#bac2de` body
- Urgency borders from mako `config-dark`: low `#6464ff`, normal `#89b4fa`, critical `#fab387`
- Close button: `#f38ba8` bg, `#1e1e2e` text
- DND active: `#6464ff`
- Hover transition: `0.3s ease-in-out` (matching waybar `style-dark.css:57`)

```css
* {
  all: unset;
  font-size: 14px;
  font-family: "FiraCode Nerd Font", "FiraCode Nerd Font Mono", sans-serif;
  transition: 200ms;
}

/* ── Popup notifications ─────────────────────────────────── */

.notification-background {
  background: rgba(30, 30, 46, 0.85);
  border-radius: 8px;
  margin: 8px;
  padding: 0;
  color: #cdd6f4;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4);
}

.notification-background .notification {
  padding: 8px;
  border-radius: 8px;
  border: 1px solid rgba(137, 180, 250, 0.25);
  background: rgba(100, 100, 255, 0.08);
}

.notification-background .notification.low {
  border-color: rgba(100, 100, 255, 0.25);
  background: rgba(100, 100, 255, 0.04);
}

.notification-background .notification.critical {
  border-color: rgba(243, 139, 168, 0.4);
  background: rgba(243, 139, 168, 0.1);
}

.notification .notification-content {
  margin: 4px;
}

.notification-content .summary {
  color: #cdd6f4;
  font-weight: bold;
}

.notification-content .time {
  color: #a6adc8;
}

.notification-content .body {
  color: #bac2de;
}

.notification > *:last-child > * {
  min-height: 3.4em;
}

/* Close button */
.notification-background .close-button {
  margin: 6px;
  padding: 2px;
  border-radius: 6px;
  color: #1e1e2e;
  background-color: #f38ba8;
}

.notification-background .close-button:hover {
  background-color: #eba0ac;
}

/* Action buttons (including copy) */
.notification .notification-action {
  border-radius: 8px;
  color: #89b4fa;
  background: rgba(100, 100, 255, 0.2);
  margin: 4px;
  padding: 8px;
  transition: all 0.3s ease-in-out;
}

.notification .notification-action:hover {
  background: rgba(100, 100, 255, 0.35);
}

.notification .notification-action:active {
  background: rgba(100, 100, 255, 0.5);
}

/* Progress bars */
.notification.critical progress {
  background-color: #f38ba8;
}

.notification.low progress,
.notification.normal progress {
  background-color: #89b4fa;
}

.notification progress,
.notification trough,
.notification progressbar {
  border-radius: 8px;
  padding: 3px 0;
}

trough {
  background-color: rgba(100, 100, 255, 0.1);
}

trough highlight {
  background: #89b4fa;
}

/* ── Control center (drawer) ─────────────────────────────── */

.control-center {
  background-color: rgba(30, 30, 46, 0.92);
  border-radius: 8px;
  border: 1px solid rgba(100, 100, 255, 0.15);
  color: #cdd6f4;
  padding: 14px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
}

.control-center .notification-background {
  border-radius: 8px;
  margin: 4px 0;
  box-shadow: none;
}

.control-center .notification-background .notification {
  border-radius: 8px;
}

.control-center .notification-background .notification.low {
  opacity: 0.8;
}

/* Title widget */
.control-center .widget-title > label {
  color: #cdd6f4;
  font-size: 1.2em;
  font-weight: bold;
}

.control-center .widget-title button {
  border-radius: 8px;
  color: #89b4fa;
  background: rgba(100, 100, 255, 0.2);
  padding: 6px 12px;
  transition: all 0.3s ease-in-out;
}

.control-center .widget-title button:hover {
  background: rgba(100, 100, 255, 0.35);
}

/* Notification groups */
.control-center .notification-group {
  margin-top: 8px;
}

/* Scrollbar */
scrollbar slider {
  margin: -3px;
  opacity: 0.6;
  background: rgba(100, 100, 255, 0.3);
  border-radius: 8px;
}

scrollbar trough {
  margin: 2px 0;
  background: transparent;
}

/* ── DND widget ──────────────────────────────────────────── */

.widget-dnd {
  margin-top: 8px;
  border-radius: 8px;
  font-size: 1rem;
}

.widget-dnd > switch {
  font-size: initial;
  border-radius: 8px;
  background: rgba(100, 100, 255, 0.1);
  box-shadow: none;
}

.widget-dnd > switch:checked {
  background: #6464ff;
}

.widget-dnd > switch slider {
  background: rgba(100, 100, 255, 0.3);
  border-radius: 8px;
}

.widget-dnd > switch:checked slider {
  background: #cdd6f4;
}

/* ── MPRIS widget ────────────────────────────────────────── */

.widget-mpris-player {
  background: rgba(100, 100, 255, 0.08);
  border: 1px solid rgba(100, 100, 255, 0.15);
  border-radius: 8px;
  color: #cdd6f4;
}

.widget-mpris-album-art {
  border-radius: 8px;
  margin: 0 8px;
}

.widget-mpris-title {
  font-size: 1.1rem;
  font-weight: bold;
  color: #cdd6f4;
}

.widget-mpris-subtitle {
  font-size: 0.9rem;
  color: #bac2de;
}

.widget-mpris button {
  border-radius: 8px;
  color: #89b4fa;
  margin: 0 4px;
  padding: 4px;
  transition: all 0.3s ease-in-out;
}

.widget-mpris button:hover {
  background: rgba(100, 100, 255, 0.2);
}

.widget-mpris button:active {
  background: rgba(100, 100, 255, 0.35);
}

.widget-mpris button:disabled {
  opacity: 0.4;
}

/* Scale (sliders) */
scale trough {
  margin: 0 1rem;
  min-height: 8px;
  min-width: 70px;
  border-radius: 8px;
}

trough slider {
  margin: -10px;
  border-radius: 8px;
  background-color: #89b4fa;
}

trough slider:hover {
  box-shadow: 0 0 8px rgba(137, 180, 250, 0.5);
}
```

- [ ] **Step 2: Commit**

```bash
git add home/dot_config/swaync/style-dark.css
git commit -m "feat: add SwayNC dark theme (Catppuccin Mocha)"
```

---

### Task 3: Create SwayNC light theme CSS

**Files:**
- Create: `home/dot_config/swaync/style-light.css`

- [ ] **Step 1: Create the light theme CSS**

Write `home/dot_config/swaync/style-light.css` — same structure as dark, with Catppuccin Latte colors. Key substitutions from the existing `style-light.css` and `config-light`:
- Background: `rgba(239, 241, 245, 0.85)` (from waybar `style-light.css:15`)
- Text: `#4c4f69` (from waybar `style-light.css:1`)
- Normal border: `rgba(30, 102, 245, 0.25)` (from mako `config-light` `#1e66f5`)
- Critical border: `rgba(254, 100, 11, 0.4)` (from mako `config-light` `#fe640b`)
- Low border: `rgba(100, 100, 255, 0.25)` (same as dark — `#6464ff` is used in both modes)
- Module bg light: `rgba(100, 100, 255, 0.15)` (from waybar `style-light.css:34`)
- Close button: `#d20f39` bg (Latte red)
- Hover active bg: `rgba(100, 100, 255, 0.3)` (from waybar `style-light.css:63`)
- Body text: `#6c6f85` (Latte subtext0)
- Secondary: `#8c8fa1` (Latte subtext1)

```css
* {
  all: unset;
  font-size: 14px;
  font-family: "FiraCode Nerd Font", "FiraCode Nerd Font Mono", sans-serif;
  transition: 200ms;
}

/* ── Popup notifications ─────────────────────────────────── */

.notification-background {
  background: rgba(239, 241, 245, 0.85);
  border-radius: 8px;
  margin: 8px;
  padding: 0;
  color: #4c4f69;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.15);
}

.notification-background .notification {
  padding: 8px;
  border-radius: 8px;
  border: 1px solid rgba(30, 102, 245, 0.25);
  background: rgba(100, 100, 255, 0.06);
}

.notification-background .notification.low {
  border-color: rgba(100, 100, 255, 0.25);
  background: rgba(100, 100, 255, 0.03);
}

.notification-background .notification.critical {
  border-color: rgba(254, 100, 11, 0.4);
  background: rgba(254, 100, 11, 0.08);
}

.notification .notification-content {
  margin: 4px;
}

.notification-content .summary {
  color: #4c4f69;
  font-weight: bold;
}

.notification-content .time {
  color: #8c8fa1;
}

.notification-content .body {
  color: #6c6f85;
}

.notification > *:last-child > * {
  min-height: 3.4em;
}

.notification-background .close-button {
  margin: 6px;
  padding: 2px;
  border-radius: 6px;
  color: #eff1f5;
  background-color: #d20f39;
}

.notification-background .close-button:hover {
  background-color: #e64553;
}

.notification .notification-action {
  border-radius: 8px;
  color: #1e66f5;
  background: rgba(100, 100, 255, 0.15);
  margin: 4px;
  padding: 8px;
  transition: all 0.3s ease-in-out;
}

.notification .notification-action:hover {
  background: rgba(100, 100, 255, 0.25);
}

.notification .notification-action:active {
  background: rgba(100, 100, 255, 0.35);
}

.notification.critical progress {
  background-color: #d20f39;
}

.notification.low progress,
.notification.normal progress {
  background-color: #1e66f5;
}

.notification progress,
.notification trough,
.notification progressbar {
  border-radius: 8px;
  padding: 3px 0;
}

trough {
  background-color: rgba(100, 100, 255, 0.08);
}

trough highlight {
  background: #1e66f5;
}

/* ── Control center (drawer) ─────────────────────────────── */

.control-center {
  background-color: rgba(239, 241, 245, 0.92);
  border-radius: 8px;
  border: 1px solid rgba(100, 100, 255, 0.1);
  color: #4c4f69;
  padding: 14px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.15);
}

.control-center .notification-background {
  border-radius: 8px;
  margin: 4px 0;
  box-shadow: none;
}

.control-center .notification-background .notification {
  border-radius: 8px;
}

.control-center .notification-background .notification.low {
  opacity: 0.8;
}

.control-center .widget-title > label {
  color: #4c4f69;
  font-size: 1.2em;
  font-weight: bold;
}

.control-center .widget-title button {
  border-radius: 8px;
  color: #1e66f5;
  background: rgba(100, 100, 255, 0.15);
  padding: 6px 12px;
  transition: all 0.3s ease-in-out;
}

.control-center .widget-title button:hover {
  background: rgba(100, 100, 255, 0.25);
}

.control-center .notification-group {
  margin-top: 8px;
}

scrollbar slider {
  margin: -3px;
  opacity: 0.6;
  background: rgba(100, 100, 255, 0.2);
  border-radius: 8px;
}

scrollbar trough {
  margin: 2px 0;
  background: transparent;
}

/* ── DND widget ──────────────────────────────────────────── */

.widget-dnd {
  margin-top: 8px;
  border-radius: 8px;
  font-size: 1rem;
}

.widget-dnd > switch {
  font-size: initial;
  border-radius: 8px;
  background: rgba(100, 100, 255, 0.08);
  box-shadow: none;
}

.widget-dnd > switch:checked {
  background: #6464ff;
}

.widget-dnd > switch slider {
  background: rgba(100, 100, 255, 0.2);
  border-radius: 8px;
}

.widget-dnd > switch:checked slider {
  background: #eff1f5;
}

/* ── MPRIS widget ────────────────────────────────────────── */

.widget-mpris-player {
  background: rgba(100, 100, 255, 0.06);
  border: 1px solid rgba(100, 100, 255, 0.1);
  border-radius: 8px;
  color: #4c4f69;
}

.widget-mpris-album-art {
  border-radius: 8px;
  margin: 0 8px;
}

.widget-mpris-title {
  font-size: 1.1rem;
  font-weight: bold;
  color: #4c4f69;
}

.widget-mpris-subtitle {
  font-size: 0.9rem;
  color: #6c6f85;
}

.widget-mpris button {
  border-radius: 8px;
  color: #1e66f5;
  margin: 0 4px;
  padding: 4px;
  transition: all 0.3s ease-in-out;
}

.widget-mpris button:hover {
  background: rgba(100, 100, 255, 0.15);
}

.widget-mpris button:active {
  background: rgba(100, 100, 255, 0.25);
}

.widget-mpris button:disabled {
  opacity: 0.4;
}

scale trough {
  margin: 0 1rem;
  min-height: 8px;
  min-width: 70px;
  border-radius: 8px;
}

trough slider {
  margin: -10px;
  border-radius: 8px;
  background-color: #1e66f5;
}

trough slider:hover {
  box-shadow: 0 0 8px rgba(30, 102, 245, 0.5);
}
```

- [ ] **Step 2: Commit**

```bash
git add home/dot_config/swaync/style-light.css
git commit -m "feat: add SwayNC light theme (Catppuccin Latte)"
```

---

### Task 4: Create copy notification script

**Files:**
- Create: `home/dot_local/bin/executable_swaync-copy.sh`

- [ ] **Step 1: Create the copy script**

```bash
#!/bin/bash
set -e

# Copy notification body text to clipboard
# Called by SwayNC's script system with the notification body as $1

BODY="$1"

if [ -z "$BODY" ]; then
    exit 0
fi

echo -n "$BODY" | wl-copy

notify-send -u low -t 2000 -a "swaync-copy" "Copied" "Notification text copied to clipboard"
```

Create this file at `home/dot_local/bin/executable_swaync-copy.sh`. The `executable_` prefix makes chezmoi set the execute bit.

- [ ] **Step 2: Commit**

```bash
git add home/dot_local/bin/executable_swaync-copy.sh
git commit -m "feat: add swaync-copy script for clipboard notification action"
```

---

### Task 5: Add Waybar notification module

**Files:**
- Modify: `home/dot_config/waybar/modules.jsonc.tmpl` (add module at end, before closing `}`)
- Modify: `home/dot_config/waybar/config-hyprland.tmpl` (add to modules-right)
- Modify: `home/dot_config/waybar/config-niri.tmpl` (add to modules-right)

- [ ] **Step 1: Add the custom/notification module definition**

In `home/dot_config/waybar/modules.jsonc.tmpl`, add before the closing `}` on line 240:

```jsonc
  // Notification center (SwayNC)
  "custom/notification": {
    "exec": "swaync-client -swb",
    "return-type": "json",
    "tooltip": true,
    "on-click": "swaync-client -t",
    "on-click-right": "swaync-client -d",
    "escape": true,
    "format": "{icon} {}",
    "format-icons": {
      "notification": "<span foreground='#f5c2e7'>\uf0f3</span>",
      "none": "\uf0f3",
      "dnd-notification": "<span foreground='#f5c2e7'>\uf1f6</span>",
      "dnd-none": "\uf1f6",
      "inhibited-notification": "<span foreground='#f5c2e7'>\uf0f3</span>",
      "inhibited-none": "\uf0f3"
    },
  },
```

Note: `\uf0f3` is the bell icon, `\uf1f6` is the bell-slash icon (Font Awesome / Nerd Font).

- [ ] **Step 2: Add the module to Hyprland waybar config**

In `home/dot_config/waybar/config-hyprland.tmpl`, add `"custom/notification"` to `modules-right`, after `"custom/tailscale"` and before `"tray"`. The line should become:

```jsonc
        "custom/tailscale",
        "custom/notification",
        "tray",
```

- [ ] **Step 3: Add the module to Niri waybar config**

In `home/dot_config/waybar/config-niri.tmpl`, same change — add `"custom/notification"` after `"custom/tailscale"` and before `"tray"`:

```jsonc
        "custom/tailscale",
        "custom/notification",
        "tray",
```

- [ ] **Step 4: Commit**

```bash
git add home/dot_config/waybar/modules.jsonc.tmpl home/dot_config/waybar/config-hyprland.tmpl home/dot_config/waybar/config-niri.tmpl
git commit -m "feat: add Waybar notification module for SwayNC"
```

---

### Task 6: Add Waybar notification CSS (both themes)

**Files:**
- Modify: `home/dot_config/waybar/style-dark.css` (append notification styles)
- Modify: `home/dot_config/waybar/style-light.css` (append notification styles)

- [ ] **Step 1: Add notification CSS to dark theme**

Append to `home/dot_config/waybar/style-dark.css` (after the battery blink animation block, line 115):

```css
/* Notification center */
#custom-notification {
  font-size: 17px;
}
#custom-notification.dnd-notification,
#custom-notification.dnd-none {
  opacity: 0.5;
}
```

Also add `#custom-notification` to the existing icon font-size selector on line 68-76. The selector currently is:

```css
#custom-exit,
#custom-system,
#custom-caffeine,
#custom-tailscale,
#custom-headset-battery,
#custom-dark-mode,
#idle-inhibitor,
#workspaces button {
```

Add `#custom-notification,` to this list.

- [ ] **Step 2: Add notification CSS to light theme**

Same changes to `home/dot_config/waybar/style-light.css`:

Append after line 115:

```css
/* Notification center */
#custom-notification {
  font-size: 17px;
}
#custom-notification.dnd-notification,
#custom-notification.dnd-none {
  opacity: 0.5;
}
```

Also add `#custom-notification,` to the icon font-size selector (line 68-76 of style-light.css).

- [ ] **Step 3: Commit**

```bash
git add home/dot_config/waybar/style-dark.css home/dot_config/waybar/style-light.css
git commit -m "feat: add Waybar CSS for notification module (dark + light)"
```

---

### Task 7: Update keybindings (Hyprland + Niri)

**Files:**
- Modify: `home/dot_config/hypr/conf/binds.conf.tmpl` (lines 112-116 and add new binds)
- Modify: `home/dot_config/niri/config.kdl.tmpl` (lines 289-296 and add new binds)

- [ ] **Step 1: Update Hyprland keybindings**

In `home/dot_config/hypr/conf/binds.conf.tmpl`:

1. In section 1 (Application Shortcuts), after the `Mod+H` line (line 137), add:

```conf
bind = SUPER, U, exec, swaync-client -t # Toggle notification center
bind = SUPER ALT, U, exec, swaync-client -d # Toggle DND
```

2. In section 11 (Reload Configs), replace line 115:

```conf
bind = SUPER SHIFT, M, exec, ~/.config/hypr/scripts/reload-mako.sh # Reload notifications
```

with:

```conf
bind = SUPER SHIFT, M, exec, swaync-client -R && swaync-client -rs # Reload SwayNC
```

- [ ] **Step 2: Update Niri keybindings**

In `home/dot_config/niri/config.kdl.tmpl`:

1. In section 1 (Application Shortcuts), after the `Mod+H` line (line 327), add:

```kdl
    Mod+U hotkey-overlay-title="Toggle Notification Center" { spawn-sh "swaync-client -t"; }
    Mod+Alt+U hotkey-overlay-title="Toggle Do Not Disturb" { spawn-sh "swaync-client -d"; }
```

2. In section 11 (Reload Configs), replace the mako/dunst conditional block (lines 292-296):

```kdl
{{ if or (eq .distro "debian") ... -}}
    Mod+Shift+M hotkey-overlay-title="Reload Notifications: dunst" { spawn-sh "killall dunst; dunst &"; }
{{ else -}}
    Mod+Shift+M hotkey-overlay-title="Reload Notifications: mako" { spawn-sh "killall mako; mako &"; }
{{ end -}}
```

with a single unconditional line:

```kdl
    Mod+Shift+M hotkey-overlay-title="Reload SwayNC" { spawn-sh "swaync-client -R && swaync-client -rs"; }
```

- [ ] **Step 3: Commit**

```bash
git add home/dot_config/hypr/conf/binds.conf.tmpl home/dot_config/niri/config.kdl.tmpl
git commit -m "feat: add Mod+U (drawer), Mod+Alt+U (DND), update Mod+Shift+M reload"
```

---

### Task 8: Update autostart configs

**Files:**
- Modify: `home/dot_config/hypr/conf/autostart.conf.tmpl` (lines 4-8)
- Modify: `home/dot_config/niri/config.kdl.tmpl` (lines 139-143)

- [ ] **Step 1: Update Hyprland autostart**

In `home/dot_config/hypr/conf/autostart.conf.tmpl`, replace lines 4-8:

```conf
{{- if or (eq .distro "debian") (eq .distro "ubuntu") (eq .distro "linuxmint") (eq .distro "pop") (eq .distro "elementary") (eq .distro "neon") (eq .distro "zorin") (eq .distro "kali") }}
exec-once = dunst
{{- else }}
exec-once = mako
{{- end }}
```

with:

```conf
exec-once = swaync
```

- [ ] **Step 2: Update Niri autostart**

In `home/dot_config/niri/config.kdl.tmpl`, replace lines 139-143:

```kdl
{{ if or (eq .distro "debian") (eq .distro "ubuntu") (eq .distro "linuxmint") (eq .distro "pop") (eq .distro "elementary") (eq .distro "neon") (eq .distro "zorin") (eq .distro "kali") -}}
spawn-at-startup "dunst"
{{ else -}}
spawn-at-startup "mako"
{{ end -}}
```

with:

```kdl
spawn-at-startup "swaync"
```

- [ ] **Step 3: Commit**

```bash
git add home/dot_config/hypr/conf/autostart.conf.tmpl home/dot_config/niri/config.kdl.tmpl
git commit -m "feat: replace mako/dunst autostart with swaync"
```

---

### Task 9: Update reload script

**Files:**
- Modify: `home/dot_config/hypr/scripts/executable_reload-mako.sh.tmpl`

- [ ] **Step 1: Replace the reload script content**

Replace the entire content of `home/dot_config/hypr/scripts/executable_reload-mako.sh.tmpl` with:

```bash
#!/bin/bash
# Reload SwayNC (notification center)
swaync-client -R && swaync-client -rs
```

This removes the distro-conditional dunst/mako branching. The file keeps its name for now (renaming chezmoi source files requires care with chezmoi's state tracking — can be done as a follow-up).

- [ ] **Step 2: Commit**

```bash
git add home/dot_config/hypr/scripts/executable_reload-mako.sh.tmpl
git commit -m "refactor: update reload-mako script to reload swaync"
```

---

### Task 10: Update dark/light toggle script

**Files:**
- Modify: `home/dot_local/bin/executable_apply-dark-mode.sh` (lines 92-97)

- [ ] **Step 1: Replace the mako section with SwayNC**

In `home/dot_local/bin/executable_apply-dark-mode.sh`, replace lines 92-97 (section `# 8. Mako`):

```bash
# 8. Mako
MAKO_SRC="$HOME/.config/mako/config-${MODE}"
if [ -f "$MAKO_SRC" ]; then
    cp "$MAKO_SRC" "$HOME/.config/mako/config"
    makoctl reload 2>/dev/null || true
fi
```

with:

```bash
# 8. SwayNC
SWAYNC_SRC="$HOME/.config/swaync/style-${MODE}.css"
if [ -f "$SWAYNC_SRC" ]; then
    cp "$SWAYNC_SRC" "$HOME/.config/swaync/style.css"
    swaync-client -rs 2>/dev/null || true
fi
```

- [ ] **Step 2: Commit**

```bash
git add home/dot_local/bin/executable_apply-dark-mode.sh
git commit -m "feat: swap mako for swaync in dark/light mode toggle"
```

---

### Task 11: Update package definitions

**Files:**
- Modify: `packages/groups/hyprland.yaml`
- Modify: `packages/groups/niri.yaml`

- [ ] **Step 1: Update hyprland.yaml**

In `packages/groups/hyprland.yaml`:

1. Update description on line 3: change `(waybar, rofi, mako)` to `(waybar, rofi, swaync)`
2. Update descriptions section — replace line 34:
   ```yaml
   mako: Lightweight notification daemon
   ```
   with:
   ```yaml
   swaync: Notification center with drawer and DND
   ```
3. Update dotfiles section — replace line 12:
   ```yaml
     - dot_config/mako
   ```
   with:
   ```yaml
     - dot_config/swaync
   ```
4. In `packages.arch` — replace line 70 (`- mako`) with:
   ```yaml
       - swaync
   ```
   Update the comment on line 69 from `# Notifications` (keep as-is, just the package changes).
5. In `packages.fedora` — replace line 112 (`- mako`) with:
   ```yaml
       - SwayNotificationCenter
   ```
6. In `packages.debian` — replace lines 158-159:
   ```yaml
       - dunst            # mako is not in apt; dunst is the apt equivalent
   ```
   with:
   ```yaml
       - sway-notification-center
   ```
   Remove the comment above it about mako configs/dunst adaptation (lines 155-157).
7. In `fedora_copr` section (line 180-181), add the SwayNC COPR:
   ```yaml
     fedora_copr:
       - solopasha/hyprland  # For latest Hyprland packages
       - erikreider/SwayNotificationCenter  # Notification center
   ```

- [ ] **Step 2: Update niri.yaml**

In `packages/groups/niri.yaml`:

1. Update description on line 3: change `(waybar, rofi, mako)` to `(waybar, rofi, swaync)`
2. Update descriptions section — replace line 30:
   ```yaml
   mako: Lightweight notification daemon
   ```
   with:
   ```yaml
   swaync: Notification center with drawer and DND
   ```
3. Update dotfiles section — replace line 12:
   ```yaml
     - dot_config/mako
   ```
   with:
   ```yaml
     - dot_config/swaync
   ```
4. In `packages.arch` — replace line 67 (`- mako`) with:
   ```yaml
       - swaync
   ```
5. In `packages.fedora` — replace line 122 (`- mako`) with:
   ```yaml
       - SwayNotificationCenter
   ```
6. In `packages.debian` — replace lines 175-176:
   ```yaml
       - dunst            # mako not in apt; dunst is the apt equivalent
   ```
   with:
   ```yaml
       - sway-notification-center
   ```
   Remove the comment above it about mako configs/dunst adaptation (lines 172-174).
7. Add a `fedora_copr` section at the end of the file (niri.yaml currently has no fedora_copr):
   ```yaml
     fedora_copr:
       - erikreider/SwayNotificationCenter  # Notification center
   ```

- [ ] **Step 3: Commit**

```bash
git add packages/groups/hyprland.yaml packages/groups/niri.yaml
git commit -m "feat: replace mako/dunst with swaync in package definitions"
```

---

### Task 12: Update .chezmoiignore

**Files:**
- Modify: `home/.chezmoiignore`

- [ ] **Step 1: Update ignore patterns**

In `home/.chezmoiignore`:

1. Replace line 39-40:
   ```
   .config/mako
   .config/mako/**
   ```
   with:
   ```
   .config/swaync
   .config/swaync/**
   ```
2. Replace line 76:
   ```
   .config/mako/config
   ```
   with:
   ```
   .config/swaync/style.css
   ```

The `style.css` active file is generated at runtime by `apply-dark-mode.sh` (same pattern as waybar's `style.css` on line 79).

- [ ] **Step 2: Commit**

```bash
git add home/.chezmoiignore
git commit -m "refactor: update chezmoiignore from mako to swaync"
```

---

### Task 13: Remove mako config files

**Files:**
- Remove: `home/dot_config/mako/config-dark`
- Remove: `home/dot_config/mako/config-light`

- [ ] **Step 1: Remove the mako config files**

```bash
git rm home/dot_config/mako/config-dark home/dot_config/mako/config-light
```

If there are other files in the `home/dot_config/mako/` directory, remove the entire directory. If it's just these two files, remove the directory too:

```bash
rmdir home/dot_config/mako 2>/dev/null || true
```

- [ ] **Step 2: Commit**

```bash
git commit -m "chore: remove mako config files (replaced by swaync)"
```

---

### Task 14: Update KEYBINDINGS.md

**Files:**
- Modify: `KEYBINDINGS.md`

- [ ] **Step 1: Add notification center keybindings**

In `KEYBINDINGS.md`, in section 1 (Application Shortcuts), add after the `Keybinding help` row (last row in section 1):

```markdown
| Toggle notification center | `Mod+U` | `Mod+U` | `swaync-client -t` |
| Toggle DND | `Mod+Alt+U` | `Mod+Alt+U` | `swaync-client -d` |
```

- [ ] **Step 2: Update reload section**

In section 11 (Reload Configs), replace:

```markdown
| Reload Mako | `Mod+Shift+M` | `Mod+Shift+M` | |
```

with:

```markdown
| Reload SwayNC | `Mod+Shift+M` | `Mod+Shift+M` | `swaync-client -R && swaync-client -rs` |
```

- [ ] **Step 3: Commit**

```bash
git add KEYBINDINGS.md
git commit -m "docs: update KEYBINDINGS.md with notification center bindings"
```
