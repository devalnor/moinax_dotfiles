# Vibewatch — AI Agent Monitor for Wayland

**Date**: 2026-04-16
**Status**: Draft
**Repo**: New standalone repo (to be created as `vibewatch`)

## Problem

On macOS, Vibe Island provides a unified overlay for monitoring AI coding agents (Claude Code, Codex, Cursor, etc.) from the Dynamic Island. No equivalent exists for Linux/Wayland. Users running multiple AI agents across terminals and IDEs must manually track and switch between them.

## Goal

Build an open-source alternative to Vibe Island for Hyprland and Niri (Wayland compositors). A lightweight Rust daemon + GTK4 overlay that monitors AI coding agent sessions, shows live status, plays sound alerts, and lets you jump to the right window with one click.

## Non-Goals (Phase 1)

- Permission approval GUI (approve/deny tool calls from the overlay) — deferred to Phase 2
- Support for compositors beyond Hyprland and Niri (Sway, river, etc.) — community contributions welcome
- Bars beyond Waybar (eww, ironbar, etc.)

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Desktop                           │
│                                                      │
│  ┌──────────┐    click/    ┌───────────────────────┐ │
│  │  Waybar  │───keybind──▶│   GTK4 Overlay Panel  │ │
│  │  Module  │             │   (layer-shell)        │ │
│  └────┬─────┘             └───────────┬───────────┘ │
│       │                               │              │
│       │ poll                          │ subscribe    │
│       ▼                               ▼              │
│  ┌────────────────────────────────────────────┐      │
│  │          vibewatch daemon (Rust/tokio)     │      │
│  │  - session registry                        │      │
│  │  - Unix socket IPC                         │      │
│  │  - sound alerts (rodio)                    │      │
│  └──────┬──────────────┬──────────────┬───────┘      │
│         │              │              │               │
│    hooks/IPC      hooks/IPC      process detect      │
│         ▼              ▼              ▼               │
│   Claude Code       Codex      Cursor / WebStorm     │
└─────────────────────────────────────────────────────┘
```

### Components

1. **Daemon** (`vibewatch`) — Rust/tokio background service, runs as a user systemd unit
2. **Waybar module** — custom module that polls daemon for status summary
3. **GTK4 overlay panel** — gtk4-rs + gtk4-layer-shell popup toggled by click or keybind
4. **Hook scripts** — installed into Claude Code and Codex hook configs to feed events to the daemon

## Daemon

### Session State Model

```rust
struct Session {
    id: String,                    // unique session ID from hook JSON
    agent: AgentKind,              // ClaudeCode, Codex, Cursor, WebStorm
    status: SessionStatus,         // Thinking, Executing, WaitingApproval, Idle, Stopped
    current_tool: Option<String>,  // e.g. "Bash", "Edit", "Read"
    tool_detail: Option<String>,   // e.g. "running tests", file path
    window_id: Option<String>,     // compositor window ID for jumping
    pid: u32,
    started_at: Instant,
    last_event: Instant,
}

enum AgentKind { ClaudeCode, Codex, Cursor, WebStorm }

enum SessionStatus { Thinking, Executing, WaitingApproval, Idle, Stopped }
```

### IPC

Unix socket at `$XDG_RUNTIME_DIR/vibewatch.sock`. JSON-line protocol.

**Inbound (hooks -> daemon):**
```json
{"event": "session_start", "agent": "claude_code", "session_id": "abc123", "pid": 12345}
{"event": "pre_tool_use", "session_id": "abc123", "tool": "Bash", "detail": "npm test"}
{"event": "post_tool_use", "session_id": "abc123", "tool": "Bash", "success": true}
{"event": "stop", "session_id": "abc123"}
```

**Outbound (daemon -> clients):**
- `vibewatch status` — one-shot JSON for Waybar
- `vibewatch subscribe` — streaming JSON lines for the GTK panel
- `vibewatch toggle-panel` — signal the panel to show/hide

### Process Scanning

Background task polls every 2-3 seconds:
- Detects `claude` / `codex` processes not registered via hooks (pre-existing sessions, crash recovery)
- Detects `cursor` / `webstorm` windows via compositor IPC
- Cleans up stale sessions (process died, no Stop hook fired)

### Sound Alerts

Uses `rodio` crate. Configurable events:
- Agent waiting for approval
- Agent finished task
- Agent errored

Ships with built-in 8-bit synthesized sounds. User can override with custom WAV/OGG files.

### Configuration

TOML file at `~/.config/vibewatch/config.toml`:

```toml
[general]
compositor = "auto"  # auto-detect, or "hyprland" / "niri"

[sounds]
enabled = true
approval_needed = "builtin:chime"
task_complete = "builtin:success"
error = "builtin:alert"
# custom: approval_needed = "/path/to/sound.wav"

