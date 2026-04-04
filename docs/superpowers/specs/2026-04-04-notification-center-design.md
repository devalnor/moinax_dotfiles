# Notification Center Design

Replace Mako/Dunst with SwayNC across all supported distros (Arch, Fedora, Debian/Ubuntu) to provide a unified notification center with a history drawer, Do Not Disturb, copy-to-clipboard, and Waybar integration — styled to match the existing Catppuccin Mocha/Latte design language.

## Requirements

1. **Left-click** on notification focuses the source app (SwayNC default behavior)
2. **Right-click** on notification closes it (SwayNC default behavior)
3. **Copy action** on each notification (popup + drawer) copies body text to clipboard via `wl-copy`
4. **Notification center drawer** accessible via `Mod+U` keybind and Waybar bell icon, showing all notifications (new and old) from the current session
5. **Do Not Disturb** toggle via `Mod+Alt+U` keybind and Waybar right-click
6. **Consistent styling** with existing Catppuccin Mocha (dark) / Latte (light) theme, using the repo's actual design tokens (translucent backgrounds, `#6464ff` accent, `8px` border-radius, FiraCode Nerd Font)

## Architecture

SwayNC is a GTK4-based notification daemon with a built-in control center drawer. It replaces both Mako (Arch/Fedora) and Dunst (Debian/Ubuntu), eliminating the distro-conditional template branching.

### New files

| File | Purpose |
|---|---|
| `home/dot_config/swaync/config.json` | Daemon behavior: positioning, timeouts, widgets, scripts, grouping |
| `home/dot_config/swaync/style-dark.css` | Dark theme (Catppuccin Mocha) — custom CSS |
| `home/dot_config/swaync/style-light.css` | Light theme (Catppuccin Latte) — custom CSS |
| `home/dot_local/bin/executable_swaync-copy.sh` | Copy notification body to clipboard via `wl-copy` |

### Removed files

| File | Reason |
|---|---|
| `home/dot_config/mako/config-dark` | Replaced by SwayNC |
| `home/dot_config/mako/config-light` | Replaced by SwayNC |

### Modified files

| File | Change |
|---|---|
| `home/dot_config/hypr/conf/autostart.conf.tmpl` | `exec-once = swaync` (remove mako/dunst conditional) |
| `home/dot_config/hypr/conf/binds.conf.tmpl` | Add `Mod+U` (toggle drawer), `Mod+Alt+U` (toggle DND); update `Mod+Shift+M` to reload swaync |
| `home/dot_config/hypr/scripts/executable_reload-mako.sh.tmpl` | Rename/replace: reload swaync instead of mako/dunst |
| `home/dot_config/niri/config.kdl.tmpl` | `spawn-at-startup "swaync"` (remove conditional); add keybindings; update reload |
| `home/dot_config/waybar/modules.jsonc.tmpl` | Add `custom/notification` module |
| `home/dot_config/waybar/config-hyprland.tmpl` | Add `custom/notification` to right section |
| `home/dot_config/waybar/config-niri.tmpl` | Add `custom/notification` to right section |
| `home/dot_config/waybar/style.css` (or `.tmpl`) | Add notification module CSS (bell icon states, DND styling) |
| `home/dot_local/bin/executable_apply-dark-mode.sh` | Replace mako section with SwayNC style swap + `swaync-client -rs` |
| `packages/groups/hyprland.yaml` | Replace mako/dunst with swaync packages |
| `packages/groups/niri.yaml` | Replace mako/dunst with swaync packages |
| `KEYBINDINGS.md` | Add `Mod+U`, `Mod+Alt+U`; update `Mod+Shift+M` description |

## SwayNC Configuration (`config.json`)

### Positioning & dimensions

- Popup notifications: top-right
- Control center drawer: right side
- Notification window width: 600px
- Control center width: 380px

### Timeouts (matching current mako values)

- Low urgency: 3000ms
- Normal urgency: 15000ms
- Critical urgency: 30000ms

### Notification behavior

- Grouping: enabled, by app-name
- Session history only (no persistence to disk)
- `volume-control` app-name: set to `transient` via `notification-visibility` (short-lived, no history — matching current mako behavior)
- Keyboard shortcuts enabled in control center

### Widgets (in drawer, top to bottom)

1. `title` — "Notifications" header with clear button
2. `dnd` — Do Not Disturb toggle switch
3. `notifications` — notification list
4. `mpris` — media player controls

### Copy script

SwayNC's `scripts` config fires a shell command on notification match. A `copy-notification` entry matches all notifications and provides a copy action. The script (`swaync-copy.sh`) receives the notification body, pipes it to `wl-copy`, and sends a brief transient confirmation notification.

