# Vibewatch Panel Preload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Embed the GTK4 panel into the vibewatch daemon process so toggling the panel is instant show/hide instead of spawning/killing a separate process each time.

**Architecture:** The daemon's main loop switches from pure tokio to a GTK `adw::Application`. Tokio runs on a background thread for IPC, scanning, and sound. A `glib::Sender` channel lets the tokio IPC handler signal the GTK thread to toggle panel visibility. The panel window is created hidden at startup and shown/hidden via `window.set_visible()`.

**Tech Stack:** Rust, GTK4 (gtk4-rs 0.9), Libadwaita (libadwaita 0.7), gtk4-layer-shell 0.5, tokio 1, glib channels

**Repository:** ~/Projects/labs/vibewatch

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `src/main.rs` | Modify | Switch `run_daemon()` to GTK-driven, remove `run_toggle_panel()` pgrep/pkill, remove `Panel` command, simplify `TogglePanel` to IPC send |
| `src/panel/mod.rs` | Modify | Remove `run_panel()`, expose `create_panel()` that returns a hidden window |
| `src/panel/window.rs` | Modify | Take `SessionRegistry` directly, start hidden, remove `fetch_sessions()`, add visibility-aware polling |
| `src/config.rs` | Modify | Add `Clone` derive to `Config` (needed to pass config into background thread) |

---

### Task 1: Add Clone derive to Config

The daemon needs to clone `Config` to pass it into both the background tokio thread and use it on the main GTK thread. Currently `Config` only derives `Debug, Deserialize`.

**Files:**
- Modify: `src/config.rs:7` (Config struct derive)
- Modify: `src/config.rs:13` (GeneralConfig struct derive)
- Modify: `src/config.rs:29` (AgentConfig struct derive)

- [ ] **Step 1: Add Clone derive to Config, GeneralConfig, and AgentConfig**

In `src/config.rs`, change the derives:

```rust
// Line 7 — Config
#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct Config {

// Line 13 — GeneralConfig
#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct GeneralConfig {

// Line 29 — AgentConfig (already has no Clone)
#[derive(Debug, Clone, Deserialize)]
pub struct AgentConfig {
```

`SoundConfig` already derives `Clone`.

- [ ] **Step 2: Verify it compiles**

Run: `cargo check`
Expected: Compiles with no errors.

- [ ] **Step 3: Commit**

```bash
git add src/config.rs
git commit -m "feat: add Clone derive to Config structs for shared ownership"
```

---

### Task 2: Refactor panel/window.rs to accept SessionRegistry directly

Change the panel window from fetching sessions via IPC socket to reading them directly from a shared `SessionRegistry`. The window starts hidden and skips polling when not visible.

**Files:**
- Modify: `src/panel/window.rs`

- [ ] **Step 1: Change `build_window` signature to take `SessionRegistry`**

Replace the entire `build_window` function signature and body in `src/panel/window.rs`. The function now takes `(app, registry)` instead of just `(app)`, starts hidden, and reads sessions directly from the registry:

