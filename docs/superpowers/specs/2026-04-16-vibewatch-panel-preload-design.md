# Vibewatch Panel Preload — Embed GTK4 Panel in Daemon

**Date:** 2026-04-16
**Status:** Approved
**Repository:** ~/Projects/labs/vibewatch

## Problem

Every time the user clicks the Waybar vibewatch module, `toggle-panel` spawns a new `vibewatch panel` process. This pays the full GTK4/Libadwaita initialization cost (~0.5–1s) on every open. Closing kills the process, so the next open pays again.

## Solution

Embed the GTK4 panel directly into the daemon process. The window is created hidden at daemon startup and toggled visible/hidden on demand. This eliminates all process spawn overhead and makes the toggle instant.

## Architecture

### Main loop change

The daemon switches from a pure tokio async loop to a GTK `libadwaita::Application` as the outer event loop. Tokio runs on a background thread for IPC, scanning, and all async work. Communication between the tokio thread and GTK thread uses `glib::Sender`/`glib::Receiver` channels.

### Toggle flow

```
Waybar click → vibewatch toggle-panel (CLI)
    → connects to daemon socket, sends TogglePanel event
        → daemon IPC handler (tokio thread)
            → sends message via glib channel to GTK thread
                → window.set_visible(!window.is_visible())
```

### Session data flow

Before (socket-based polling between two processes):
```
panel process → socket → daemon → GetStatus → socket → panel
```

After (in-process direct access):
```
GTK glib::timeout (500ms) → registry.all() → rebuild_list()
```

The `SessionRegistry` is `Arc<Mutex<HashMap<...>>>`, already safe for cross-thread access. The GTK timeout locks the mutex briefly to snapshot sessions.

## File changes

### `src/main.rs`

- `run_daemon()` becomes GTK-driven: create `adw::Application`, spawn tokio runtime on background thread, start IPC server and scanner there.
- `TogglePanel` IPC handler sends a message via `glib::Sender` to the GTK thread instead of the current TODO comment.
- Remove `run_toggle_panel()` function (pgrep/pkill logic). Replace with a simple IPC send to daemon, same as `run_status()`.
- Remove the `Panel` variant from `Commands` enum. The standalone panel subcommand is no longer needed.

### `src/panel/mod.rs`

- Remove `run_panel()` (standalone GTK app launcher).
- Expose `create_panel(app: &adw::Application, registry: SessionRegistry) -> adw::ApplicationWindow` that builds the hidden window.

### `src/panel/window.rs`

- `build_window()` takes a `SessionRegistry` parameter instead of fetching sessions via socket IPC.
- Window starts hidden: `window.set_visible(false)` (remove `window.present()`).
- The 500ms `glib::timeout_add_local` reads directly from `registry.all()` instead of calling `fetch_sessions()` (which connected to the socket).
- Remove `fetch_sessions()` function entirely.
- Add visibility-aware polling: skip `registry.all()` when the window is hidden to avoid unnecessary work.

### `Cargo.toml`

No changes needed. The `panel` feature is already in `default` features and already pulls in `gtk4`, `libadwaita`, and `gtk4-layer-shell`.

### Waybar config (`home/dot_config/waybar/modules.jsonc.tmpl`)

No changes needed. The `on-click` still runs `vibewatch toggle-panel`, which now sends an IPC event to the daemon.

## Threading model

```
Main thread (GTK):
  - adw::Application main loop
  - Window rendering, show/hide
  - 500ms timer reads SessionRegistry

Background thread (tokio):
  - IPC server (Unix socket accept loop)
  - Scanner (process discovery)
  - Sound player
  - Sends TogglePanel signal to GTK thread via glib channel
```

## Edge cases

- **Daemon started without display:** If `$WAYLAND_DISPLAY` is unset (e.g., SSH session), GTK init will fail. The daemon should check this env var before attempting GTK initialization. If absent, fall back to the current pure-tokio loop (IPC + scanner only, no panel window). This preserves the ability to run the daemon for status output without a graphical session.
- **Panel visibility on workspace switch:** Layer shell overlay windows are compositor-managed. No special handling needed.
- **Multiple toggle-panel clicks in rapid succession:** `set_visible(!is_visible())` is idempotent per call. Rapid clicks just flip back and forth.

## What gets removed

- `Commands::Panel` subcommand and its `#[cfg(feature = "panel")]` gate
- `panel::run_panel()` function
- `run_toggle_panel()` function (pgrep/pkill logic)
- `window::fetch_sessions()` function (socket-based session fetching)
- The `Subscribe` IPC event becomes unused (panel no longer connects as a streaming client). Can be kept for future external consumers or removed.
