# Vibewatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Rust daemon + GTK4 overlay that monitors AI coding agent sessions on Hyprland/Niri, shows live status in Waybar, and lets you jump to agent windows.

**Architecture:** A tokio-based daemon receives events from Claude Code/Codex hooks via a Unix socket, tracks session state in an in-memory registry, and serves status to a Waybar custom module and a GTK4 layer-shell overlay panel. Process scanning detects Cursor/WebStorm windows. Compositor-specific backends (Hyprland, Niri) handle window focusing.

**Tech Stack:** Rust 2021, tokio, gtk4-rs 0.8, gtk4-layer-shell 0.8, libadwaita 0.6, hyprland-rs 0.3, rodio, clap 4, serde/serde_json, toml, dirs

**Spec:** `docs/superpowers/specs/2026-04-16-vibewatch-design.md`

---

## File Structure

```
~/projects/vibewatch/
├── Cargo.toml
├── src/
│   ├── main.rs                # CLI entry point (clap subcommands)
│   ├── config.rs              # TOML config parsing
│   ├── session.rs             # Session, AgentKind, SessionStatus types + registry
│   ├── ipc.rs                 # Unix socket server + client helpers
│   ├── notify.rs              # `vibewatch notify` subcommand (hook stdin parsing)
│   ├── scanner.rs             # Background process/window scanner
│   ├── compositor/
│   │   ├── mod.rs             # Compositor trait + auto-detection
│   │   ├── hyprland.rs        # Hyprland IPC backend
│   │   └── niri.rs            # Niri IPC backend
│   ├── sound.rs               # Sound alert system (rodio)
│   ├── waybar.rs              # `vibewatch status` JSON output
│   └── panel/
│       ├── mod.rs             # GTK4 panel application setup
│       ├── window.rs          # Layer-shell window creation
│       └── session_row.rs     # Per-session row widget
├── assets/
│   ├── sounds/
│   │   ├── chime.wav
│   │   ├── success.wav
│   │   └── alert.wav
│   └── style.css              # Panel CSS (Catppuccin Mocha/Latte)
├── contrib/
│   ├── vibewatch.service      # systemd user unit
│   └── waybar-module.jsonc    # Example Waybar module config
├── tests/
│   └── integration_test.rs    # End-to-end IPC tests
└── README.md
```

---

## Task 1: Project Scaffold + Core Types

**Files:**
- Create: `~/projects/vibewatch/Cargo.toml`
- Create: `~/projects/vibewatch/src/main.rs`
- Create: `~/projects/vibewatch/src/session.rs`

- [ ] **Step 1: Create project directory and init git**

```bash
mkdir -p ~/projects/vibewatch
cd ~/projects/vibewatch
git init
```

- [ ] **Step 2: Write Cargo.toml**

Create `Cargo.toml`:

```toml
[package]
name = "vibewatch"
version = "0.1.0"
edition = "2021"
description = "AI agent monitor for Wayland compositors"
license = "MIT"
repository = "https://github.com/moinax/vibewatch"

[dependencies]
clap = { version = "4", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
toml = "0.8"
tokio = { version = "1", features = ["full"] }
dirs = "6"
thiserror = "2"

# Compositor
hyprland = { version = "0.3", features = ["tokio"], optional = true }

# GUI (optional, only for panel subcommand)
gtk4 = { version = "0.8", optional = true }
libadwaita = { version = "0.6", optional = true }
gtk4-layer-shell = { version = "0.8", optional = true }

# Audio
rodio = { version = "0.19", optional = true }

[features]
default = ["panel", "sound", "hyprland-backend"]
panel = ["dep:gtk4", "dep:libadwaita", "dep:gtk4-layer-shell"]
sound = ["dep:rodio"]
hyprland-backend = ["dep:hyprland"]
```

- [ ] **Step 3: Write core types in session.rs with tests**

Create `src/session.rs`:

```rust
use serde::{Deserialize, Serialize};
use std::time::Instant;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AgentKind {
    ClaudeCode,
    Codex,
    Cursor,
    WebStorm,
}

impl AgentKind {
    pub fn display_name(&self) -> &'static str {
        match self {
            AgentKind::ClaudeCode => "Claude Code",
            AgentKind::Codex => "Codex",
            AgentKind::Cursor => "Cursor",
            AgentKind::WebStorm => "WebStorm",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionStatus {
    Thinking,
    Executing,
    WaitingApproval,
    Idle,
    Running,
    Stopped,
}

impl SessionStatus {
    pub fn css_class(&self) -> &'static str {
        match self {
            SessionStatus::Executing => "executing",
            SessionStatus::WaitingApproval => "attention",
            SessionStatus::Thinking => "thinking",
            SessionStatus::Running => "running",
            SessionStatus::Idle | SessionStatus::Stopped => "idle",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: String,
    pub agent: AgentKind,
    pub status: SessionStatus,
    pub current_tool: Option<String>,
    pub tool_detail: Option<String>,
    pub window_id: Option<String>,
    pub pid: u32,
    #[serde(skip)]
    pub started_at: Option<Instant>,
    #[serde(skip)]
    pub last_event: Option<Instant>,
}

impl Session {
    pub fn new(id: String, agent: AgentKind, pid: u32) -> Self {
        let now = Instant::now();
        Self {
            id,
            agent,
            pid,
            status: SessionStatus::Idle,
            current_tool: None,
            tool_detail: None,
            window_id: None,
            started_at: Some(now),
            last_event: Some(now),
        }
    }

    pub fn touch(&mut self) {
        self.last_event = Some(Instant::now());
    }

    pub fn status_line(&self) -> String {
        let status = match self.status {
            SessionStatus::Executing => {
                if let Some(ref tool) = self.current_tool {
                    if let Some(ref detail) = self.tool_detail {
                        format!("executing {}: {}", tool, detail)
                    } else {
                        format!("executing {}", tool)
                    }
                } else {
                    "executing".to_string()
                }
            }
            SessionStatus::Thinking => "thinking".to_string(),
            SessionStatus::WaitingApproval => "waiting for approval".to_string(),
            SessionStatus::Idle => "idle".to_string(),
            SessionStatus::Running => "running".to_string(),
            SessionStatus::Stopped => "stopped".to_string(),
        };
        format!("{}: {}", self.agent.display_name(), status)
    }
}

/// Thread-safe session registry
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Debug, Clone)]
pub struct SessionRegistry {
    sessions: Arc<RwLock<HashMap<String, Session>>>,
}

impl SessionRegistry {
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub async fn register(&self, session: Session) {
        self.sessions.write().await.insert(session.id.clone(), session);
    }

    pub async fn update_status(
        &self,
        session_id: &str,
        status: SessionStatus,
        tool: Option<String>,
        detail: Option<String>,
    ) -> bool {
        let mut sessions = self.sessions.write().await;
        if let Some(session) = sessions.get_mut(session_id) {
            session.status = status;
            session.current_tool = tool;
            session.tool_detail = detail;
            session.touch();
            true
        } else {
            false
        }
    }

    pub async fn remove(&self, session_id: &str) -> Option<Session> {
        self.sessions.write().await.remove(session_id)
    }

    pub async fn get(&self, session_id: &str) -> Option<Session> {
        self.sessions.read().await.get(session_id).cloned()
    }

    pub async fn all(&self) -> Vec<Session> {
        self.sessions.read().await.values().cloned().collect()
    }

    pub async fn active_count(&self) -> usize {
        self.sessions.read().await.values()
            .filter(|s| s.status != SessionStatus::Stopped)
            .count()
    }

    /// Remove sessions whose PID is no longer running
    pub async fn cleanup_dead(&self) -> Vec<String> {
        let mut sessions = self.sessions.write().await;
        let dead: Vec<String> = sessions.iter()
            .filter(|(_, s)| !is_pid_alive(s.pid))
            .map(|(id, _)| id.clone())
            .collect();
        for id in &dead {
            sessions.remove(id);
        }
        dead
    }

    pub async fn set_window_id(&self, session_id: &str, window_id: String) {
        if let Some(session) = self.sessions.write().await.get_mut(session_id) {
            session.window_id = Some(window_id);
        }
    }
}

fn is_pid_alive(pid: u32) -> bool {
    std::path::Path::new(&format!("/proc/{}", pid)).exists()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_agent_display_name() {
        assert_eq!(AgentKind::ClaudeCode.display_name(), "Claude Code");
        assert_eq!(AgentKind::Codex.display_name(), "Codex");
        assert_eq!(AgentKind::Cursor.display_name(), "Cursor");
        assert_eq!(AgentKind::WebStorm.display_name(), "WebStorm");
    }

    #[test]
    fn test_session_status_line() {
        let mut session = Session::new("test-1".into(), AgentKind::ClaudeCode, 1234);
        assert_eq!(session.status_line(), "Claude Code: idle");

        session.status = SessionStatus::Executing;
        session.current_tool = Some("Bash".into());
        session.tool_detail = Some("npm test".into());
        assert_eq!(session.status_line(), "Claude Code: executing Bash: npm test");
    }

    #[test]
    fn test_session_status_css_class() {
        assert_eq!(SessionStatus::Executing.css_class(), "executing");
        assert_eq!(SessionStatus::WaitingApproval.css_class(), "attention");
        assert_eq!(SessionStatus::Thinking.css_class(), "thinking");
        assert_eq!(SessionStatus::Idle.css_class(), "idle");
    }

    #[tokio::test]
    async fn test_registry_register_and_get() {
        let registry = SessionRegistry::new();
        let session = Session::new("s1".into(), AgentKind::ClaudeCode, 1000);
        registry.register(session).await;

        let got = registry.get("s1").await.unwrap();
        assert_eq!(got.agent, AgentKind::ClaudeCode);
        assert_eq!(got.pid, 1000);
    }

    #[tokio::test]
    async fn test_registry_update_status() {
        let registry = SessionRegistry::new();
        registry.register(Session::new("s1".into(), AgentKind::Codex, 2000)).await;

        let updated = registry.update_status(
            "s1",
            SessionStatus::Executing,
            Some("Bash".into()),
            Some("cargo test".into()),
        ).await;
        assert!(updated);

        let got = registry.get("s1").await.unwrap();
        assert_eq!(got.status, SessionStatus::Executing);
        assert_eq!(got.current_tool.as_deref(), Some("Bash"));
    }

    #[tokio::test]
    async fn test_registry_update_nonexistent_returns_false() {
        let registry = SessionRegistry::new();
        let updated = registry.update_status("nope", SessionStatus::Idle, None, None).await;
        assert!(!updated);
    }

    #[tokio::test]
    async fn test_registry_remove() {
        let registry = SessionRegistry::new();
        registry.register(Session::new("s1".into(), AgentKind::Cursor, 3000)).await;
        let removed = registry.remove("s1").await;
        assert!(removed.is_some());
        assert!(registry.get("s1").await.is_none());
    }

    #[tokio::test]
    async fn test_registry_active_count() {
        let registry = SessionRegistry::new();
        registry.register(Session::new("s1".into(), AgentKind::ClaudeCode, 1000)).await;
        registry.register(Session::new("s2".into(), AgentKind::Codex, 2000)).await;
        assert_eq!(registry.active_count().await, 2);

        registry.update_status("s1", SessionStatus::Stopped, None, None).await;
        assert_eq!(registry.active_count().await, 1);
    }

    #[test]
    fn test_is_pid_alive() {
        // PID 1 (init/systemd) should always be alive
        assert!(is_pid_alive(1));
        // PID max should not be alive
        assert!(!is_pid_alive(u32::MAX));
    }
}
```