```rust
use gtk4 as gtk;
use gtk4_layer_shell::LayerShell;
use libadwaita as adw;

use adw::prelude::*;

use crate::session::SessionRegistry;

use super::session_row;

pub fn build_window(app: &adw::Application, registry: SessionRegistry) -> adw::ApplicationWindow {
    let window = adw::ApplicationWindow::builder()
        .application(app)
        .title("vibewatch")
        .build();
    // Set only width, let height be driven by content
    window.set_size_request(360, 1);

    // Layer shell setup
    window.init_layer_shell();
    window.set_layer(gtk4_layer_shell::Layer::Overlay);
    window.set_anchor(gtk4_layer_shell::Edge::Top, true);
    window.set_anchor(gtk4_layer_shell::Edge::Right, true);
    window.set_margin(gtk4_layer_shell::Edge::Top, 8);
    window.set_margin(gtk4_layer_shell::Edge::Right, 8);
    window.set_exclusive_zone(0);
    window.set_keyboard_mode(gtk4_layer_shell::KeyboardMode::OnDemand);
    window.set_namespace(Some("vibewatch"));

    // Load CSS
    let css_provider = gtk::CssProvider::new();
    css_provider.load_from_string(include_str!("../../assets/style.css"));
    gtk::style_context_add_provider_for_display(
        &gtk::gdk::Display::default().unwrap(),
        &css_provider,
        gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );

    // Main layout box
    let main_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    main_box.add_css_class("main-box");
    main_box.set_vexpand(false);

    // Session list
    let session_list = gtk::ListBox::new();
    session_list.set_selection_mode(gtk::SelectionMode::None);
    session_list.add_css_class("session-list");

    let empty_label = gtk::Label::new(Some("No agents running"));
    empty_label.add_css_class("empty-state");
    session_list.set_placeholder(Some(&empty_label));

    main_box.append(&session_list);
    window.set_content(Some(&main_box));

    // Poll registry every 500ms, only rebuild if data changed
    // Skip polling when window is hidden to avoid unnecessary work
    let list_ref = session_list;
    let win_ref = window.clone();
    let last_snapshot: std::rc::Rc<std::cell::RefCell<String>> =
        std::rc::Rc::new(std::cell::RefCell::new(String::new()));
    gtk::glib::timeout_add_local(std::time::Duration::from_millis(500), move || {
        // Skip polling when hidden
        if !win_ref.is_visible() {
            // Clear snapshot so we rebuild immediately when shown again
            *last_snapshot.borrow_mut() = String::new();
            return gtk::glib::ControlFlow::Continue;
        }

        let sessions = registry.all();
        let snapshot = serde_json::to_string(&sessions).unwrap_or_default();
        let mut prev = last_snapshot.borrow_mut();
        if *prev != snapshot {
            *prev = snapshot;
            drop(prev);
            rebuild_list(&list_ref, &sessions);
            // Resize window height to match content
            let win = win_ref.clone();
            gtk::glib::idle_add_local_once(move || {
                if let Some(content) = win.content() {
                    let (_, natural) = content.preferred_size();
                    let h = natural.height().max(1);
                    win.set_size_request(360, h);
                }
            });
        }
        gtk::glib::ControlFlow::Continue
    });

    // Start hidden — daemon will toggle visibility via IPC
    window.set_visible(false);

    window
}

/// Rebuild the list from scratch with new session data.
fn rebuild_list(list: &gtk::ListBox, sessions: &[crate::session::Session]) {
    while let Some(row) = list.row_at_index(0) {
        list.remove(&row);
    }
    for session in sessions {
        let row = session_row::build_row(session);
        list.append(&row);
    }
}
```

This replaces the entire file. Key changes:
- Import `SessionRegistry` instead of `Config`, `InboundEvent`, `StatusResponse`, `Session`
- `build_window` takes `registry: SessionRegistry`, returns `adw::ApplicationWindow`
- Window starts with `set_visible(false)` instead of `present()`
- Polling reads `registry.all()` directly instead of `fetch_sessions()` via socket
- Skips polling when window is hidden, clears snapshot cache so first poll after show triggers a rebuild
- `fetch_sessions()` function removed entirely

- [ ] **Step 2: Verify it compiles**

Run: `cargo check`
Expected: May show warnings about unused imports in `panel/mod.rs` — that's expected, we'll fix it in Task 3.

- [ ] **Step 3: Commit**

```bash
git add src/panel/window.rs
git commit -m "refactor: panel reads SessionRegistry directly, starts hidden"
```

---

### Task 3: Refactor panel/mod.rs to expose create_panel()

Replace the standalone `run_panel()` with a `create_panel()` function that the daemon calls during `connect_activate`.

**Files:**
- Modify: `src/panel/mod.rs`

- [ ] **Step 1: Replace panel/mod.rs contents**

Replace the entire `src/panel/mod.rs` with:

```rust
pub mod session_row;
pub mod window;

use libadwaita as adw;

use crate::session::SessionRegistry;

/// Create the panel window (hidden). Call from the daemon's GTK `connect_activate`.
/// Returns the window handle so the daemon can toggle its visibility.
pub fn create_panel(app: &adw::Application, registry: SessionRegistry) -> adw::ApplicationWindow {
    window::build_window(app, registry)
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cargo check`
Expected: Compiles cleanly. The old `run_panel()` and its `adw::prelude::*` import are gone.