[agents.cursor]
window_class = "cursor"

[agents.webstorm]
window_class = "jetbrains-webstorm"
```

## Agent Integration

### Claude Code (full integration)

Hooks installed in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [{"type": "command", "command": "vibewatch notify session-start"}],
    "PreToolUse": [{"type": "command", "command": "vibewatch notify pre-tool-use"}],
    "PostToolUse": [{"type": "command", "command": "vibewatch notify post-tool-use"}],
    "Stop": [{"type": "command", "command": "vibewatch notify stop"}]
  }
}
```

Hook scripts receive JSON context on stdin from Claude Code (including session ID, tool name, command, working directory). The `vibewatch notify` subcommand reads this JSON from stdin, extracts relevant fields, and forwards a normalized event to the daemon via the Unix socket. This means hooks are a single CLI call with no wrapper scripts needed.

**Status granularity**: Thinking, Executing (with tool name + detail), WaitingApproval, Idle, Stopped.

### Codex (full integration)

Hooks installed in `~/.codex/hooks.json` — same events, same `vibewatch notify` pattern. Codex provides SessionStart, PreToolUse, PostToolUse, UserPromptSubmit, Stop.

**Status granularity**: Same as Claude Code.

### Cursor / WebStorm (presence only)

No hook system available. Detection via:
- Process detection (is the app running?)
- Window detection via compositor IPC (match by `app_id` / window class)

**Status granularity**: Running or Not Running. No insight into internal AI agent state.

## Waybar Module

Custom module output format (Waybar JSON protocol):

```json
{"text": "\uf544 3", "tooltip": "Claude Code: executing Bash\nCodex: thinking\nCursor: running", "class": "active"}
```

- **Text**: icon + active agent count
- **CSS classes**: `active` (agents running), `attention` (approval needed), `idle` (no agents)
- **Click**: runs `vibewatch toggle-panel`
- **Tooltip**: quick summary on hover

Integrates into existing Waybar config as a `custom/vibewatch` module.

## GTK4 Overlay Panel

### Rendering

- `gtk4-rs` + `gtk4-layer-shell` for proper Wayland overlay behavior
- Anchored to top-right corner
- Toggled by Waybar click or keybind
- Auto-dismiss on outside click (exclusive zone = 0)
- Styled with Libadwaita, with CSS overrides for Catppuccin Mocha (dark) / Latte (light) themes

### Layout

```
┌──────────────────────────────┐
│  vibewatch            [✕]    │
├──────────────────────────────┤
│  ● Claude Code    Executing  │
│    └ Bash: running tests     │
│                    [Jump]    │
├──────────────────────────────┤
│  ● Codex          Thinking   │
│    └ planning next step      │
│                    [Jump]    │
├──────────────────────────────┤
│  ○ Cursor         Running    │
│                    [Jump]    │
└──────────────────────────────┘
```

- Each session is a row: agent icon, name, status badge, current tool/activity
- **[Jump]** button focuses the agent's window
- Color-coded status: green (executing), amber (waiting approval), blue (thinking), gray (idle)
- Empty state: "No agents running" with a brief description of how to get started

## Window Jumping

### PID Matching (Claude Code, Codex)

Hook context provides the terminal PID. The daemon queries the compositor:
- **Hyprland**: `hyprctl clients -j` to find window by PID, then `hyprctl dispatch focuswindow pid:<pid>`
- **Niri**: `niri msg windows` to find window by PID, then `niri msg action focus-window --id <id>`

### Window Class Matching (Cursor, WebStorm)

Match by `app_id` / window class from config. If multiple windows of the same class exist, the panel lists them all with workspace info so the user can pick.

### Stretch Goal: Kitty Tab/Split Focus

Kitty supports remote control (`kitty @ focus-window`). If the terminal is Kitty, vibewatch could focus the exact tab/split where an agent runs, not just the Kitty window. Deferred to post-v1.

## Tech Stack

- **Language**: Rust (2021 edition)
- **Async runtime**: tokio
- **GUI**: gtk4-rs + gtk4-layer-shell-rs + libadwaita-rs
- **Audio**: rodio
- **Compositor IPC**: hyprland-rs (Hyprland), niri JSON IPC via Unix socket (Niri)
- **Config**: toml + serde
- **CLI**: clap

## Distribution

- **AUR package** (primary, since user is on Arch)
- **Cargo install** (crates.io)
- **Binary releases** (GitHub Releases)
- Homebrew / other distro packages as community contributions

## Phase 2 (Future)

- Permission approval GUI — approve/deny tool calls from the overlay panel instead of switching to the terminal
- Additional compositor support (Sway, river, cosmic)
- Additional bar support (eww, ironbar, ags)
- Kitty remote control for tab/split focus
- Plugin system for adding new agent integrations