- [ ] **Step 4: Write minimal main.rs**

Create `src/main.rs`:

```rust
mod config;
mod session;
mod ipc;
mod notify;
mod scanner;
mod waybar;
mod sound;
mod compositor;

#[cfg(feature = "panel")]
mod panel;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "vibewatch", version, about = "AI agent monitor for Wayland")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the vibewatch daemon
    Daemon,
    /// Send a hook notification to the daemon (called by agent hooks)
    Notify {
        /// Event type: session-start, pre-tool-use, post-tool-use, stop
        event: String,
        /// Agent type: claude-code, codex
        #[arg(long, default_value = "claude-code")]
        agent: String,
    },
    /// Output JSON status for Waybar custom module
    Status,
    /// Toggle the overlay panel visibility
    TogglePanel,
    /// Launch the overlay panel (usually started by the daemon)
    Panel,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Daemon => todo!("Task 4"),
        Commands::Notify { event, agent } => todo!("Task 5"),
        Commands::Status => todo!("Task 6"),
        Commands::TogglePanel => todo!("Task 8"),
        Commands::Panel => todo!("Task 9"),
    }
}
```

Add `anyhow = "1"` to `[dependencies]` in `Cargo.toml`.

- [ ] **Step 5: Verify it compiles and tests pass**

```bash
cd ~/projects/vibewatch
cargo test
```

Expected: all tests in `session.rs` pass. Compilation succeeds (with warnings about unused modules — that's fine, they're empty).

- [ ] **Step 6: Create empty module files**

Create each of these as empty files with just a comment:

- `src/config.rs` — `// Configuration parsing`
- `src/ipc.rs` — `// Unix socket IPC`
- `src/notify.rs` — `// Hook notification handling`
- `src/scanner.rs` — `// Process/window scanning`
- `src/waybar.rs` — `// Waybar status output`
- `src/sound.rs` — `// Sound alert system`
- `src/compositor/mod.rs` — `// Compositor abstraction`
- `src/compositor/hyprland.rs` — `// Hyprland backend`
- `src/compositor/niri.rs` — `// Niri backend`
- `src/panel/mod.rs` — `// GTK4 panel app`
- `src/panel/window.rs` — `// Layer-shell window`
- `src/panel/session_row.rs` — `// Session row widget`

- [ ] **Step 7: Add .gitignore and commit**

Create `.gitignore`:

```
/target
```

```bash
git add -A
git commit -m "feat: project scaffold with core session types and registry"
```

---

## Task 2: Configuration

**Files:**
- Create: `src/config.rs`

- [ ] **Step 1: Write config tests**

Replace `src/config.rs` with:

```rust
use serde::Deserialize;
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Debug, Deserialize)]
#[serde(default)]
pub struct Config {
    pub general: GeneralConfig,
    pub sounds: SoundConfig,
    pub agents: HashMap<String, AgentConfig>,
}

#[derive(Debug, Deserialize)]
#[serde(default)]
pub struct GeneralConfig {
    pub compositor: String,
    pub socket_path: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(default)]
pub struct SoundConfig {
    pub enabled: bool,
    pub approval_needed: String,
    pub task_complete: String,
    pub error: String,
}

#[derive(Debug, Deserialize)]
pub struct AgentConfig {
    pub window_class: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            general: GeneralConfig::default(),
            sounds: SoundConfig::default(),
            agents: HashMap::new(),
        }
    }
}

impl Default for GeneralConfig {
    fn default() -> Self {
        Self {
            compositor: "auto".to_string(),
            socket_path: None,
        }
    }
}

impl Default for SoundConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            approval_needed: "builtin:chime".to_string(),
            task_complete: "builtin:success".to_string(),
            error: "builtin:alert".to_string(),
        }
    }
}

impl Config {
    pub fn load() -> Self {
        let path = Self::config_path();
        if path.exists() {
            let content = std::fs::read_to_string(&path).unwrap_or_default();
            toml::from_str(&content).unwrap_or_default()
        } else {
            Config::default()
        }
    }

    pub fn config_path() -> PathBuf {
        dirs::config_dir()
            .unwrap_or_else(|| PathBuf::from("~/.config"))
            .join("vibewatch")
            .join("config.toml")
    }

    pub fn socket_path() -> PathBuf {
        if let Ok(runtime_dir) = std::env::var("XDG_RUNTIME_DIR") {
            PathBuf::from(runtime_dir).join("vibewatch.sock")
        } else {
            PathBuf::from("/tmp").join(format!("vibewatch-{}.sock", whoami()))
        }
    }
}

fn whoami() -> String {
    std::env::var("USER").unwrap_or_else(|_| "unknown".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert_eq!(config.general.compositor, "auto");
        assert!(config.sounds.enabled);
        assert_eq!(config.sounds.approval_needed, "builtin:chime");
        assert!(config.agents.is_empty());
    }

    #[test]
    fn test_parse_full_config() {
        let toml_str = r#"
[general]
compositor = "hyprland"

[sounds]
enabled = false
approval_needed = "/home/user/chime.wav"
task_complete = "builtin:success"
error = "builtin:alert"

[agents.cursor]
window_class = "cursor"

[agents.webstorm]
window_class = "jetbrains-webstorm"
"#;
        let config: Config = toml::from_str(toml_str).unwrap();
        assert_eq!(config.general.compositor, "hyprland");
        assert!(!config.sounds.enabled);
        assert_eq!(config.sounds.approval_needed, "/home/user/chime.wav");
        assert_eq!(config.agents["cursor"].window_class, "cursor");
        assert_eq!(config.agents["webstorm"].window_class, "jetbrains-webstorm");
    }

    #[test]
    fn test_parse_empty_config() {
        let config: Config = toml::from_str("").unwrap();
        assert_eq!(config.general.compositor, "auto");
        assert!(config.sounds.enabled);
    }

    #[test]
    fn test_parse_partial_config() {
        let toml_str = r#"
[sounds]
enabled = false
"#;
        let config: Config = toml::from_str(toml_str).unwrap();
        assert_eq!(config.general.compositor, "auto");
        assert!(!config.sounds.enabled);
        assert_eq!(config.sounds.task_complete, "builtin:success");
    }

    #[test]
    fn test_socket_path_uses_xdg() {
        std::env::set_var("XDG_RUNTIME_DIR", "/run/user/1000");
        let path = Config::socket_path();
        assert_eq!(path, PathBuf::from("/run/user/1000/vibewatch.sock"));
    }
}
```

- [ ] **Step 2: Run tests**

```bash
cargo test config
```

Expected: all 5 config tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/config.rs
git commit -m "feat: add TOML configuration parsing with defaults"
```

---

## Task 3: IPC Protocol (Unix Socket Server + Client)

**Files:**
- Create: `src/ipc.rs`

- [ ] **Step 1: Write IPC types and server**

Replace `src/ipc.rs` with:

```rust
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::broadcast;

/// Inbound event from hooks
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum InboundEvent {
    SessionStart {
        agent: String,
        session_id: String,
        pid: u32,
    },
    PreToolUse {
        session_id: String,
        tool: String,
        #[serde(default)]
        detail: Option<String>,
    },
    PostToolUse {
        session_id: String,
        tool: String,
        #[serde(default)]
        success: bool,
    },
    Stop {
        session_id: String,
    },
    /// Internal: request status (from waybar/panel)
    GetStatus,
    /// Internal: toggle panel visibility
    TogglePanel,
    /// Internal: subscribe to live updates
    Subscribe,
}

/// Outbound state snapshot for Waybar/panel
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatusResponse {
    pub text: String,
    pub tooltip: String,
    pub class: String,
    pub sessions: Vec<crate::session::Session>,
}

/// Broadcasts session changes to subscribers (panel)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionUpdate {
    pub sessions: Vec<crate::session::Session>,
}

pub struct IpcServer {
    listener: UnixListener,
    socket_path: PathBuf,
}

impl IpcServer {
    pub fn bind(path: &Path) -> std::io::Result<Self> {
        // Remove stale socket file if it exists
        if path.exists() {
            std::fs::remove_file(path)?;
        }
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).ok();
        }
        let listener = std::os::unix::net::UnixListener::bind(path)?;
        listener.set_nonblocking(true)?;
        let listener = UnixListener::from_std(listener)?;
        Ok(Self {
            listener,
            socket_path: path.to_path_buf(),
        })
    }

    pub async fn accept(&self) -> std::io::Result<UnixStream> {
        let (stream, _) = self.listener.accept().await?;
        Ok(stream)
    }

    pub fn path(&self) -> &Path {
        &self.socket_path
    }
}

impl Drop for IpcServer {
    fn drop(&mut self) {
        std::fs::remove_file(&self.socket_path).ok();
    }
}

/// Read a single JSON line from a stream
pub async fn read_event(stream: &mut BufReader<UnixStream>) -> std::io::Result<Option<InboundEvent>> {
    let mut line = String::new();
    let bytes = stream.read_line(&mut line).await?;
    if bytes == 0 {
        return Ok(None);
    }
    serde_json::from_str(line.trim())
        .map(Some)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
}