- [ ] **Step 3: Commit**

```bash
git add src/panel/mod.rs
git commit -m "refactor: replace run_panel() with create_panel() for daemon embedding"
```

---

### Task 4: Rewrite the daemon to use GTK main loop with background tokio

This is the core change. The daemon starts as an `adw::Application`, spawns tokio on a background thread, and uses a `glib::Sender` to signal the GTK thread for panel toggle.

**Files:**
- Modify: `src/main.rs`

- [ ] **Step 1: Rewrite main.rs**

Replace the full contents of `src/main.rs`:

```rust
mod compositor;
mod config;
mod ipc;
mod notify;
mod scanner;
mod session;
mod sound;
mod waybar;

#[cfg(feature = "panel")]
mod panel;

use std::sync::Arc;

use clap::{Parser, Subcommand};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::unix::OwnedReadHalf;

use config::Config;
use ipc::{InboundEvent, IpcServer, SessionUpdate};
use session::{AgentKind, Session, SessionRegistry, SessionStatus};
use sound::{SoundEvent, SoundPlayer};

#[derive(Parser)]
#[command(name = "vibewatch", about = "AI agent monitor for Wayland compositors")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the vibewatch daemon
    Daemon,
    /// Send a notification event from a hook
    Notify {
        /// The event payload (JSON string)
        event: String,
        /// Agent type
        #[arg(long, default_value = "claude-code")]
        agent: String,
    },
    /// Print current session status
    Status,
    /// Toggle the overlay panel visibility
    TogglePanel,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Daemon => run_daemon(),
        Commands::Notify { event, agent } => {
            tokio::runtime::Runtime::new()?.block_on(notify::handle_notify(&event, &agent))
        }
        Commands::Status => {
            tokio::runtime::Runtime::new()?.block_on(run_status())
        }
        Commands::TogglePanel => {
            tokio::runtime::Runtime::new()?.block_on(run_toggle_panel())
        }
    }
}

/// Messages sent from the tokio IPC thread to the GTK main thread.
#[cfg(feature = "panel")]
enum GtkMessage {
    TogglePanel,
}

fn run_daemon() -> anyhow::Result<()> {
    let config = Config::load()?;
    let registry = SessionRegistry::new();

    // Check if we have a graphical session for the panel
    let has_display = std::env::var("WAYLAND_DISPLAY").is_ok();

    if has_display {
        #[cfg(feature = "panel")]
        return run_daemon_with_panel(config, registry);
    }

    // Headless mode: pure tokio, no GTK
    eprintln!("vibewatch: no WAYLAND_DISPLAY, running in headless mode (no panel)");
    tokio::runtime::Runtime::new()?.block_on(run_daemon_headless(config, registry))
}

/// Headless daemon: pure tokio loop, no GTK. Used when WAYLAND_DISPLAY is unset.
async fn run_daemon_headless(config: Config, registry: SessionRegistry) -> anyhow::Result<()> {
    let socket_path = config.socket_path();
    let sound_player = Arc::new(SoundPlayer::new(config.sounds.clone()));

    eprintln!(
        "vibewatch: starting daemon (headless), socket at {}",
        socket_path.display()
    );

    let server = IpcServer::bind(&socket_path)?;

    let compositor = compositor::create_compositor(&config.general.compositor)?;
    let scanner_registry = registry.clone();
    tokio::spawn(async move {
        scanner::run_scanner(scanner_registry, compositor, config).await;
    });

    eprintln!("vibewatch: daemon ready (headless)");

    loop {
        match server.accept().await {
            Ok(stream) => {
                let registry = registry.clone();
                let sound_player = sound_player.clone();
                tokio::spawn(async move {
                    handle_connection(stream, registry, sound_player, None::<Arc<dyn Fn() + Send + Sync>>).await;
                });
            }
            Err(e) => eprintln!("vibewatch: accept error: {}", e),
        }
    }
}

/// GTK-driven daemon: adw::Application is the outer loop, tokio runs on a background thread.
#[cfg(feature = "panel")]
fn run_daemon_with_panel(config: Config, registry: SessionRegistry) -> anyhow::Result<()> {
    use libadwaita as adw;
    use adw::prelude::*;
    use gtk4::glib;

    let app = adw::Application::builder()
        .application_id("app.vibewatch.daemon")
        .build();

    let config_clone = config.clone();
    let registry_clone = registry.clone();

    app.connect_activate(move |app| {
        // Create the panel window (hidden)
        let window = panel::create_panel(app, registry_clone.clone());

        // Set up glib channel for tokio → GTK communication
        let (gtk_sender, gtk_receiver) = glib::MainContext::channel::<GtkMessage>(glib::Priority::DEFAULT);

        let win_ref = window.clone();
        gtk_receiver.attach(None, move |msg| {
            match msg {
                GtkMessage::TogglePanel => {
                    win_ref.set_visible(!win_ref.is_visible());
                }
            }
            glib::ControlFlow::Continue
        });

        // Spawn tokio runtime on a background thread
        let config = config_clone.clone();
        let registry = registry_clone.clone();
        std::thread::spawn(move || {
            let rt = tokio::runtime::Runtime::new().expect("failed to create tokio runtime");
            rt.block_on(async move {
                let socket_path = config.socket_path();
                let sound_player = Arc::new(SoundPlayer::new(config.sounds.clone()));

                eprintln!(
                    "vibewatch: starting daemon, socket at {}",
                    socket_path.display()
                );

                let server = match IpcServer::bind(&socket_path) {
                    Ok(s) => s,
                    Err(e) => {
                        eprintln!("vibewatch: failed to bind socket: {}", e);
                        return;
                    }
                };

                let compositor = match compositor::create_compositor(&config.general.compositor) {
                    Ok(c) => c,
                    Err(e) => {
                        eprintln!("vibewatch: failed to create compositor: {}", e);
                        return;
                    }
                };

                let scanner_registry = registry.clone();
                tokio::spawn(async move {
                    scanner::run_scanner(scanner_registry, compositor, config).await;
                });

                eprintln!("vibewatch: daemon ready");

                loop {
                    match server.accept().await {
                        Ok(stream) => {
                            let registry = registry.clone();
                            let sound_player = sound_player.clone();
                            let sender = gtk_sender.clone();
                            let toggle_fn: Arc<dyn Fn() + Send + Sync> = Arc::new(move || {
                                let _ = sender.send(GtkMessage::TogglePanel);
                            });
                            tokio::spawn(async move {
                                handle_connection(stream, registry, sound_player, Some(toggle_fn)).await;
                            });
                        }
                        Err(e) => eprintln!("vibewatch: accept error: {}", e),
                    }
                }
            });
        });
    });

    app.run_with_args::<String>(&[]);
    Ok(())
}

/// Read one JSON line from an OwnedReadHalf and parse it as an InboundEvent.
async fn read_event_from_reader(
    reader: &mut BufReader<OwnedReadHalf>,
) -> anyhow::Result<InboundEvent> {
    let mut line = String::new();
    let n = reader.read_line(&mut line).await?;
    if n == 0 {
        anyhow::bail!("connection closed");
    }
    let event: InboundEvent = serde_json::from_str(line.trim())?;
    Ok(event)
}

/// Handle a single client connection.
///
/// `toggle_sender` is `Some` when running with a panel (GTK mode), `None` in headless mode.
/// The sender type is erased to `Box<dyn Fn() + Send>` so this function compiles
/// without GTK feature flags.
async fn handle_connection(
    stream: tokio::net::UnixStream,
    registry: SessionRegistry,
    sound_player: Arc<SoundPlayer>,
    toggle_sender: Option<Arc<dyn Fn() + Send + Sync>>,
) {
    let (read_half, mut write_half) = stream.into_split();
    let mut reader = BufReader::new(read_half);

    loop {
        let event = match read_event_from_reader(&mut reader).await {
            Ok(e) => e,
            Err(_) => return,
        };

        match event {
            InboundEvent::SessionStart {
                agent,
                session_id,
                pid,
                cwd,
                session_name,
            } => {
                registry.remove_by_pid(pid);
                let kind = parse_agent_kind(&agent);
                let mut session = Session::new(session_id, kind, pid);
                session.cwd = cwd;
                session.session_name = session_name;
                session.terminal = Some(session::detect_terminal(pid));
                registry.register(session);
            }
            InboundEvent::PreToolUse {
                session_id,
                tool,
                detail,
            } => {
                if let Some(mut session) = get_session(&registry, &session_id) {
                    session.status = SessionStatus::Executing;
                    session.current_tool = Some(tool);
                    session.tool_detail = detail;
                    session.touch();
                    registry.register(session);
                }
            }
            InboundEvent::PostToolUse {
                session_id,
                tool: _,
                success,
            } => {
                if let Some(mut session) = get_session(&registry, &session_id) {
                    session.last_tool = session.current_tool.take();
                    session.last_tool_detail = session.tool_detail.take();
                    session.status = SessionStatus::Thinking;
                    session.touch();
                    registry.register(session);
                }
                if !success {
                    sound_player.play(SoundEvent::Error);
                }
            }
            InboundEvent::UserPromptSubmit { session_id, prompt } => {
                if let Some(mut session) = get_session(&registry, &session_id) {
                    session.status = SessionStatus::Thinking;
                    session.last_prompt = prompt;
                    session.current_tool = None;
                    session.tool_detail = None;
                    if let Some(name) = read_transcript_name(&session_id) {
                        session.session_name = Some(name);
                    }
                    session.touch();
                    registry.register(session);
                }
            }
            InboundEvent::PermissionRequest { session_id, tool } => {
                if let Some(mut session) = get_session(&registry, &session_id) {
                    session.status = SessionStatus::WaitingApproval;
                    session.current_tool = tool;
                    session.touch();
                    registry.register(session);
                    sound_player.play(SoundEvent::ApprovalNeeded);
                }
            }
            InboundEvent::PermissionDenied { session_id } => {
                if let Some(mut session) = registry.get(&session_id) {
                    session.status = SessionStatus::Thinking;
                    session.current_tool = None;
                    session.tool_detail = None;
                    session.touch();
                    registry.register(session);
                }
            }
            InboundEvent::Stop { session_id } => {
                if let Some(mut session) = registry.get(&session_id) {
                    session.status = SessionStatus::Idle;
                    session.current_tool = None;
                    session.tool_detail = None;
                    session.touch();
                    registry.register(session);
                }
            }
            InboundEvent::GetStatus => {
                let sessions = registry.all();
                let status = waybar::build_status(&sessions);
                let mut json = serde_json::to_string(&status).unwrap_or_default();
                json.push('\n');
                let _ = write_half.write_all(json.as_bytes()).await;
                let _ = write_half.flush().await;
                return;
            }
            InboundEvent::Subscribe => {
                loop {
                    let sessions = registry.all();
                    let update = SessionUpdate { sessions };
                    let mut json = serde_json::to_string(&update).unwrap_or_default();
                    json.push('\n');
                    if write_half.write_all(json.as_bytes()).await.is_err() {
                        return;
                    }
                    if write_half.flush().await.is_err() {
                        return;
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                }
            }
            InboundEvent::TogglePanel => {
                if let Some(ref sender) = toggle_sender {
                    sender();
                }
            }
        }
    }
}

/// Get an existing session by ID.
fn get_session(registry: &SessionRegistry, session_id: &str) -> Option<Session> {
    registry.get(session_id)
}

/// Find the transcript for a hook session and read its name.
fn read_transcript_name(session_id: &str) -> Option<String> {
    let claude_projects = dirs::home_dir()?.join(".claude/projects");
    for project in std::fs::read_dir(&claude_projects).ok()?.flatten() {
        let transcript = project.path().join(format!("{}.jsonl", session_id));
        if transcript.exists() {
            let content = std::fs::read_to_string(&transcript).ok()?;
            for line in content.lines().rev() {
                if line.contains("\"custom-title\"") {
                    if let Ok(val) = serde_json::from_str::<serde_json::Value>(line) {
                        if let Some(title) = val.get("customTitle").and_then(|v| v.as_str()) {
                            return Some(title.to_string());
                        }
                    }
                }
            }
            return None;
        }
    }
    None
}

fn parse_agent_kind(s: &str) -> AgentKind {
    match s {
        "claude_code" | "claude-code" => AgentKind::ClaudeCode,
        "codex" => AgentKind::Codex,
        "cursor" => AgentKind::Cursor,
        "webstorm" => AgentKind::WebStorm,
        _ => AgentKind::ClaudeCode,
    }
}

/// Connect to the daemon and print current status as Waybar JSON.
async fn run_status() -> anyhow::Result<()> {
    let config = Config::load()?;
    let socket_path = config.socket_path();

    match ipc::send_event(&socket_path, &InboundEvent::GetStatus).await {
        Ok(Some(response)) => {
            println!("{}", response);
        }
        Ok(None) => {
            waybar::print_waybar_status(&[]);
        }
        Err(_) => {
            waybar::print_waybar_status(&[]);
        }
    }

    Ok(())
}

/// Toggle the panel by sending a TogglePanel IPC event to the daemon.
async fn run_toggle_panel() -> anyhow::Result<()> {
    let config = Config::load()?;
    let socket_path = config.socket_path();

    if let Err(e) = ipc::send_event(&socket_path, &InboundEvent::TogglePanel).await {
        eprintln!("vibewatch: failed to toggle panel: {}", e);
        eprintln!("vibewatch: is the daemon running?");
    }

    Ok(())
}
```