## CSS Theming

Written from scratch (not forking the Catppuccin SwayNC theme) to match the repo's existing design tokens.

### Dark theme (`style-dark.css` — Catppuccin Mocha)

- **Font**: `FiraCode Nerd Font`, 14px
- **Control center**: `rgba(30, 30, 46, 0.85)` background, `8px` border-radius
- **Notification cards by urgency**:
  - Low: bg `rgba(100, 100, 255, 0.04)`, border `rgba(100, 100, 255, 0.25)`
  - Normal: bg `rgba(100, 100, 255, 0.08)`, border `rgba(137, 180, 250, 0.25)`
  - Critical: bg `rgba(243, 139, 168, 0.1)`, border `rgba(243, 139, 168, 0.4)`
- **Text**: primary `#cdd6f4`, secondary `#a6adc8`, body `#bac2de`
- **Buttons/actions**: `rgba(100, 100, 255, 0.2)` background, `#89b4fa` text
- **Hover**: increased opacity, `0.3s ease-in-out` transition
- **DND switch active**: `#6464ff`
- **MPRIS widget**: `rgba(100, 100, 255, 0.08)` background, `#89b4fa` controls
- **Close button**: `#f38ba8` background, `#1e1e2e` text
- **Scrollbar**: subtle, matching surface colors

### Light theme (`style-light.css` — Catppuccin Latte)

Same structure, swapping to Latte palette:

- **Control center**: `rgba(239, 241, 245, 0.85)` background
- **Text**: primary `#4c4f69`
- **Normal border**: `#1e66f5`, Critical border: `#fe640b`
- **Buttons**: `rgba(100, 100, 255, 0.15)`

## Waybar Integration

### Module: `custom/notification`

Placed in the right section of both waybar configs (Hyprland and Niri), near the system tray/clock.

- `exec`: `swaync-client -swb` (subscribe with Waybar JSON output)
- `return-type`: `json`
- `on-click`: `swaync-client -t` (toggle drawer)
- `on-click-right`: `swaync-client -d` (toggle DND)
- Format: ` {count}` when notifications exist, `` when empty

### Waybar CSS

SwayNC provides CSS classes via its Waybar output:

- `.notification` — has unread notifications: `#f5c2e7` (pink) text
- `.none` — no notifications: default/subdued color
- `.dnd-notification` — DND on + notifications: dimmed icon
- `.dnd-none` — DND on + empty: dimmed icon

Standard module background: `rgba(100, 100, 255, 0.3)`.

## Keybindings

### New

| Action | Hyprland | Niri | Notes |
|---|---|---|---|
| Toggle notification center | `Mod+U` | `Mod+U` | `swaync-client -t` |
| Toggle DND | `Mod+Alt+U` | `Mod+Alt+U` | `swaync-client -d` |

### Modified

| Action | Hyprland | Niri | Notes |
|---|---|---|---|
| Reload SwayNC | `Mod+Shift+M` | `Mod+Shift+M` | Was "Reload Mako"; now `swaync-client -R && swaync-client -rs` |

## Package Changes

### Package group YAMLs (hyprland.yaml, niri.yaml)

Remove mako/dunst entries. Add:

| Distro | Package name | Notes |
|---|---|---|
| Arch | `swaync` | Official repos |
| Fedora | `SwayNotificationCenter` | COPR: `erikreider/SwayNotificationCenter` |
| Debian | `sway-notification-center` | Official repos (Bookworm+) |

### Fedora COPR

The installer needs to enable the `erikreider/SwayNotificationCenter` COPR repo before installing. Follow the existing pattern in `install/distros/fedora.sh` for COPR enablement.

## Dark/Light Toggle Integration

The existing `Mod+N` toggle calls `apply-dark-mode.sh`, which uses a file copy pattern for each tool (e.g., `config-dark` → `config`). Replace the mako section in that script with SwayNC:

1. Copy `~/.config/swaync/style-dark.css` or `style-light.css` → `~/.config/swaync/style.css`
2. Reload CSS: `swaync-client -rs`

This follows the same pattern used for waybar (`style-{mode}.css` → `style.css`), wlogout, rofi, kitty, and eza in that script.

**Chezmoi source files** use the naming convention: `style.css` (active, not tracked), `style-dark.css` and `style-light.css` (source variants, tracked). The active file is generated at runtime by the toggle script.

## Template Simplification

The current mako/dunst distro conditional (`{{ if debian }} dunst {{ else }} mako {{ end }}`) used in autostart configs, reload scripts, and Niri config is removed. All distros use `swaync` unconditionally.