/// Write a JSON line to a stream
pub async fn write_json<T: Serialize>(stream: &mut UnixStream, value: &T) -> std::io::Result<()> {
    let mut json = serde_json::to_string(value)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    json.push('\n');
    stream.write_all(json.as_bytes()).await?;
    stream.flush().await
}

/// Send a single event to the daemon (used by `vibewatch notify` and `vibewatch status`)
pub async fn send_event(socket_path: &Path, event: &InboundEvent) -> anyhow::Result<Option<String>> {
    let mut stream = UnixStream::connect(socket_path).await?;
    let json = serde_json::to_string(event)?;
    stream.write_all(json.as_bytes()).await?;
    stream.write_all(b"\n").await?;
    stream.flush().await?;

    // Read response if any
    let mut reader = BufReader::new(stream);
    let mut response = String::new();
    let bytes = reader.read_line(&mut response).await?;
    if bytes > 0 {
        Ok(Some(response.trim().to_string()))
    } else {
        Ok(None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_parse_session_start() {
        let json = r#"{"event":"session_start","agent":"claude_code","session_id":"abc123","pid":1234}"#;
        let event: InboundEvent = serde_json::from_str(json).unwrap();
        match event {
            InboundEvent::SessionStart { agent, session_id, pid } => {
                assert_eq!(agent, "claude_code");
                assert_eq!(session_id, "abc123");
                assert_eq!(pid, 1234);
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn test_parse_pre_tool_use() {
        let json = r#"{"event":"pre_tool_use","session_id":"abc123","tool":"Bash","detail":"npm test"}"#;
        let event: InboundEvent = serde_json::from_str(json).unwrap();
        match event {
            InboundEvent::PreToolUse { session_id, tool, detail } => {
                assert_eq!(session_id, "abc123");
                assert_eq!(tool, "Bash");
                assert_eq!(detail.as_deref(), Some("npm test"));
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn test_parse_stop() {
        let json = r#"{"event":"stop","session_id":"abc123"}"#;
        let event: InboundEvent = serde_json::from_str(json).unwrap();
        match event {
            InboundEvent::Stop { session_id } => {
                assert_eq!(session_id, "abc123");
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn test_serialize_status_response() {
        let resp = StatusResponse {
            text: "\u{f544} 2".to_string(),
            tooltip: "Claude Code: executing Bash".to_string(),
            class: "active".to_string(),
            sessions: vec![],
        };
        let json = serde_json::to_string(&resp).unwrap();
        assert!(json.contains("active"));
    }

    #[tokio::test]
    async fn test_server_bind_and_connect() {
        let tmp = TempDir::new().unwrap();
        let sock_path = tmp.path().join("test.sock");

        let server = IpcServer::bind(&sock_path).unwrap();
        assert!(sock_path.exists());

        // Connect from client side
        let client_task = tokio::spawn({
            let path = sock_path.clone();
            async move {
                let mut stream = UnixStream::connect(&path).await.unwrap();
                stream.write_all(b"{\"event\":\"get_status\"}\n").await.unwrap();
            }
        });

        let _stream = server.accept().await.unwrap();
        client_task.await.unwrap();
    }

    #[tokio::test]
    async fn test_read_write_event() {
        let tmp = TempDir::new().unwrap();
        let sock_path = tmp.path().join("test.sock");
        let server = IpcServer::bind(&sock_path).unwrap();

        let client_task = tokio::spawn({
            let path = sock_path.clone();
            async move {
                let mut stream = UnixStream::connect(&path).await.unwrap();
                let event = InboundEvent::Stop { session_id: "s1".into() };
                write_json(&mut stream, &event).await.unwrap();
            }
        });

        let stream = server.accept().await.unwrap();
        let mut reader = BufReader::new(stream);
        let event = read_event(&mut reader).await.unwrap().unwrap();
        match event {
            InboundEvent::Stop { session_id } => assert_eq!(session_id, "s1"),
            _ => panic!("wrong variant"),
        }
        client_task.await.unwrap();
    }
}
```

Add `tempfile = "3"` to `[dev-dependencies]` in `Cargo.toml`, and `anyhow = "1"` to `[dependencies]` if not already there.

- [ ] **Step 2: Run tests**

```bash
cargo test ipc
```

Expected: all 6 IPC tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/ipc.rs Cargo.toml
git commit -m "feat: add Unix socket IPC server with JSON-line protocol"
```

---

## Task 4: Notify Subcommand (Hook Integration)

**Files:**
- Create: `src/notify.rs`

- [ ] **Step 1: Write notify module with hook JSON parsing**

Replace `src/notify.rs` with:

```rust
use crate::config::Config;
use crate::ipc::{InboundEvent, send_event};
use serde::Deserialize;
use std::io::Read;

/// Claude Code hook JSON envelope (received on stdin)
#[derive(Debug, Deserialize)]
pub struct ClaudeCodeHook {
    pub session_id: String,
    pub hook_event_name: String,
    #[serde(default)]
    pub tool_name: Option<String>,
    #[serde(default)]
    pub tool_input: Option<serde_json::Value>,
    #[serde(default)]
    pub tool_response: Option<serde_json::Value>,
    #[serde(default)]
    pub cwd: Option<String>,
}

/// Codex hook JSON envelope (received on stdin)
#[derive(Debug, Deserialize)]
pub struct CodexHook {
    pub session_id: String,
    #[serde(default)]
    pub tool_name: Option<String>,
    #[serde(default)]
    pub tool_input: Option<serde_json::Value>,
    #[serde(default)]
    pub tool_response: Option<serde_json::Value>,
}

/// Read stdin and parse as hook JSON, then send to daemon.
pub async fn handle_notify(event_type: &str, agent: &str) -> anyhow::Result<()> {
    let mut stdin_buf = String::new();
    std::io::stdin().read_to_string(&mut stdin_buf)?;

    let ipc_event = match agent {
        "claude-code" | "claude_code" => parse_claude_code(&stdin_buf, event_type)?,
        "codex" => parse_codex(&stdin_buf, event_type)?,
        other => anyhow::bail!("unknown agent: {}", other),
    };

    let socket_path = Config::socket_path();
    send_event(&socket_path, &ipc_event).await?;
    Ok(())
}

fn parse_claude_code(stdin: &str, event_type: &str) -> anyhow::Result<InboundEvent> {
    let hook: ClaudeCodeHook = serde_json::from_str(stdin)?;
    let pid = std::process::id(); // hook runs in the claude process tree

    match event_type {
        "session-start" => Ok(InboundEvent::SessionStart {
            agent: "claude_code".to_string(),
            session_id: hook.session_id,
            pid,
        }),
        "pre-tool-use" => {
            let detail = extract_tool_detail(&hook.tool_input);
            Ok(InboundEvent::PreToolUse {
                session_id: hook.session_id,
                tool: hook.tool_name.unwrap_or_else(|| "unknown".to_string()),
                detail,
            })
        }
        "post-tool-use" => {
            let success = hook.tool_response
                .as_ref()
                .and_then(|r| r.get("success"))
                .and_then(|v| v.as_bool())
                .unwrap_or(true);
            Ok(InboundEvent::PostToolUse {
                session_id: hook.session_id,
                tool: hook.tool_name.unwrap_or_else(|| "unknown".to_string()),
                success,
            })
        }
        "stop" => Ok(InboundEvent::Stop {
            session_id: hook.session_id,
        }),
        other => anyhow::bail!("unknown event type: {}", other),
    }
}

fn parse_codex(stdin: &str, event_type: &str) -> anyhow::Result<InboundEvent> {
    let hook: CodexHook = serde_json::from_str(stdin)?;
    let pid = std::process::id();

    match event_type {
        "session-start" => Ok(InboundEvent::SessionStart {
            agent: "codex".to_string(),
            session_id: hook.session_id,
            pid,
        }),
        "pre-tool-use" => {
            let detail = extract_tool_detail(&hook.tool_input);
            Ok(InboundEvent::PreToolUse {
                session_id: hook.session_id,
                tool: hook.tool_name.unwrap_or_else(|| "unknown".to_string()),
                detail,
            })
        }
        "post-tool-use" => {
            let success = hook.tool_response
                .as_ref()
                .and_then(|r| r.get("success"))
                .and_then(|v| v.as_bool())
                .unwrap_or(true);
            Ok(InboundEvent::PostToolUse {
                session_id: hook.session_id,
                tool: hook.tool_name.unwrap_or_else(|| "unknown".to_string()),
                success,
            })
        }
        "stop" => Ok(InboundEvent::Stop {
            session_id: hook.session_id,
        }),
        other => anyhow::bail!("unknown event type: {}", other),
    }
}

fn extract_tool_detail(tool_input: &Option<serde_json::Value>) -> Option<String> {
    let input = tool_input.as_ref()?;
    // Try common fields: command (Bash), file_path (Edit/Write/Read)
    if let Some(cmd) = input.get("command").and_then(|v| v.as_str()) {
        // Truncate long commands
        let truncated = if cmd.len() > 80 {
            format!("{}...", &cmd[..77])
        } else {
            cmd.to_string()
        };
        return Some(truncated);
    }
    if let Some(path) = input.get("file_path").and_then(|v| v.as_str()) {
        return Some(path.to_string());
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_claude_code_session_start() {
        let stdin = r#"{
            "session_id": "abc123",
            "hook_event_name": "SessionStart",
            "cwd": "/home/user/project",
            "permission_mode": "default",
            "source": "startup",
            "model": "claude-sonnet-4-6"
        }"#;
        let event = parse_claude_code(stdin, "session-start").unwrap();
        match event {
            InboundEvent::SessionStart { agent, session_id, .. } => {
                assert_eq!(agent, "claude_code");
                assert_eq!(session_id, "abc123");
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn test_parse_claude_code_pre_tool_use() {
        let stdin = r#"{
            "session_id": "abc123",
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "tool_input": {"command": "npm test"},
            "tool_use_id": "toolu_01ABC",
            "cwd": "/home/user/project",
            "permission_mode": "default"
        }"#;
        let event = parse_claude_code(stdin, "pre-tool-use").unwrap();
        match event {
            InboundEvent::PreToolUse { session_id, tool, detail } => {
                assert_eq!(session_id, "abc123");
                assert_eq!(tool, "Bash");
                assert_eq!(detail.as_deref(), Some("npm test"));
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn test_parse_claude_code_post_tool_use() {
        let stdin = r#"{
            "session_id": "abc123",
            "hook_event_name": "PostToolUse",
            "tool_name": "Write",
            "tool_input": {"file_path": "/tmp/test.rs", "content": "fn main() {}"},
            "tool_response": {"success": true},
            "tool_use_id": "toolu_01ABC",
            "cwd": "/home/user/project",
            "permission_mode": "default"
        }"#;
        let event = parse_claude_code(stdin, "post-tool-use").unwrap();
        match event {
            InboundEvent::PostToolUse { session_id, tool, success } => {
                assert_eq!(session_id, "abc123");
                assert_eq!(tool, "Write");
                assert!(success);
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn test_parse_codex_pre_tool_use() {
        let stdin = r#"{
            "session_id": "codex-001",
            "tool_name": "Bash",
            "tool_input": {"command": "cargo build"}
        }"#;
        let event = parse_codex(stdin, "pre-tool-use").unwrap();
        match event {
            InboundEvent::PreToolUse { session_id, tool, detail } => {
                assert_eq!(session_id, "codex-001");
                assert_eq!(tool, "Bash");
                assert_eq!(detail.as_deref(), Some("cargo build"));
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn test_extract_tool_detail_command() {
        let input = serde_json::json!({"command": "npm test"});
        assert_eq!(extract_tool_detail(&Some(input)).as_deref(), Some("npm test"));
    }

    #[test]
    fn test_extract_tool_detail_file_path() {
        let input = serde_json::json!({"file_path": "/src/main.rs", "content": "..."});
        assert_eq!(extract_tool_detail(&Some(input)).as_deref(), Some("/src/main.rs"));
    }

    #[test]
    fn test_extract_tool_detail_truncates_long_commands() {
        let long_cmd = "a".repeat(100);
        let input = serde_json::json!({"command": long_cmd});
        let detail = extract_tool_detail(&Some(input)).unwrap();
        assert_eq!(detail.len(), 80);
        assert!(detail.ends_with("..."));
    }

    #[test]
    fn test_extract_tool_detail_none() {
        assert!(extract_tool_detail(&None).is_none());
        let input = serde_json::json!({"something_else": true});
        assert!(extract_tool_detail(&Some(input)).is_none());
    }

    #[test]
    fn test_unknown_agent_errors() {
        let stdin = r#"{"session_id": "x"}"#;
        let result = parse_claude_code(stdin, "invalid-event");
        assert!(result.is_err());
    }
}
```

- [ ] **Step 2: Run tests**

```bash
cargo test notify
```

Expected: all 9 notify tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/notify.rs
git commit -m "feat: add hook notification parsing for Claude Code and Codex"
```

---

## Task 5: Compositor Abstraction + Backends

**Files:**
- Create: `src/compositor/mod.rs`
- Create: `src/compositor/hyprland.rs`
- Create: `src/compositor/niri.rs`

- [ ] **Step 1: Write compositor trait and detection**

Replace `src/compositor/mod.rs` with:

```rust
pub mod hyprland;
pub mod niri;

use anyhow::Result;
use serde::Deserialize;

/// A window discovered by the compositor
#[derive(Debug, Clone)]
pub struct CompositorWindow {
    pub id: String,
    pub pid: u32,
    pub app_id: String,
    pub title: String,
    pub workspace: String,
}

/// Abstraction over compositor IPC
#[async_trait::async_trait]
pub trait Compositor: Send + Sync {
    /// List all windows
    async fn list_windows(&self) -> Result<Vec<CompositorWindow>>;

    /// Focus a window by its compositor ID
    async fn focus_window(&self, window_id: &str) -> Result<()>;

    /// Focus a window by PID (finds the window first)
    async fn focus_by_pid(&self, pid: u32) -> Result<()> {
        let windows = self.list_windows().await?;
        if let Some(win) = windows.iter().find(|w| w.pid == pid) {
            self.focus_window(&win.id).await
        } else {
            anyhow::bail!("no window found for PID {}", pid)
        }
    }

    /// Focus a window by app_id/window class
    async fn focus_by_class(&self, class: &str) -> Result<()> {
        let windows = self.list_windows().await?;
        if let Some(win) = windows.iter().find(|w| w.app_id == class) {
            self.focus_window(&win.id).await
        } else {
            anyhow::bail!("no window found for class {}", class)
        }
    }

    /// Find windows matching an app_id
    async fn find_by_class(&self, class: &str) -> Result<Vec<CompositorWindow>> {
        let windows = self.list_windows().await?;
        Ok(windows.into_iter().filter(|w| w.app_id == class).collect())
    }

    /// Find window for a given PID
    async fn find_by_pid(&self, pid: u32) -> Result<Option<CompositorWindow>> {
        let windows = self.list_windows().await?;
        Ok(windows.into_iter().find(|w| w.pid == pid))
    }
}

/// Detect which compositor is running
pub fn detect_compositor() -> Option<String> {
    // Check XDG_CURRENT_DESKTOP first
    if let Ok(desktop) = std::env::var("XDG_CURRENT_DESKTOP") {
        let lower = desktop.to_lowercase();
        if lower.contains("hyprland") {
            return Some("hyprland".to_string());
        }
        if lower.contains("niri") {
            return Some("niri".to_string());
        }
    }
    // Check HYPRLAND_INSTANCE_SIGNATURE
    if std::env::var("HYPRLAND_INSTANCE_SIGNATURE").is_ok() {
        return Some("hyprland".to_string());
    }
    // Check NIRI_SOCKET
    if std::env::var("NIRI_SOCKET").is_ok() {
        return Some("niri".to_string());
    }
    None
}

/// Create the appropriate compositor backend
pub fn create_compositor(name: &str) -> Result<Box<dyn Compositor>> {
    match name {
        "hyprland" => Ok(Box::new(hyprland::HyprlandCompositor::new())),
        "niri" => Ok(Box::new(niri::NiriCompositor::new())),
        "auto" => {
            if let Some(detected) = detect_compositor() {
                create_compositor(&detected)
            } else {
                anyhow::bail!("could not detect compositor — set compositor in config.toml")
            }
        }
        other => anyhow::bail!("unsupported compositor: {}", other),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_hyprland_via_env() {
        std::env::set_var("HYPRLAND_INSTANCE_SIGNATURE", "test");
        std::env::remove_var("NIRI_SOCKET");
        std::env::remove_var("XDG_CURRENT_DESKTOP");
        assert_eq!(detect_compositor(), Some("hyprland".to_string()));
        std::env::remove_var("HYPRLAND_INSTANCE_SIGNATURE");
    }

    #[test]
    fn test_detect_niri_via_env() {
        std::env::remove_var("HYPRLAND_INSTANCE_SIGNATURE");
        std::env::set_var("NIRI_SOCKET", "/tmp/niri.sock");
        std::env::remove_var("XDG_CURRENT_DESKTOP");
        assert_eq!(detect_compositor(), Some("niri".to_string()));
        std::env::remove_var("NIRI_SOCKET");
    }

    #[test]
    fn test_detect_via_xdg_desktop() {
        std::env::remove_var("HYPRLAND_INSTANCE_SIGNATURE");
        std::env::remove_var("NIRI_SOCKET");
        std::env::set_var("XDG_CURRENT_DESKTOP", "Hyprland");
        assert_eq!(detect_compositor(), Some("hyprland".to_string()));
        std::env::set_var("XDG_CURRENT_DESKTOP", "niri");
        assert_eq!(detect_compositor(), Some("niri".to_string()));
        std::env::remove_var("XDG_CURRENT_DESKTOP");
    }
}
```

Add `async-trait = "0.1"` to `[dependencies]` in `Cargo.toml`.

- [ ] **Step 2: Write Hyprland backend**

Replace `src/compositor/hyprland.rs` with:

```rust
use super::{Compositor, CompositorWindow};
use anyhow::Result;
use tokio::process::Command;

pub struct HyprlandCompositor;

impl HyprlandCompositor {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait::async_trait]
impl Compositor for HyprlandCompositor {
    async fn list_windows(&self) -> Result<Vec<CompositorWindow>> {
        let output = Command::new("hyprctl")
            .args(["clients", "-j"])
            .output()
            .await?;
        if !output.status.success() {
            anyhow::bail!("hyprctl clients failed: {}", String::from_utf8_lossy(&output.stderr));
        }
        let clients: Vec<HyprClient> = serde_json::from_slice(&output.stdout)?;
        Ok(clients.into_iter().map(|c| CompositorWindow {
            id: format!("address:{}", c.address),
            pid: c.pid,
            app_id: c.class,
            title: c.title,
            workspace: c.workspace.name,
        }).collect())
    }

    async fn focus_window(&self, window_id: &str) -> Result<()> {
        let output = Command::new("hyprctl")
            .args(["dispatch", "focuswindow", window_id])
            .output()
            .await?;
        if !output.status.success() {
            anyhow::bail!("hyprctl dispatch focuswindow failed");
        }
        Ok(())
    }

    async fn focus_by_pid(&self, pid: u32) -> Result<()> {
        let output = Command::new("hyprctl")
            .args(["dispatch", "focuswindow", &format!("pid:{}", pid)])
            .output()
            .await?;
        if !output.status.success() {
            anyhow::bail!("hyprctl dispatch focuswindow pid:{} failed", pid);
        }
        Ok(())
    }
}

#[derive(Debug, serde::Deserialize)]
struct HyprClient {
    address: String,
    pid: u32,
    class: String,
    title: String,
    workspace: HyprWorkspace,
}

#[derive(Debug, serde::Deserialize)]
struct HyprWorkspace {
    name: String,
}
```

- [ ] **Step 3: Write Niri backend**

Replace `src/compositor/niri.rs` with:

```rust
use super::{Compositor, CompositorWindow};
use anyhow::Result;
use tokio::process::Command;

pub struct NiriCompositor;

impl NiriCompositor {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait::async_trait]
impl Compositor for NiriCompositor {
    async fn list_windows(&self) -> Result<Vec<CompositorWindow>> {
        let output = Command::new("niri")
            .args(["msg", "-j", "windows"])
            .output()
            .await?;
        if !output.status.success() {
            anyhow::bail!("niri msg windows failed: {}", String::from_utf8_lossy(&output.stderr));
        }
        let windows: Vec<NiriWindow> = serde_json::from_slice(&output.stdout)?;
        Ok(windows.into_iter().map(|w| CompositorWindow {
            id: w.id.to_string(),
            pid: w.pid.unwrap_or(0),
            app_id: w.app_id.unwrap_or_default(),
            title: w.title.unwrap_or_default(),
            workspace: w.workspace_id.map(|id| id.to_string()).unwrap_or_default(),
        }).collect())
    }

    async fn focus_window(&self, window_id: &str) -> Result<()> {
        let output = Command::new("niri")
            .args(["msg", "action", "focus-window", "--id", window_id])
            .output()
            .await?;
        if !output.status.success() {
            anyhow::bail!("niri msg focus-window failed");
        }
        Ok(())
    }
}

#[derive(Debug, serde::Deserialize)]
struct NiriWindow {
    id: u64,
    pid: Option<u32>,
    app_id: Option<String>,
    title: Option<String>,
    workspace_id: Option<u64>,
}
```

- [ ] **Step 4: Run tests**

```bash
cargo test compositor
```

Expected: 3 compositor detection tests pass. The Hyprland/Niri backends can't be unit-tested without the compositors running — they'll be validated during integration testing.

- [ ] **Step 5: Commit**

```bash
git add src/compositor/ Cargo.toml
git commit -m "feat: add compositor abstraction with Hyprland and Niri backends"
```

---

## Task 6: Waybar Status Output

**Files:**
- Create: `src/waybar.rs`

- [ ] **Step 1: Write waybar status module with tests**

Replace `src/waybar.rs` with:

```rust
use crate::ipc::StatusResponse;
use crate::session::{Session, SessionRegistry, SessionStatus};

pub fn build_status(sessions: &[Session]) -> StatusResponse {
    let active: Vec<&Session> = sessions.iter()
        .filter(|s| s.status != SessionStatus::Stopped)
        .collect();

    let count = active.len();

    let text = if count == 0 {
        "\u{f544}".to_string() // nf-md-robot icon, no count
    } else {
        format!("\u{f544} {}", count)
    };

    let tooltip = if active.is_empty() {
        "No agents running".to_string()
    } else {
        active.iter()
            .map(|s| s.status_line())
            .collect::<Vec<_>>()
            .join("\n")
    };

    let class = if active.iter().any(|s| s.status == SessionStatus::WaitingApproval) {
        "attention".to_string()
    } else if count > 0 {
        "active".to_string()
    } else {
        "idle".to_string()
    };

    StatusResponse {
        text,
        tooltip,
        class,
        sessions: sessions.to_vec(),
    }
}

/// Output Waybar-compatible JSON to stdout
pub fn print_waybar_status(sessions: &[Session]) {
    let status = build_status(sessions);
    // Waybar custom module expects: {"text": "...", "tooltip": "...", "class": "..."}
    let waybar_json = serde_json::json!({
        "text": status.text,
        "tooltip": status.tooltip,
        "class": status.class,
    });
    println!("{}", waybar_json);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session::{AgentKind, Session, SessionStatus};

    fn make_session(id: &str, agent: AgentKind, status: SessionStatus) -> Session {
        let mut s = Session::new(id.into(), agent, 1000);
        s.status = status;
        s
    }

    #[test]
    fn test_empty_status() {
        let status = build_status(&[]);
        assert_eq!(status.text, "\u{f544}");
        assert_eq!(status.tooltip, "No agents running");
        assert_eq!(status.class, "idle");
    }

    #[test]
    fn test_active_agents() {
        let sessions = vec![
            make_session("s1", AgentKind::ClaudeCode, SessionStatus::Executing),
            make_session("s2", AgentKind::Codex, SessionStatus::Thinking),
        ];
        let status = build_status(&sessions);
        assert_eq!(status.text, "\u{f544} 2");
        assert_eq!(status.class, "active");
        assert!(status.tooltip.contains("Claude Code"));
        assert!(status.tooltip.contains("Codex"));
    }

    #[test]
    fn test_attention_class_when_waiting_approval() {
        let sessions = vec![
            make_session("s1", AgentKind::ClaudeCode, SessionStatus::WaitingApproval),
        ];
        let status = build_status(&sessions);
        assert_eq!(status.class, "attention");
    }

    #[test]
    fn test_stopped_sessions_excluded_from_count() {
        let sessions = vec![
            make_session("s1", AgentKind::ClaudeCode, SessionStatus::Executing),
            make_session("s2", AgentKind::Codex, SessionStatus::Stopped),
        ];
        let status = build_status(&sessions);
        assert_eq!(status.text, "\u{f544} 1");
    }

    #[test]
    fn test_status_with_tool_detail() {
        let mut session = make_session("s1", AgentKind::ClaudeCode, SessionStatus::Executing);
        session.current_tool = Some("Bash".into());
        session.tool_detail = Some("npm test".into());
        let status = build_status(&[session]);
        assert!(status.tooltip.contains("executing Bash: npm test"));
    }
}
```

- [ ] **Step 2: Run tests**

```bash
cargo test waybar
```

Expected: all 5 waybar tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/waybar.rs
git commit -m "feat: add Waybar status JSON output"
```

---

## Task 7: Process Scanner

**Files:**
- Create: `src/scanner.rs`

- [ ] **Step 1: Write scanner module**

Replace `src/scanner.rs` with:

```rust
use crate::compositor::Compositor;
use crate::config::Config;
use crate::session::{AgentKind, Session, SessionRegistry, SessionStatus};
use std::collections::HashSet;
use tokio::time::{interval, Duration};

/// Known CLI agent process names
const CLAUDE_CODE_NAMES: &[&str] = &["claude"];
const CODEX_NAMES: &[&str] = &["codex"];

/// Scan /proc for running agent processes
pub fn scan_agent_processes() -> Vec<(AgentKind, u32)> {
    let mut found = Vec::new();
    let Ok(entries) = std::fs::read_dir("/proc") else {
        return found;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        // Only look at numeric directories (PIDs)
        let Ok(pid) = name_str.parse::<u32>() else {
            continue;
        };
        let comm_path = entry.path().join("comm");
        let Ok(comm) = std::fs::read_to_string(&comm_path) else {
            continue;
        };
        let comm = comm.trim();
        if CLAUDE_CODE_NAMES.iter().any(|n| comm == *n) {
            found.push((AgentKind::ClaudeCode, pid));
        } else if CODEX_NAMES.iter().any(|n| comm == *n) {
            found.push((AgentKind::Codex, pid));
        }
    }
    found
}

/// Background scanner task
pub async fn run_scanner(
    registry: SessionRegistry,
    compositor: Box<dyn Compositor>,
    config: Config,
) {
    let mut tick = interval(Duration::from_secs(3));
    loop {
        tick.tick().await;

        // 1. Clean up dead sessions
        registry.cleanup_dead().await;

        // 2. Scan for CLI agent processes not yet registered
        let processes = scan_agent_processes();
        let known_pids: HashSet<u32> = registry.all().await.iter().map(|s| s.pid).collect();
        for (agent, pid) in processes {
            if !known_pids.contains(&pid) {
                let session = Session::new(
                    format!("scan-{}-{}", agent_str(&agent), pid),
                    agent,
                    pid,
                );
                registry.register(session).await;
            }
        }

        // 3. Scan for GUI agent windows (Cursor, WebStorm)
        for (name, agent_config) in &config.agents {
            let agent_kind = match name.as_str() {
                "cursor" => AgentKind::Cursor,
                "webstorm" => AgentKind::WebStorm,
                _ => continue,
            };
            if let Ok(windows) = compositor.find_by_class(&agent_config.window_class).await {
                for win in windows {
                    let session_id = format!("window-{}-{}", name, win.id);
                    if registry.get(&session_id).await.is_none() {
                        let mut session = Session::new(session_id, agent_kind, win.pid);
                        session.status = SessionStatus::Running;
                        session.window_id = Some(win.id.clone());
                        registry.register(session).await;
                    }
                }
            }
            // Clean up window sessions whose window no longer exists
            let current_window_ids: HashSet<String> = compositor
                .find_by_class(&agent_config.window_class).await
                .unwrap_or_default()
                .iter()
                .map(|w| format!("window-{}-{}", name, w.id))
                .collect();
            let all_sessions = registry.all().await;
            for session in all_sessions {
                if session.agent == agent_kind
                    && session.id.starts_with(&format!("window-{}-", name))
                    && !current_window_ids.contains(&session.id)
                {
                    registry.remove(&session.id).await;
                }
            }
        }

        // 4. Update window IDs for CLI agents via PID matching
        let all_sessions = registry.all().await;
        for session in all_sessions {
            if session.window_id.is_none() && session.pid > 0 {
                if let Ok(Some(win)) = compositor.find_by_pid(session.pid).await {
                    registry.set_window_id(&session.id, win.id).await;
                }
            }
        }
    }
}

fn agent_str(kind: &AgentKind) -> &'static str {
    match kind {
        AgentKind::ClaudeCode => "claude",
        AgentKind::Codex => "codex",
        AgentKind::Cursor => "cursor",
        AgentKind::WebStorm => "webstorm",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scan_agent_processes_does_not_panic() {
        // This just verifies the /proc scan doesn't crash.
        // Actual agent detection depends on running processes.
        let result = scan_agent_processes();
        // Result may be empty if no agents running — that's fine
        assert!(result.len() >= 0);
    }
}
```

- [ ] **Step 2: Run tests**

```bash
cargo test scanner
```

Expected: scanner test passes.

- [ ] **Step 3: Commit**

```bash
git add src/scanner.rs
git commit -m "feat: add background process/window scanner"
```

---

## Task 8: Sound Alerts

**Files:**
- Create: `src/sound.rs`
- Create: `assets/sounds/` (placeholder files)

- [ ] **Step 1: Write sound module**

Replace `src/sound.rs` with:

```rust
use crate::config::SoundConfig;
use std::path::PathBuf;

#[cfg(feature = "sound")]
use rodio::{Decoder, OutputStream, Sink};

pub enum SoundEvent {
    ApprovalNeeded,
    TaskComplete,
    Error,
}

pub struct SoundPlayer {
    config: SoundConfig,
}

impl SoundPlayer {
    pub fn new(config: SoundConfig) -> Self {
        Self { config }
    }

    pub fn play(&self, event: SoundEvent) {
        if !self.config.enabled {
            return;
        }
        let sound_ref = match event {
            SoundEvent::ApprovalNeeded => &self.config.approval_needed,
            SoundEvent::TaskComplete => &self.config.task_complete,
            SoundEvent::Error => &self.config.error,
        };
        if let Err(e) = self.play_sound(sound_ref) {
            eprintln!("vibewatch: sound error: {}", e);
        }
    }

    fn play_sound(&self, sound_ref: &str) -> anyhow::Result<()> {
        #[cfg(feature = "sound")]
        {
            let path = if sound_ref.starts_with("builtin:") {
                self.resolve_builtin(sound_ref)?
            } else {
                PathBuf::from(sound_ref)
            };

            if !path.exists() {
                anyhow::bail!("sound file not found: {}", path.display());
            }

            // Spawn in a thread so we don't block async
            std::thread::spawn(move || {
                if let Ok((_stream, handle)) = OutputStream::try_default() {
                    if let Ok(file) = std::fs::File::open(&path) {
                        if let Ok(source) = Decoder::new(std::io::BufReader::new(file)) {
                            let sink = Sink::try_new(&handle).unwrap();
                            sink.append(source);
                            sink.sleep_until_end();
                        }
                    }
                }
            });
        }
        #[cfg(not(feature = "sound"))]
        {
            let _ = sound_ref;
        }
        Ok(())
    }

    fn resolve_builtin(&self, name: &str) -> anyhow::Result<PathBuf> {
        let sound_name = name.strip_prefix("builtin:").unwrap_or(name);
        // Look in standard locations
        let candidates = vec![
            // Installed location
            PathBuf::from("/usr/share/vibewatch/sounds").join(format!("{}.wav", sound_name)),
            // Development location
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets/sounds").join(format!("{}.wav", sound_name)),
        ];
        for path in &candidates {
            if path.exists() {
                return Ok(path.clone());
            }
        }
        anyhow::bail!("builtin sound '{}' not found", sound_name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::SoundConfig;

    #[test]
    fn test_disabled_sound_does_not_error() {
        let config = SoundConfig {
            enabled: false,
            ..SoundConfig::default()
        };
        let player = SoundPlayer::new(config);
        // Should not panic or error
        player.play(SoundEvent::TaskComplete);
    }

    #[test]
    fn test_resolve_builtin_format() {
        let player = SoundPlayer::new(SoundConfig::default());
        // This will fail because we haven't created the wav files yet,
        // but we can test the path construction
        let result = player.resolve_builtin("builtin:chime");
        // It's OK if this errors — the files don't exist yet
        // Just verify it doesn't panic
        let _ = result;
    }
}
```

- [ ] **Step 2: Create placeholder sound assets**

Create `assets/sounds/` directory. For now, create a README explaining sounds need to be generated:

Create `assets/sounds/README.md`:
```markdown
# Built-in Sounds

Place WAV files here:
- `chime.wav` — played when an agent needs approval
- `success.wav` — played when an agent completes a task
- `alert.wav` — played when an agent errors

These should be short (< 1 second) 8-bit style sounds.
Generate with a tool like sfxr/jsfxr or record your own.
```

- [ ] **Step 3: Run tests**

```bash
cargo test sound
```

Expected: 2 sound tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/sound.rs assets/
git commit -m "feat: add sound alert system with rodio"
```

---

## Task 9: Daemon Main Loop

**Files:**
- Modify: `src/main.rs`
- Create: `contrib/vibewatch.service`

- [ ] **Step 1: Wire up the daemon command**

Update `src/main.rs` — replace the entire file:

```rust
mod config;
mod session;
mod ipc;
mod notify;
mod scanner;
mod waybar;
mod sound;
mod compositor;

#[cfg(feature = "panel")]
mod panel;

use clap::{Parser, Subcommand};
use config::Config;
use ipc::{InboundEvent, IpcServer, read_event, write_json};
use session::{AgentKind, Session, SessionRegistry, SessionStatus};
use sound::{SoundEvent, SoundPlayer};
use tokio::io::BufReader;
use std::sync::Arc;

#[derive(Parser)]
#[command(name = "vibewatch", version, about = "AI agent monitor for Wayland")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the vibewatch daemon
    Daemon,
    /// Send a hook notification to the daemon (called by agent hooks)
    Notify {
        /// Event type: session-start, pre-tool-use, post-tool-use, stop
        event: String,
        /// Agent type: claude-code, codex
        #[arg(long, default_value = "claude-code")]
        agent: String,
    },
    /// Output JSON status for Waybar custom module
    Status,
    /// Toggle the overlay panel visibility
    TogglePanel,
    /// Launch the overlay panel (usually started by the daemon)
    #[cfg(feature = "panel")]
    Panel,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Daemon => run_daemon().await,
        Commands::Notify { event, agent } => notify::handle_notify(&event, &agent).await,
        Commands::Status => run_status().await,
        Commands::TogglePanel => run_toggle_panel().await,
        #[cfg(feature = "panel")]
        Commands::Panel => panel::run_panel().await,
    }
}

async fn run_daemon() -> anyhow::Result<()> {
    let config = Config::load();
    let socket_path = Config::socket_path();
    let registry = SessionRegistry::new();
    let sound_player = Arc::new(SoundPlayer::new(config.sounds.clone()));

    eprintln!("vibewatch: starting daemon, socket at {}", socket_path.display());

    // Start IPC server
    let server = IpcServer::bind(&socket_path)?;

    // Start background scanner
    let compositor = compositor::create_compositor(&config.general.compositor)?;
    let scanner_registry = registry.clone();
    tokio::spawn(async move {
        scanner::run_scanner(scanner_registry, compositor, config).await;
    });

    eprintln!("vibewatch: daemon ready");

    // Accept connections
    loop {
        match server.accept().await {
            Ok(stream) => {
                let registry = registry.clone();
                let sound_player = sound_player.clone();
                tokio::spawn(async move {
                    handle_connection(stream, registry, sound_player).await;
                });
            }
            Err(e) => {
                eprintln!("vibewatch: accept error: {}", e);
            }
        }
    }
}

async fn handle_connection(
    stream: tokio::net::UnixStream,
    registry: SessionRegistry,
    sound_player: Arc<SoundPlayer>,
) {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let mut writer = tokio::net::unix::OwnedWriteHalf::from(writer);

    while let Ok(Some(event)) = read_event_from_reader(&mut reader).await {
        match event {
            InboundEvent::SessionStart { agent, session_id, pid } => {
                let agent_kind = parse_agent_kind(&agent);
                let session = Session::new(session_id, agent_kind, pid);
                registry.register(session).await;
            }
            InboundEvent::PreToolUse { session_id, tool, detail } => {
                registry.update_status(
                    &session_id,
                    SessionStatus::Executing,
                    Some(tool),
                    detail,
                ).await;
            }
            InboundEvent::PostToolUse { session_id, tool, success } => {
                if !success {
                    sound_player.play(SoundEvent::Error);
                }
                registry.update_status(
                    &session_id,
                    SessionStatus::Idle,
                    None,
                    None,
                ).await;
            }
            InboundEvent::Stop { session_id } => {
                registry.update_status(
                    &session_id,
                    SessionStatus::Stopped,
                    None,
                    None,
                ).await;
                sound_player.play(SoundEvent::TaskComplete);
            }
            InboundEvent::GetStatus => {
                let sessions = registry.all().await;
                let status = waybar::build_status(&sessions);
                let json = serde_json::to_string(&status).unwrap_or_default();
                let _ = tokio::io::AsyncWriteExt::write_all(&mut writer, json.as_bytes()).await;
                let _ = tokio::io::AsyncWriteExt::write_all(&mut writer, b"\n").await;
                let _ = tokio::io::AsyncWriteExt::flush(&mut writer).await;
                return; // One-shot request
            }
            InboundEvent::Subscribe => {
                // Stream updates until client disconnects
                loop {
                    let sessions = registry.all().await;
                    let update = ipc::SessionUpdate { sessions };
                    let json = serde_json::to_string(&update).unwrap_or_default();
                    if tokio::io::AsyncWriteExt::write_all(&mut writer, json.as_bytes()).await.is_err() {
                        return;
                    }
                    if tokio::io::AsyncWriteExt::write_all(&mut writer, b"\n").await.is_err() {
                        return;
                    }
                    let _ = tokio::io::AsyncWriteExt::flush(&mut writer).await;
                    tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
                }
            }
            InboundEvent::TogglePanel => {
                // Panel is a separate process — toggle by sending SIGUSR1
                // or by launching/killing the panel process
                let _ = tokio::process::Command::new("pkill")
                    .args(["-USR1", "vibewatch"])
                    .output()
                    .await;
            }
        }
    }
}

async fn read_event_from_reader(
    reader: &mut BufReader<tokio::net::unix::OwnedReadHalf>,
) -> std::io::Result<Option<InboundEvent>> {
    use tokio::io::AsyncBufReadExt;
    let mut line = String::new();
    let bytes = reader.read_line(&mut line).await?;
    if bytes == 0 {
        return Ok(None);
    }
    serde_json::from_str(line.trim())
        .map(Some)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
}

fn parse_agent_kind(s: &str) -> AgentKind {
    match s {
        "claude_code" | "claude-code" => AgentKind::ClaudeCode,
        "codex" => AgentKind::Codex,
        "cursor" => AgentKind::Cursor,
        "webstorm" => AgentKind::WebStorm,
        _ => AgentKind::ClaudeCode, // default
    }
}

async fn run_status() -> anyhow::Result<()> {
    let socket_path = Config::socket_path();
    let response = ipc::send_event(&socket_path, &InboundEvent::GetStatus).await?;
    if let Some(json) = response {
        println!("{}", json);
    } else {
        // Daemon not running — output idle status
        let status = waybar::build_status(&[]);
        let waybar_json = serde_json::json!({
            "text": status.text,
            "tooltip": status.tooltip,
            "class": status.class,
        });
        println!("{}", waybar_json);
    }
    Ok(())
}

async fn run_toggle_panel() -> anyhow::Result<()> {
    let socket_path = Config::socket_path();
    ipc::send_event(&socket_path, &InboundEvent::TogglePanel).await?;
    Ok(())
}
```

Note: This has a compilation issue with `stream.into_split()` — `UnixStream::into_split()` returns `(OwnedReadHalf, OwnedWriteHalf)`. The `read_event_from_reader` function needs to accept `BufReader<OwnedReadHalf>`. Adjust the function signature:

```rust
async fn handle_connection(
    stream: tokio::net::UnixStream,
    registry: SessionRegistry,
    sound_player: Arc<SoundPlayer>,
) {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);

    while let Ok(Some(event)) = read_event_from_reader(&mut reader).await {
        // ... (same match arms as above, using &mut writer directly)
    }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cargo build 2>&1
```

Expected: compiles (possibly with warnings). Fix any type errors from the split stream API.

- [ ] **Step 3: Create systemd service file**

Create `contrib/vibewatch.service`:

```ini
[Unit]
Description=Vibewatch - AI Agent Monitor
Documentation=https://github.com/moinax/vibewatch
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.cargo/bin/vibewatch daemon
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

- [ ] **Step 4: Create example Waybar module config**

Create `contrib/waybar-module.jsonc`:

```jsonc
// Add this to your Waybar modules config:
// In "modules-right" (or wherever you want it): "custom/vibewatch"

{
    "custom/vibewatch": {
        "exec": "vibewatch status",
        "return-type": "json",
        "interval": 2,
        "on-click": "vibewatch toggle-panel",
        "format": "{}",
        "tooltip": true
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add src/main.rs contrib/
git commit -m "feat: wire up daemon main loop, systemd service, and Waybar config"
```

---

## Task 10: GTK4 Overlay Panel

**Files:**
- Create: `src/panel/mod.rs`
- Create: `src/panel/window.rs`
- Create: `src/panel/session_row.rs`
- Create: `assets/style.css`

Note: GTK4 UI code is difficult to TDD. This task is structured as "build, compile, verify visually" rather than strict TDD.

- [ ] **Step 1: Write panel entry point**

Replace `src/panel/mod.rs` with:

```rust
pub mod window;
pub mod session_row;

use gtk4 as gtk;
use libadwaita as adw;
use gtk::prelude::*;
use adw::prelude::*;

pub async fn run_panel() -> anyhow::Result<()> {
    // GTK must run on the main thread
    let app = adw::Application::builder()
        .application_id("app.vibewatch.panel")
        .build();

    app.connect_activate(|app| {
        window::build_window(app);
    });

    // Run GTK main loop (this blocks)
    app.run_with_args::<String>(&[]);
    Ok(())
}
```

- [ ] **Step 2: Write layer-shell window**

Replace `src/panel/window.rs` with:

```rust
use gtk4 as gtk;
use gtk4_layer_shell as layer_shell;
use libadwaita as adw;
use gtk::prelude::*;
use adw::prelude::*;
use layer_shell::LayerShell;

use crate::config::Config;
use crate::ipc::{InboundEvent, SessionUpdate};
use crate::session::Session;
use super::session_row::build_session_row;

pub fn build_window(app: &adw::Application) {
    let window = adw::ApplicationWindow::builder()
        .application(app)
        .title("vibewatch")
        .default_width(320)
        .default_height(200)
        .build();

    // Set up layer shell
    window.init_layer_shell();
    window.set_layer(layer_shell::Layer::Overlay);
    window.set_anchor(layer_shell::Edge::Top, true);
    window.set_anchor(layer_shell::Edge::Right, true);
    window.set_margin(layer_shell::Edge::Top, 8);
    window.set_margin(layer_shell::Edge::Right, 8);
    window.set_exclusive_zone(0);
    window.set_keyboard_mode(layer_shell::KeyboardMode::OnDemand);
    window.set_namespace(Some("vibewatch"));

    // Load CSS
    let css_provider = gtk::CssProvider::new();
    let css = include_str!("../../assets/style.css");
    css_provider.load_from_string(css);
    gtk::style_context_add_provider_for_display(
        &gtk::gdk::Display::default().unwrap(),
        &css_provider,
        gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );

    // Main layout
    let main_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    main_box.add_css_class("main-box");

    // Header
    let header = build_header(&window);
    main_box.append(&header);

    // Session list (scrollable)
    let session_list = gtk::ListBox::new();
    session_list.set_selection_mode(gtk::SelectionMode::None);
    session_list.add_css_class("session-list");

    // Empty state
    let empty_label = gtk::Label::new(Some("No agents running"));
    empty_label.add_css_class("empty-state");
    session_list.set_placeholder(Some(&empty_label));

    let scrolled = gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vscrollbar_policy(gtk::PolicyType::Automatic)
        .vexpand(true)
        .child(&session_list)
        .build();

    main_box.append(&scrolled);
    window.set_content(Some(&main_box));

    // Start polling daemon for updates
    let list_clone = session_list.clone();
    gtk::glib::timeout_add_local(std::time::Duration::from_millis(500), move || {
        update_session_list(&list_clone);
        gtk::glib::ControlFlow::Continue
    });

    window.present();
}

fn build_header(window: &adw::ApplicationWindow) -> gtk::Box {
    let header = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    header.add_css_class("header");

    let title = gtk::Label::new(Some("vibewatch"));
    title.add_css_class("title");
    title.set_hexpand(true);
    title.set_halign(gtk::Align::Start);
    header.append(&title);

    let close_btn = gtk::Button::with_label("\u{2715}");
    close_btn.add_css_class("close-button");
    let win = window.clone();
    close_btn.connect_clicked(move |_| {
        win.close();
    });
    header.append(&close_btn);

    header
}

fn update_session_list(list: &gtk::ListBox) {
    // Connect to daemon and get status
    // Using a blocking approach in the GLib timeout since it's short-lived
    let socket_path = Config::socket_path();
    let rt = tokio::runtime::Handle::try_current();

    // Use std UnixStream for synchronous read in GTK context
    let sessions = match std::os::unix::net::UnixStream::connect(&socket_path) {
        Ok(mut stream) => {
            use std::io::{Write, BufRead, BufReader};
            let msg = serde_json::to_string(&InboundEvent::GetStatus).unwrap();
            let _ = writeln!(stream, "{}", msg);
            let _ = stream.flush();
            let mut reader = BufReader::new(stream);
            let mut response = String::new();
            if reader.read_line(&mut response).is_ok() {
                serde_json::from_str::<crate::ipc::StatusResponse>(&response)
                    .map(|s| s.sessions)
                    .unwrap_or_default()
            } else {
                vec![]
            }
        }
        Err(_) => vec![],
    };

    // Clear existing rows
    while let Some(row) = list.first_child() {
        list.remove(&row);
    }

    // Add session rows
    for session in &sessions {
        if session.status != crate::session::SessionStatus::Stopped {
            let row = build_session_row(session);
            list.append(&row);
        }
    }
}
```

- [ ] **Step 3: Write session row widget**

Replace `src/panel/session_row.rs` with:

```rust
use gtk4 as gtk;
use gtk::prelude::*;
use crate::compositor;
use crate::config::Config;
use crate::session::{Session, SessionStatus};

pub fn build_session_row(session: &Session) -> gtk::ListBoxRow {
    let row = gtk::ListBoxRow::new();
    row.add_css_class("session-row");

    let outer = gtk::Box::new(gtk::Orientation::Vertical, 4);
    outer.set_margin_start(12);
    outer.set_margin_end(12);
    outer.set_margin_top(8);
    outer.set_margin_bottom(8);

    // Top line: indicator + agent name + status
    let top = gtk::Box::new(gtk::Orientation::Horizontal, 8);

    let indicator = gtk::Label::new(Some(status_indicator(session.status)));
    indicator.add_css_class(session.status.css_class());
    indicator.add_css_class("indicator");
    top.append(&indicator);

    let name = gtk::Label::new(Some(session.agent.display_name()));
    name.add_css_class("agent-name");
    name.set_hexpand(true);
    name.set_halign(gtk::Align::Start);
    top.append(&name);

    let status_label = gtk::Label::new(Some(status_text(session.status)));
    status_label.add_css_class("status-label");
    status_label.add_css_class(session.status.css_class());
    top.append(&status_label);

    outer.append(&top);

    // Detail line (if any)
    if let Some(ref tool) = session.current_tool {
        let detail_text = if let Some(ref detail) = session.tool_detail {
            format!("\u{2514} {}: {}", tool, detail)
        } else {
            format!("\u{2514} {}", tool)
        };
        let detail = gtk::Label::new(Some(&detail_text));
        detail.add_css_class("detail");
        detail.set_halign(gtk::Align::Start);
        detail.set_margin_start(24);
        detail.set_ellipsize(gtk::pango::EllipsizeMode::End);
        outer.append(&detail);
    }

    // Jump button
    if session.window_id.is_some() || session.pid > 0 {
        let jump_box = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        jump_box.set_halign(gtk::Align::End);

        let jump_btn = gtk::Button::with_label("Jump");
        jump_btn.add_css_class("jump-button");

        let window_id = session.window_id.clone();
        let pid = session.pid;
        jump_btn.connect_clicked(move |_| {
            let wid = window_id.clone();
            let p = pid;
            std::thread::spawn(move || {
                let rt = tokio::runtime::Runtime::new().unwrap();
                rt.block_on(async {
                    let config = Config::load();
                    if let Ok(comp) = compositor::create_compositor(&config.general.compositor) {
                        if let Some(ref id) = wid {
                            let _ = comp.focus_window(id).await;
                        } else {
                            let _ = comp.focus_by_pid(p).await;
                        }
                    }
                });
            });
        });

        jump_box.append(&jump_btn);
        outer.append(&jump_box);
    }

    row.set_child(Some(&outer));
    row
}

fn status_indicator(status: SessionStatus) -> &'static str {
    match status {
        SessionStatus::Stopped | SessionStatus::Idle => "\u{25cb}", // ○
        _ => "\u{25cf}", // ●
    }
}

fn status_text(status: SessionStatus) -> &'static str {
    match status {
        SessionStatus::Thinking => "Thinking",
        SessionStatus::Executing => "Executing",
        SessionStatus::WaitingApproval => "Approval",
        SessionStatus::Idle => "Idle",
        SessionStatus::Running => "Running",
        SessionStatus::Stopped => "Stopped",
    }
}
```

- [ ] **Step 4: Write panel CSS**

Create `assets/style.css`:

```css
/* Vibewatch Panel — Catppuccin Mocha */
.main-box {
    background-color: #1e1e2e;
    border-radius: 12px;
    border: 1px solid #45475a;
}

.header {
    padding: 12px 16px;
    border-bottom: 1px solid #313244;
}

.title {
    color: #cdd6f4;
    font-weight: bold;
    font-size: 14px;
}

.close-button {
    background: none;
    border: none;
    color: #6c7086;
    min-width: 24px;
    min-height: 24px;
    padding: 0;
}

.close-button:hover {
    color: #f38ba8;
}

.session-list {
    background: transparent;
}

.session-row {
    background: transparent;
    border-bottom: 1px solid #313244;
}

.session-row:last-child {
    border-bottom: none;
}

.indicator {
    font-size: 12px;
}

.indicator.executing {
    color: #a6e3a1;
}

.indicator.attention {
    color: #fab387;
}

.indicator.thinking {
    color: #89b4fa;
}

.indicator.running {
    color: #a6e3a1;
}

.indicator.idle {
    color: #6c7086;
}

.agent-name {
    color: #cdd6f4;
    font-weight: 600;
    font-size: 13px;
}

.status-label {
    font-size: 11px;
    padding: 2px 8px;
    border-radius: 4px;
}

.status-label.executing {
    color: #a6e3a1;
    background-color: rgba(166, 227, 161, 0.15);
}

.status-label.attention {
    color: #fab387;
    background-color: rgba(250, 179, 135, 0.15);
}

.status-label.thinking {
    color: #89b4fa;
    background-color: rgba(137, 180, 250, 0.15);
}

.status-label.running {
    color: #a6e3a1;
    background-color: rgba(166, 227, 161, 0.15);
}

.status-label.idle {
    color: #6c7086;
    background-color: rgba(108, 112, 134, 0.15);
}

.detail {
    color: #a6adc8;
    font-size: 11px;
    font-family: monospace;
}

.jump-button {
    background-color: #313244;
    color: #cdd6f4;
    border: 1px solid #45475a;
    border-radius: 6px;
    padding: 4px 12px;
    font-size: 11px;
    min-height: 24px;
}

.jump-button:hover {
    background-color: #45475a;
}

.empty-state {
    color: #6c7086;
    padding: 32px;
    font-size: 13px;
}
```

- [ ] **Step 5: Verify compilation**

```bash
cargo build --features panel
```

Expected: compiles. The panel can't be visually tested without a running compositor + daemon, but compilation confirms the GTK4 API usage is correct.

- [ ] **Step 6: Commit**

```bash
git add src/panel/ assets/style.css
git commit -m "feat: add GTK4 layer-shell overlay panel with Catppuccin theme"
```

---

## Task 11: Integration Test

**Files:**
- Create: `tests/integration_test.rs`

- [ ] **Step 1: Write end-to-end IPC test**

Create `tests/integration_test.rs`:

```rust
use std::time::Duration;
use tempfile::TempDir;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;

/// Test: send hook events to daemon socket and verify status output
#[tokio::test]
async fn test_daemon_ipc_flow() {
    let tmp = TempDir::new().unwrap();
    let sock_path = tmp.path().join("test.sock");

    // Bind server
    let server = vibewatch::ipc::IpcServer::bind(&sock_path).unwrap();
    let registry = vibewatch::session::SessionRegistry::new();

    // Spawn a handler task
    let reg = registry.clone();
    let accept_task = tokio::spawn(async move {
        let stream = server.accept().await.unwrap();
        let (reader, _writer) = stream.into_split();
        let mut reader = BufReader::new(reader);
        let mut line = String::new();
        reader.read_line(&mut line).await.unwrap();
        let event: vibewatch::ipc::InboundEvent = serde_json::from_str(line.trim()).unwrap();
        match event {
            vibewatch::ipc::InboundEvent::SessionStart { agent, session_id, pid } => {
                let kind = if agent == "claude_code" {
                    vibewatch::session::AgentKind::ClaudeCode
                } else {
                    vibewatch::session::AgentKind::Codex
                };
                reg.register(vibewatch::session::Session::new(session_id, kind, pid)).await;
            }
            _ => panic!("unexpected event"),
        }
    });

    // Send a session_start event
    let mut client = UnixStream::connect(&sock_path).await.unwrap();
    let event = serde_json::json!({
        "event": "session_start",
        "agent": "claude_code",
        "session_id": "test-session-1",
        "pid": 9999
    });
    client.write_all(serde_json::to_string(&event).unwrap().as_bytes()).await.unwrap();
    client.write_all(b"\n").await.unwrap();
    client.flush().await.unwrap();

    accept_task.await.unwrap();

    // Verify session was registered
    let sessions = registry.all().await;
    assert_eq!(sessions.len(), 1);
    assert_eq!(sessions[0].id, "test-session-1");
    assert_eq!(sessions[0].agent, vibewatch::session::AgentKind::ClaudeCode);

    // Verify waybar status
    let status = vibewatch::waybar::build_status(&sessions);
    assert!(status.text.contains("1"));
    assert!(status.tooltip.contains("Claude Code"));
}
```

Note: this test requires that the relevant types are public in `lib.rs`. Create `src/lib.rs`:

```rust
pub mod config;
pub mod session;
pub mod ipc;
pub mod notify;
pub mod scanner;
pub mod waybar;
pub mod sound;
pub mod compositor;
```

And update `src/main.rs` to use the lib:

Add at the top of `src/main.rs`, replace the module declarations with:

```rust
use vibewatch::*;
```

Remove the `mod` declarations from `main.rs` since they now live in `lib.rs`.

- [ ] **Step 2: Run integration test**

```bash
cargo test --test integration_test
```

Expected: test passes.

- [ ] **Step 3: Commit**

```bash
git add src/lib.rs tests/ src/main.rs
git commit -m "feat: add integration test and lib.rs for public API"
```

---

## Task 12: README and Final Polish

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

Create `README.md`:

````markdown
# vibewatch

AI agent monitor for Wayland compositors. An open-source alternative to [Vibe Island](https://vibeisland.app/) for Linux.

Monitor Claude Code, Codex, Cursor, and WebStorm sessions from a unified overlay panel. See live status, get sound alerts, and jump to agent windows with one click.

![Status: Early Development](https://img.shields.io/badge/status-early%20development-orange)

## Features

- **Live session monitoring** — see which agents are running, what tools they're using, and their current status
- **Waybar integration** — custom module shows agent count and status in your bar
- **GTK4 overlay panel** — layer-shell popup with per-session details and Jump buttons
- **Window jumping** — focus the terminal/IDE where an agent is running (Hyprland + Niri)
- **Sound alerts** — configurable 8-bit sounds for task completion, errors, and approval requests
- **Hook integration** — Claude Code and Codex hooks feed real-time events to the daemon

## Supported Environments

| Component | Support |
|-----------|---------|
| **Compositors** | Hyprland, Niri |
| **Bars** | Waybar |
| **Agents** | Claude Code (full), Codex (full), Cursor (presence), WebStorm (presence) |

## Installation

### From source

```bash
cargo install --path .
```

### Arch Linux (AUR)

Coming soon.

## Setup

### 1. Start the daemon

```bash
# As a systemd service (recommended)
cp contrib/vibewatch.service ~/.config/systemd/user/
systemctl --user enable --now vibewatch

# Or run directly
vibewatch daemon
```

### 2. Configure Waybar

Add to your Waybar `modules.jsonc`:

```jsonc
"custom/vibewatch": {
    "exec": "vibewatch status",
    "return-type": "json",
    "interval": 2,
    "on-click": "vibewatch toggle-panel",
    "format": "{}",
    "tooltip": true
}
```

Add `"custom/vibewatch"` to your `modules-right` (or wherever you prefer).

### 3. Configure agent hooks

**Claude Code** — add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [{"type": "command", "command": "vibewatch notify session-start --agent claude-code"}],
    "PreToolUse": [{"type": "command", "command": "vibewatch notify pre-tool-use --agent claude-code"}],
    "PostToolUse": [{"type": "command", "command": "vibewatch notify post-tool-use --agent claude-code"}],
    "Stop": [{"type": "command", "command": "vibewatch notify stop --agent claude-code"}]
  }
}
```

**Codex** — add to `~/.codex/hooks.json`:

```json
[
  {"event": "SessionStart", "type": "command", "command": "vibewatch notify session-start --agent codex"},
  {"event": "PreToolUse", "type": "command", "command": "vibewatch notify pre-tool-use --agent codex"},
  {"event": "PostToolUse", "type": "command", "command": "vibewatch notify post-tool-use --agent codex"},
  {"event": "Stop", "type": "command", "command": "vibewatch notify stop --agent codex"}
]
```

## Configuration

Create `~/.config/vibewatch/config.toml`:

```toml
[general]
compositor = "auto"  # or "hyprland" / "niri"

[sounds]
enabled = true
approval_needed = "builtin:chime"
task_complete = "builtin:success"
error = "builtin:alert"

[agents.cursor]
window_class = "cursor"

[agents.webstorm]
window_class = "jetbrains-webstorm"
```

## CLI

```
vibewatch daemon          # Start the daemon
vibewatch status          # Output Waybar JSON
vibewatch toggle-panel    # Toggle the overlay panel
vibewatch panel           # Launch panel directly
vibewatch notify <event>  # Send hook event (used by agent hooks)
```

## License

MIT
````

- [ ] **Step 2: Create LICENSE file**

Create `LICENSE` with the MIT license text, copyright "2026 Jerome Poskin".

- [ ] **Step 3: Final build check**

```bash
cargo build --release
cargo test
```

Expected: release build succeeds, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add README.md LICENSE
git commit -m "docs: add README with setup instructions and project overview"
```

---

## Summary

| Task | What it builds | Estimated steps |
|------|---------------|-----------------|
| 1 | Project scaffold + core types + registry | 7 |
| 2 | TOML config parsing | 3 |
| 3 | Unix socket IPC server/client | 3 |
| 4 | Hook notification parsing (Claude Code + Codex) | 3 |
| 5 | Compositor trait + Hyprland + Niri backends | 5 |
| 6 | Waybar status JSON output | 3 |
| 7 | Background process/window scanner | 3 |
| 8 | Sound alert system | 4 |
| 9 | Daemon main loop + systemd + Waybar config | 5 |
| 10 | GTK4 overlay panel | 6 |
| 11 | Integration test + lib.rs | 3 |
| 12 | README + LICENSE | 4 |
| **Total** | | **49 steps** |