Key changes from the original:
1. **`main()` is no longer `#[tokio::main]`** — it's a plain `fn main()` because the GTK path uses `app.run()` as the outer loop. Non-daemon commands create their own tokio runtime.
2. **`Commands::Panel` removed** — no standalone panel subcommand.
3. **`run_daemon()` detects display** — checks `WAYLAND_DISPLAY` to decide GTK vs headless mode.
4. **`run_daemon_with_panel()`** — creates `adw::Application`, spawns tokio on background thread, wires up `glib::MainContext::channel` for toggle signaling.
5. **`handle_connection()` takes `toggle_sender: Option<Arc<dyn Fn() + Send + Sync>>`** — type-erased closure avoids `#[cfg]` on parameters. In GTK mode, the closure sends `GtkMessage::TogglePanel` via the glib channel. In headless mode, it's `None`.
6. **`run_toggle_panel()` rewritten** — sends `TogglePanel` IPC event to daemon instead of pgrep/pkill.

- [ ] **Step 2: Verify it compiles**

Run: `cargo check`
Expected: Compiles with no errors.

- [ ] **Step 3: Run existing tests**

Run: `cargo test`
Expected: All existing tests pass. The unit tests (session, waybar, ipc, config, sound, compositor) and integration test don't depend on the daemon startup path.

- [ ] **Step 4: Commit**

```bash
git add src/main.rs
git commit -m "feat: embed GTK4 panel in daemon, instant show/hide toggle"
```

---

### Task 5: Build release and manual smoke test

Verify the full binary builds and the toggle works end-to-end.

**Files:**
- No file changes — testing only

- [ ] **Step 1: Build release binary**

Run: `cargo build --release`
Expected: Compiles successfully. Binary at `target/release/vibewatch`.

- [ ] **Step 2: Install the binary**

Run: `cargo install --path .`
Expected: Installs to `~/.cargo/bin/vibewatch`.

- [ ] **Step 3: Verify CLI help shows no `panel` subcommand**

Run: `~/.cargo/bin/vibewatch --help`
Expected: Shows `daemon`, `notify`, `status`, `toggle-panel`. Does NOT show `panel`.

- [ ] **Step 4: Manual smoke test (if graphical session available)**

If running in a graphical Wayland session:

1. Kill any existing vibewatch daemon: `pkill -f "vibewatch daemon"` (if running)
2. Start daemon: `~/.cargo/bin/vibewatch daemon &`
3. Wait for "daemon ready" message in stderr
4. Toggle panel: `~/.cargo/bin/vibewatch toggle-panel`
5. Panel should appear instantly (no loading delay)
6. Toggle again: `~/.cargo/bin/vibewatch toggle-panel`
7. Panel should hide instantly
8. Toggle a third time to confirm it reappears
9. Kill daemon: `pkill -f "vibewatch daemon"`

- [ ] **Step 5: Commit (tag the working state)**

```bash
git commit --allow-empty -m "test: verified panel preload works — instant toggle"
```
