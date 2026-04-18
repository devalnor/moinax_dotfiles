# vibewatch Installer & Dotfiles Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move vibewatch's setup side effects (systemd unit, Claude hooks, Waybar snippet) out of these dotfiles and into vibewatch itself via a new `vibewatch install` subcommand plus a thin `install.sh` wrapper. Make vibewatch optional in the dotfiles via `ai.yaml` and a `.install_vibewatch` chezmoi flag. End result: vibewatch installs cleanly on any Hyprland/Niri machine with one `curl | sh`, and these dotfiles stop owning anything that should belong to vibewatch.

**Architecture:** The vibewatch binary grows a new top-level `install` subcommand (Rust, fully unit-tested in isolation). An `install.sh` bootstrap runs `cargo install --git …` then `exec vibewatch install "$@"`. The dotfiles become a thin chezmoi-gated layer — templates check `.install_vibewatch`, and the Claude hooks block leaves the dotfiles source for good (owned by vibewatch from now on).

**Tech Stack:** Rust (serde_json, clap, dirs, tempfile for tests), POSIX sh, chezmoi Go templates, bash (manage.sh + installer.sh), yq.

**Repo layout:**
- `~/Projects/labs/vibewatch` (remote `github.com/Moinax/vibewatch`, branch `main`) — Phase 1 lands here.
- `~/dotfiles` (local repo, current branch `vibewatch`) — Phase 2 lands here, **only after** Phase 1 has shipped and `vibewatch install` has been run on the user's live box.

---

## CRITICAL: Migration sequencing

The Phase-2 dotfiles commits REMOVE the vibewatch hook block from `home/dot_claude/settings.json`. If that file is still a plain chezmoi-managed file when we apply, `chezmoi apply` will rewrite the live `~/.claude/settings.json` without the hook block — breaking this and every other active Claude Code session instantly.

Safe sequencing — strictly:

1. Phase 1 (vibewatch repo) lands fully. `cargo install --path .`, `vibewatch install`, **diff proves zero drift** vs. the current live file.
2. Phase 2 begins. Task 14 (remove hooks from source) is the dangerous one; its steps include both renaming the file to `create_settings.json` (so chezmoi only seeds it on fresh installs) **and** immediately re-running `vibewatch install` if anything rewrites the live file.
3. Round-trip verification (flag off → diff, flag on → clean) confirms vibewatch lines appear/disappear from Waybar + autostart, and that `settings.json` is never affected by chezmoi again.

If any step in Phase 2 accidentally rewrites `~/.claude/settings.json` without the hook block, recovery is simple: `vibewatch install` re-plants it.

---

## Phase 1 — vibewatch repo

All work happens in `~/Projects/labs/vibewatch`, branch `main`. Push at the end of Phase 1.

### Task 1: Wire up the `Install` CLI subcommand skeleton

**Files:**
- Modify: `~/Projects/labs/vibewatch/src/main.rs`
- Create: `~/Projects/labs/vibewatch/src/install.rs`

- [ ] **Step 1: Inspect the existing Commands enum layout**

Run:

```bash
grep -n "enum Command\|Commands\|#\[command\|match cli" ~/Projects/labs/vibewatch/src/main.rs | head -10
```

- [ ] **Step 2: Register the new module at the top of `src/main.rs`**

Add near the other `mod` declarations in `src/main.rs`:

```rust
mod install;
```

- [ ] **Step 3: Add the `Install` variant to the `Commands` enum in `src/main.rs`**

```rust
/// Install vibewatch's systemd user service and Claude Code hooks.
Install {
    /// Skip systemd user unit install/enable.
    #[arg(long)]
    no_service: bool,
    /// Skip Claude Code hooks merge.
    #[arg(long)]
    no_hooks: bool,
    /// Print every action but change nothing on disk.
    #[arg(long)]
    dry_run: bool,
    /// Reverse the install: stop service, strip hooks, remove snippet.
    #[arg(long)]
    uninstall: bool,
},
```

- [ ] **Step 4: Dispatch the new variant in the command match block in `src/main.rs`**

```rust
Commands::Install { no_service, no_hooks, dry_run, uninstall } => {
    install::run(install::Options {
        no_service,
        no_hooks,
        dry_run,
        uninstall,
    })?;
}
```

- [ ] **Step 5: Create `src/install.rs` with a minimal skeleton**

```rust
use anyhow::Result;

pub struct Options {
    pub no_service: bool,
    pub no_hooks: bool,
    pub dry_run: bool,
    pub uninstall: bool,
}

pub fn run(opts: Options) -> Result<()> {
    if opts.uninstall {
        eprintln!("vibewatch install: uninstall not implemented yet");
    } else {
        eprintln!("vibewatch install: not implemented yet");
    }
    // Consume unused fields so clippy stays quiet.
    let _ = (opts.no_service, opts.no_hooks, opts.dry_run);
    Ok(())
}
```

- [ ] **Step 6: Build and smoke-test**

Run:

```bash
cd ~/Projects/labs/vibewatch && cargo build --release 2>&1 | tail -5
```

Expected: `Finished `release` profile`.

Run:

```bash
~/Projects/labs/vibewatch/target/release/vibewatch install --help
```

Expected output contains `--no-service`, `--no-hooks`, `--dry-run`, `--uninstall`.

- [ ] **Step 7: Commit**

```bash
cd ~/Projects/labs/vibewatch && git add src/main.rs src/install.rs && git commit -m "install: CLI skeleton for the install subcommand"
```

---

### Task 2: Pure `merge_hooks` / `unmerge_hooks` with unit tests

Everything that mutates JSON lives here and is fully pure — no filesystem.

**Files:**
- Modify: `~/Projects/labs/vibewatch/src/install.rs`

- [ ] **Step 1: Add the hook constants and pure functions**

Append to `src/install.rs`:

```rust
use serde_json::Value;

/// Every Claude Code hook event vibewatch registers, plus whether its
/// entry is flagged `async: true` in settings.json. The synchronous
/// entry (PermissionRequest) is what powers the widget approve/deny +
/// AskUserQuestion flows.
pub const HOOK_EVENTS: [(&str, bool); 6] = [
    ("SessionStart",      true),
    ("UserPromptSubmit",  true),
    ("PreToolUse",        true),
    ("PostToolUse",       true),
    ("PermissionRequest", false),
    ("Stop",              true),
];

/// Canonical hook command for a given event.
pub fn command_for(event: &str) -> String {
    format!(
        "~/.cargo/bin/vibewatch notify {} --agent claude-code",
        event_to_slug(event)
    )
}

fn event_to_slug(event: &str) -> String {
    // SessionStart -> session-start
    let mut out = String::new();
    for (i, c) in event.chars().enumerate() {
        if c.is_uppercase() && i > 0 {
            out.push('-');
        }
        out.extend(c.to_lowercase());
    }
    out
}

/// Merge vibewatch's hook entries into a parsed settings.json value.
/// Idempotent: re-running produces byte-equal output.
pub fn merge_hooks(mut settings: Value) -> Value {
    let hooks = settings
        .as_object_mut()
        .expect("settings must be a JSON object")
        .entry("hooks")
        .or_insert_with(|| serde_json::json!({}));
    let hooks_obj = hooks
        .as_object_mut()
        .expect("settings.hooks must be a JSON object");

    for (event, async_flag) in HOOK_EVENTS {
        let command = command_for(event);
        let entry = hooks_obj
            .entry(event)
            .or_insert_with(|| serde_json::json!([]));
        let array = entry.as_array_mut().expect("event entry must be an array");

        // Find or create the matcher-"" group.
        let group_idx = array.iter().position(|g| {
            g.get("matcher").and_then(|m| m.as_str()) == Some("")
        });
        let group = match group_idx {
            Some(idx) => &mut array[idx],
            None => {
                array.push(serde_json::json!({ "matcher": "", "hooks": [] }));
                array.last_mut().unwrap()
            }
        };

        let group_hooks = group
            .get_mut("hooks")
            .and_then(|v| v.as_array_mut())
            .expect("group.hooks must be an array");

        let already_present = group_hooks.iter().any(|h| {
            h.get("command").and_then(|c| c.as_str()) == Some(command.as_str())
        });
        if !already_present {
            let mut hook_entry = serde_json::json!({
                "type": "command",
                "command": command,
            });
            if async_flag {
                hook_entry
                    .as_object_mut()
                    .unwrap()
                    .insert("async".to_string(), Value::Bool(true));
            }
            group_hooks.push(hook_entry);
        }
    }

    settings
}

/// Remove vibewatch's hook entries (anything whose command string contains
/// "vibewatch"). Other tools' hooks in the same event array are preserved.
pub fn unmerge_hooks(mut settings: Value) -> Value {
    let Some(hooks_obj) = settings
        .as_object_mut()
        .and_then(|o| o.get_mut("hooks"))
        .and_then(|v| v.as_object_mut())
    else {
        return settings;
    };

    let event_names: Vec<String> = HOOK_EVENTS.iter().map(|(e, _)| e.to_string()).collect();
    for event in &event_names {
        let Some(entry) = hooks_obj.get_mut(event) else { continue };
        let Some(array) = entry.as_array_mut() else { continue };

        for group in array.iter_mut() {
            if let Some(group_hooks) = group
                .get_mut("hooks")
                .and_then(|v| v.as_array_mut())
            {
                group_hooks.retain(|h| {
                    h.get("command")
                        .and_then(|c| c.as_str())
                        .map(|s| !s.contains("vibewatch"))
                        .unwrap_or(true)
                });
            }
        }

        // Drop now-empty matcher groups.
        array.retain(|g| {
            g.get("hooks")
                .and_then(|h| h.as_array())
                .map(|a| !a.is_empty())
                .unwrap_or(false)
        });

        if array.is_empty() {
            hooks_obj.remove(event);
        }
    }

    settings
}
```

- [ ] **Step 2: Add the idempotence unit test**

Append to `src/install.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn merge_hooks_is_idempotent() {
        let initial = json!({});
        let once = merge_hooks(initial);
        let twice = merge_hooks(once.clone());
        assert_eq!(once, twice, "merge_hooks must be idempotent");
    }
}
```

- [ ] **Step 3: Run the test**

```bash
cd ~/Projects/labs/vibewatch && cargo test --release --lib install::tests::merge_hooks_is_idempotent 2>&1 | tail -3
```

Expected: `test result: ok. 1 passed`.

- [ ] **Step 4: Add preservation + all-events + other-commands + unmerge tests**

Append to the `tests` module:

```rust
    #[test]
    fn merge_hooks_preserves_unrelated_keys() {
        let initial = json!({
            "permissions": {"defaultMode": "auto"},
            "statusLine": {"type": "command", "command": "npx ccstatusline"},
            "enabledPlugins": {"frontend-design@claude-plugins-official": true},
        });
        let merged = merge_hooks(initial.clone());
        assert_eq!(merged["permissions"], initial["permissions"]);
        assert_eq!(merged["statusLine"], initial["statusLine"]);
        assert_eq!(merged["enabledPlugins"], initial["enabledPlugins"]);
        assert!(merged["hooks"]["SessionStart"].is_array());
    }

    #[test]
    fn merge_hooks_adds_all_six_events() {
        let merged = merge_hooks(json!({}));
        for (event, _) in HOOK_EVENTS {
            assert!(
                merged["hooks"][event].is_array(),
                "missing hooks.{}", event
            );
        }
    }

    #[test]
    fn merge_hooks_preserves_other_hook_commands() {
        let initial = json!({
            "hooks": {
                "PreToolUse": [{
                    "matcher": "",
                    "hooks": [{"type": "command", "command": "some-other-tool"}]
                }]
            }
        });
        let merged = merge_hooks(initial);
        let cmds: Vec<String> = merged["hooks"]["PreToolUse"][0]["hooks"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|h| {
                h.get("command").and_then(|c| c.as_str()).map(String::from)
            })
            .collect();
        assert!(cmds.iter().any(|c| c == "some-other-tool"));
        assert!(cmds.iter().any(|c| c.contains("vibewatch")));
    }

    #[test]
    fn unmerge_hooks_removes_only_vibewatch_hooks() {
        let seeded = merge_hooks(json!({
            "hooks": {
                "PreToolUse": [{
                    "matcher": "",
                    "hooks": [{"type": "command", "command": "some-other-tool"}]
                }]
            }
        }));
        let stripped = unmerge_hooks(seeded);
        let cmds: Vec<String> = stripped["hooks"]["PreToolUse"][0]["hooks"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|h| {
                h.get("command").and_then(|c| c.as_str()).map(String::from)
            })
            .collect();
        assert_eq!(cmds, vec!["some-other-tool".to_string()]);
        let all = serde_json::to_string(&stripped).unwrap();
        assert!(!all.contains("vibewatch"), "vibewatch string still present: {all}");
    }
```

- [ ] **Step 5: Run the whole install test module**

```bash
cd ~/Projects/labs/vibewatch && cargo test --release --lib install:: 2>&1 | tail -5
```

Expected: `test result: ok. 5 passed`.

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/labs/vibewatch && git add src/install.rs && git commit -m "install: pure merge_hooks/unmerge_hooks with idempotence tests"
```

---

### Task 3: Settings.json file I/O + `--no-hooks` + `--dry-run`

Wraps the pure functions with disk access. Tempdir tests prove idempotence, dry-run safety, uninstall restoration.

**Files:**
- Modify: `~/Projects/labs/vibewatch/src/install.rs`
- Modify: `~/Projects/labs/vibewatch/Cargo.toml` (add `dirs` to regular deps if not already there)

- [ ] **Step 1: Verify `dirs` and `tempfile` are present**

```bash
grep -n '^dirs\|^tempfile' ~/Projects/labs/vibewatch/Cargo.toml
```

Expected: `dirs` in `[dependencies]` and `tempfile` in `[dev-dependencies]` (both verified already in earlier exploration; no change needed).

- [ ] **Step 2: Add file-I/O helpers**

Append to `src/install.rs` (above the `#[cfg(test)]` block):

```rust
use anyhow::Context;
use std::fs;
use std::path::{Path, PathBuf};

fn settings_path() -> PathBuf {
    if let Ok(dir) = std::env::var("CLAUDE_CONFIG_DIR") {
        PathBuf::from(dir).join("settings.json")
    } else {
        dirs::home_dir()
            .expect("HOME must resolve")
            .join(".claude")
            .join("settings.json")
    }
}

pub fn apply_hooks_merge(path: &Path, dry_run: bool) -> Result<()> {
    if !path.exists() {
        eprintln!(
            "vibewatch install: {} does not exist yet; skipping hook merge. \
             Run vibewatch install again after Claude Code creates it.",
            path.display()
        );
        return Ok(());
    }
    let contents = fs::read_to_string(path)
        .with_context(|| format!("reading {}", path.display()))?;
    let original: Value = serde_json::from_str(&contents)
        .with_context(|| format!("parsing {}", path.display()))?;
    let merged = merge_hooks(original.clone());
    if merged == original {
        eprintln!(
            "vibewatch install: hooks already present in {}",
            path.display()
        );
        return Ok(());
    }
    if dry_run {
        eprintln!(
            "vibewatch install: [dry-run] would merge hooks into {}",
            path.display()
        );
        return Ok(());
    }
    let mut out = serde_json::to_string_pretty(&merged)?;
    out.push('\n');
    fs::write(path, out).with_context(|| format!("writing {}", path.display()))?;
    eprintln!("vibewatch install: merged hooks into {}", path.display());
    Ok(())
}

pub fn apply_hooks_unmerge(path: &Path, dry_run: bool) -> Result<()> {
    if !path.exists() {
        return Ok(());
    }
    let contents = fs::read_to_string(path)?;
    let original: Value = serde_json::from_str(&contents)?;
    let stripped = unmerge_hooks(original.clone());
    if stripped == original {
        return Ok(());
    }
    if dry_run {
        eprintln!(
            "vibewatch install: [dry-run] would remove vibewatch hooks from {}",
            path.display()
        );
        return Ok(());
    }
    let mut out = serde_json::to_string_pretty(&stripped)?;
    out.push('\n');
    fs::write(path, out)?;
    eprintln!(
        "vibewatch install: removed vibewatch hooks from {}",
        path.display()
    );
    Ok(())
}
```

- [ ] **Step 3: Update `run()` to call these**

Replace the body of `run()` in `src/install.rs` with:

```rust
pub fn run(opts: Options) -> Result<()> {
    let path = settings_path();
    if opts.uninstall {
        if !opts.no_hooks {
            apply_hooks_unmerge(&path, opts.dry_run)?;
        }
    } else {
        if !opts.no_hooks {
            apply_hooks_merge(&path, opts.dry_run)?;
        }
    }
    let _ = opts.no_service; // wired up in Task 4
    Ok(())
}
```

- [ ] **Step 4: Add tempdir integration tests**

Append to the `tests` module:

```rust
    #[test]
    fn apply_hooks_merge_is_idempotent_on_disk() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("settings.json");
        std::fs::write(&path, r#"{"permissions":{"defaultMode":"auto"}}"#).unwrap();
        apply_hooks_merge(&path, false).unwrap();
        let first = std::fs::read_to_string(&path).unwrap();
        apply_hooks_merge(&path, false).unwrap();
        let second = std::fs::read_to_string(&path).unwrap();
        assert_eq!(first, second, "second merge must produce identical output");
    }

    #[test]
    fn apply_hooks_merge_dry_run_writes_nothing() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("settings.json");
        let input = r#"{"permissions":{"defaultMode":"auto"}}"#;
        std::fs::write(&path, input).unwrap();
        apply_hooks_merge(&path, true).unwrap();
        let after = std::fs::read_to_string(&path).unwrap();
        assert_eq!(after, input, "--dry-run must not modify the file");
    }

    #[test]
    fn apply_hooks_unmerge_restores_pre_install_shape() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("settings.json");
        std::fs::write(&path, r#"{"permissions":{"defaultMode":"auto"}}"#).unwrap();
        apply_hooks_merge(&path, false).unwrap();
        apply_hooks_unmerge(&path, false).unwrap();
        let final_value: Value =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        // "hooks" key should be either absent or an empty object
        let hooks_empty = match final_value.get("hooks") {
            None => true,
            Some(v) => v.as_object().map(|o| o.is_empty()).unwrap_or(false),
        };
        assert!(hooks_empty, "hooks key should be empty/absent after uninstall");
        assert_eq!(final_value["permissions"]["defaultMode"], "auto");
    }
```

- [ ] **Step 5: Run all install tests**

```bash
cd ~/Projects/labs/vibewatch && cargo test --release --lib install:: 2>&1 | tail -5
```

Expected: `test result: ok. 8 passed`.

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/labs/vibewatch && git add src/install.rs && git commit -m "install: settings.json read/merge/write with --no-hooks and --dry-run"
```

---

### Task 4: systemd user unit install + `--no-service`

**Files:**
- Modify: `~/Projects/labs/vibewatch/src/install.rs`
- Confirm: `~/Projects/labs/vibewatch/contrib/vibewatch.service` exists and has the expected content.

- [ ] **Step 1: Verify the contrib unit**

```bash
cat ~/Projects/labs/vibewatch/contrib/vibewatch.service
```

Expected: the `[Unit] / [Service] / [Install]` block with `ExecStart=%h/.cargo/bin/vibewatch daemon`.

- [ ] **Step 2: Add systemd handling**

Append to `src/install.rs` (above the `#[cfg(test)]` block):

```rust
use std::process::Command;

const SERVICE_NAME: &str = "vibewatch.service";
const SERVICE_BODY: &str = include_str!("../contrib/vibewatch.service");

fn systemd_unit_path() -> PathBuf {
    dirs::config_dir()
        .expect("XDG_CONFIG_HOME or ~/.config must resolve")
        .join("systemd")
        .join("user")
        .join(SERVICE_NAME)
}

fn has_systemctl() -> bool {
    Command::new("systemctl")
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

pub fn apply_service_install(dry_run: bool) -> Result<()> {
    if !has_systemctl() {
        eprintln!("vibewatch install: systemctl not found; skipping service install");
        return Ok(());
    }
    let path = systemd_unit_path();
    let current = fs::read_to_string(&path).unwrap_or_default();
    let needs_write = current != SERVICE_BODY;
    if dry_run {
        if needs_write {
            eprintln!(
                "vibewatch install: [dry-run] would write {}",
                path.display()
            );
        }
        eprintln!(
            "vibewatch install: [dry-run] would enable --now {}",
            SERVICE_NAME
        );
        return Ok(());
    }
    if needs_write {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&path, SERVICE_BODY)
            .with_context(|| format!("writing {}", path.display()))?;
        eprintln!("vibewatch install: wrote {}", path.display());
    }
    let _ = Command::new("systemctl")
        .args(["--user", "daemon-reload"])
        .status();
    match Command::new("systemctl")
        .args(["--user", "enable", "--now", SERVICE_NAME])
        .status()
    {
        Ok(s) if s.success() => {
            eprintln!("vibewatch install: enabled & started {}", SERVICE_NAME);
        }
        Ok(s) => eprintln!(
            "vibewatch install: systemctl enable --now exited with {}",
            s
        ),
        Err(e) => eprintln!(
            "vibewatch install: systemctl enable --now failed: {e}"
        ),
    }
    Ok(())
}

pub fn apply_service_uninstall(dry_run: bool) -> Result<()> {
    if !has_systemctl() {
        return Ok(());
    }
    if dry_run {
        eprintln!(
            "vibewatch install: [dry-run] would disable+stop {} and remove the unit file",
            SERVICE_NAME
        );
        return Ok(());
    }
    let _ = Command::new("systemctl")
        .args(["--user", "disable", "--now", SERVICE_NAME])
        .status();
    let path = systemd_unit_path();
    if path.exists() {
        fs::remove_file(&path)?;
        eprintln!("vibewatch install: removed {}", path.display());
    }
    let _ = Command::new("systemctl")
        .args(["--user", "daemon-reload"])
        .status();
    Ok(())
}
```

- [ ] **Step 3: Wire into `run()`**

Replace `run()`'s body with:

```rust
pub fn run(opts: Options) -> Result<()> {
    let path = settings_path();
    if opts.uninstall {
        if !opts.no_hooks {
            apply_hooks_unmerge(&path, opts.dry_run)?;
        }
        if !opts.no_service {
            apply_service_uninstall(opts.dry_run)?;
        }
    } else {
        if !opts.no_service {
            apply_service_install(opts.dry_run)?;
        }
        if !opts.no_hooks {
            apply_hooks_merge(&path, opts.dry_run)?;
        }
    }
    Ok(())
}
```

- [ ] **Step 4: Add a sanity test for the unit path**

Append to the `tests` module:

```rust
    #[test]
    fn systemd_unit_path_points_into_config() {
        let p = systemd_unit_path();
        let s = p.to_string_lossy();
        assert!(
            s.ends_with("systemd/user/vibewatch.service"),
            "unexpected path: {s}"
        );
    }
```

- [ ] **Step 5: Build + test**

```bash
cd ~/Projects/labs/vibewatch && cargo build --release 2>&1 | tail -3 && cargo test --release --lib install:: 2>&1 | tail -3
```

Expected: `Finished` and `test result: ok. 9 passed`.

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/labs/vibewatch && git add src/install.rs && git commit -m "install: systemd user unit install/uninstall with --no-service and --dry-run"
```

---

### Task 5: Waybar snippet drop + manual-step printer

**Files:**
- Modify: `~/Projects/labs/vibewatch/src/install.rs`

- [ ] **Step 1: Add snippet-drop and printer helpers**

Append to `src/install.rs` (above `#[cfg(test)]`):

```rust
const WAYBAR_SNIPPET: &str = include_str!("../contrib/waybar-module.jsonc");

fn waybar_snippet_path() -> PathBuf {
    dirs::config_dir()
        .expect("XDG_CONFIG_HOME or ~/.config must resolve")
        .join("vibewatch")
        .join("waybar-module.jsonc")
}

pub fn apply_waybar_install(dry_run: bool) -> Result<()> {
    let path = waybar_snippet_path();
    let current = fs::read_to_string(&path).unwrap_or_default();
    if current == WAYBAR_SNIPPET {
        return Ok(());
    }
    if dry_run {
        eprintln!(
            "vibewatch install: [dry-run] would drop {}",
            path.display()
        );
        return Ok(());
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&path, WAYBAR_SNIPPET)?;
    eprintln!("vibewatch install: wrote {}", path.display());
    Ok(())
}

pub fn apply_waybar_uninstall(dry_run: bool) -> Result<()> {
    let path = waybar_snippet_path();
    if !path.exists() {
        return Ok(());
    }
    if dry_run {
        eprintln!(
            "vibewatch install: [dry-run] would remove {}",
            path.display()
        );
        return Ok(());
    }
    fs::remove_file(&path)?;
    // Best-effort: remove ~/.config/vibewatch if empty.
    if let Some(parent) = path.parent() {
        let _ = fs::remove_dir(parent);
    }
    eprintln!("vibewatch install: removed {}", path.display());
    Ok(())
}

pub fn print_manual_steps() {
    eprintln!();
    eprintln!("vibewatch install: three manual steps remain:");
    eprintln!();
    eprintln!("1. Compositor autostart (paste into your compositor config):");
    eprintln!("   Hyprland  (~/.config/hypr/*.conf):");
    eprintln!("     exec-once = ~/.cargo/bin/vibewatch daemon");
    eprintln!("   Niri      (~/.config/niri/config.kdl):");
    eprintln!(
        "     spawn-at-startup \"sh\" \"-c\" \"~/.cargo/bin/vibewatch daemon\""
    );
    eprintln!();
    eprintln!("2. Waybar — include the module snippet and wire it into your layout:");
    eprintln!("   Snippet: {}", waybar_snippet_path().display());
    eprintln!("   Include it in your Waybar config and add \"custom/vibewatch\"");
    eprintln!("   to your modules-* array.");
    eprintln!();
    eprintln!("3. (Optional) Hyprland click-focus tip — stop cursor from warping:");
    eprintln!("     cursor {{ no_warps     = true }}");
    eprintln!("     input  {{ mouse_refocus = false }}");
    eprintln!();
}
```

- [ ] **Step 2: Wire into `run()`**

Replace `run()`'s body with:

```rust
pub fn run(opts: Options) -> Result<()> {
    let path = settings_path();
    if opts.uninstall {
        if !opts.no_hooks {
            apply_hooks_unmerge(&path, opts.dry_run)?;
        }
        if !opts.no_service {
            apply_service_uninstall(opts.dry_run)?;
        }
        apply_waybar_uninstall(opts.dry_run)?;
        eprintln!("vibewatch install: uninstall complete");
    } else {
        if !opts.no_service {
            apply_service_install(opts.dry_run)?;
        }
        if !opts.no_hooks {
            apply_hooks_merge(&path, opts.dry_run)?;
        }
        apply_waybar_install(opts.dry_run)?;
        if !opts.dry_run {
            print_manual_steps();
        }
    }
    Ok(())
}
```

- [ ] **Step 3: Build + test**

```bash
cd ~/Projects/labs/vibewatch && cargo build --release 2>&1 | tail -3 && cargo test --release 2>&1 | tail -5
```

Expected: `Finished` and all tests pass (the file count is higher than just install tests — confirm none fail).

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/labs/vibewatch && git add src/install.rs && git commit -m "install: waybar snippet drop, --uninstall path, manual-steps printer"
```

---

### Task 6: `install.sh` bootstrap

**Files:**
- Create: `~/Projects/labs/vibewatch/install.sh`

- [ ] **Step 1: Write the script**

Create `~/Projects/labs/vibewatch/install.sh`:

```sh
#!/bin/sh
# vibewatch install bootstrap.
# Usage: curl -fsSL https://raw.githubusercontent.com/Moinax/vibewatch/main/install.sh | sh
# Flags after `-s --` are forwarded to `vibewatch install`:
#   curl -fsSL .../install.sh | sh -s -- --no-service
set -eu

if ! command -v cargo >/dev/null 2>&1; then
    echo "vibewatch install.sh: cargo not found. Install Rust first: https://rustup.rs/" >&2
    exit 1
fi

cargo install --git https://github.com/Moinax/vibewatch

CARGO_BIN="${CARGO_HOME:-$HOME/.cargo}/bin"
exec "$CARGO_BIN/vibewatch" install "$@"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x ~/Projects/labs/vibewatch/install.sh
```

- [ ] **Step 3: POSIX syntax check**

```bash
sh -n ~/Projects/labs/vibewatch/install.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/labs/vibewatch && git add install.sh && git commit -m "install: add install.sh curl | sh bootstrap"
```

---

### Task 7: README Setup / Uninstall rewrite

**Files:**
- Modify: `~/Projects/labs/vibewatch/README.md`

- [ ] **Step 1: Locate existing Install / Setup / Quick start sections**

```bash
grep -n '^##\|^### ' ~/Projects/labs/vibewatch/README.md
```

- [ ] **Step 2: Replace `## Install` (and any existing `## Setup` / `## Quick start`) with the new content**

Open `~/Projects/labs/vibewatch/README.md` and replace the existing install/quick-start section with exactly this:

````markdown
## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Moinax/vibewatch/main/install.sh | sh
```

That script does three things automatically: builds the binary (via `cargo install --git`), installs the user-systemd service, and merges vibewatch's hooks into `~/.claude/settings.json`.

You'll still need to do three short steps by hand — `vibewatch install` prints copy-paste snippets for each:

1. Add `exec-once = ~/.cargo/bin/vibewatch daemon` (Hyprland) or the equivalent `spawn-at-startup` line (Niri) to your compositor config.
2. Include `~/.config/vibewatch/waybar-module.jsonc` in your Waybar layout and add `"custom/vibewatch"` to your modules.
3. (Optional) For cleanest widget-click-to-focus on Hyprland, add `cursor { no_warps = true }` and `input { mouse_refocus = false }`.

Flags: `vibewatch install --help` — `--no-service`, `--no-hooks`, `--dry-run`, `--uninstall`.

## Uninstall

```bash
vibewatch install --uninstall
cargo uninstall vibewatch
```

`--uninstall` stops & disables the service, removes the unit file, strips vibewatch hooks from `~/.claude/settings.json` (other hooks untouched), and deletes `~/.config/vibewatch/`.
````

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/labs/vibewatch && git add README.md && git commit -m "docs: rewrite Install / Uninstall around install.sh + vibewatch install"
```

---

### Task 8: End-to-end verification on your live box + push

**CRITICAL** — this task is what makes Phase 2 safe. It proves `vibewatch install` produces a settings.json byte-equivalent to the current live file. If this diff isn't empty, do NOT proceed to Phase 2.

**Files:** none modified (validation only).

- [ ] **Step 1: Back up the live settings file**

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.pre-vibewatch-install
```

- [ ] **Step 2: Install the new binary from source**

```bash
cd ~/Projects/labs/vibewatch && cargo install --path . --force 2>&1 | tail -5
```

Expected: `Installed package 'vibewatch' (executables 'vibewatch')`.

- [ ] **Step 3: Preview with `--dry-run`**

```bash
vibewatch install --dry-run
```

Expected output mentions merging hooks (or "already present"), service install, waybar drop — all flagged `[dry-run]`.

- [ ] **Step 4: Run for real**

```bash
vibewatch install
```

Expected output: "hooks already present" (or "merged hooks"), "wrote ~/.config/vibewatch/waybar-module.jsonc", three manual-step snippets.

- [ ] **Step 5: Diff to prove idempotence**

```bash
diff ~/.claude/settings.json.pre-vibewatch-install ~/.claude/settings.json
```

Expected: **empty output.** If anything diffs, STOP, investigate, and reconcile before Phase 2. The most likely cause is a JSON key-ordering mismatch — fix the pretty-printer or adjust the merge to respect key order.

- [ ] **Step 6: Confirm service is running**

```bash
systemctl --user is-active vibewatch
```

Expected: `active`.

- [ ] **Step 7: Push Phase 1**

```bash
cd ~/Projects/labs/vibewatch && git push origin main
```

- [ ] **Step 8: Remove the backup**

```bash
rm ~/.claude/settings.json.pre-vibewatch-install
```

---

## Phase 2 — dotfiles repo

Only start Phase 2 once Task 8 succeeded with an empty diff. All work happens in `~/dotfiles` on branch `vibewatch`.

### Task 9: Seed the `.install_vibewatch` chezmoi data flag locally

**Files:**
- Modify: `~/.config/chezmoi/chezmoi.toml` (local machine state, not a repo file)

- [ ] **Step 1: Inspect current chezmoi data**

```bash
chezmoi data | head -40
```

- [ ] **Step 2: Add the flag**

Open `~/.config/chezmoi/chezmoi.toml`. Under the `[data]` section (create it if missing) add:

```toml
install_vibewatch = true
```

- [ ] **Step 3: Verify chezmoi sees it**

```bash
chezmoi data | grep install_vibewatch
```

Expected: `install_vibewatch: true` (or the equivalent format chezmoi uses).

- [ ] **Step 4: No commit** — local machine state only. The source repo change that seeds it for other users comes in Task 11.

---

### Task 10: Add vibewatch to `packages/groups/ai.yaml`

**Files:**
- Modify: `~/dotfiles/packages/groups/ai.yaml`

- [ ] **Step 1: Inspect the current file**

```bash
cat ~/dotfiles/packages/groups/ai.yaml
```

- [ ] **Step 2: Add the `custom_install` entry and description**

Open `~/dotfiles/packages/groups/ai.yaml` and add (creating the `custom_install:` top-level key if it doesn't exist yet, mirroring the pattern in `packages/groups/development.yaml`):

```yaml
custom_install:
  - name: vibewatch
    check: command -v vibewatch || test -f "$HOME/.cargo/bin/vibewatch"
    install: curl -fsSL https://raw.githubusercontent.com/Moinax/vibewatch/main/install.sh | sh
    requires: cargo
```

And in the `descriptions:` block:

```yaml
descriptions:
  vibewatch: AI agent status bar & overlay for Hyprland/Niri (built from source via cargo)
  # ... keep existing entries ...
```

- [ ] **Step 3: Validate YAML**

```bash
cd ~/dotfiles && yq '.' packages/groups/ai.yaml >/dev/null && echo OK
```

Expected: `OK`.

- [ ] **Step 4: Validate the installer can parse the new entry**

```bash
bash -c 'source ~/dotfiles/install/lib/common.sh && parse_custom_install_names ~/dotfiles/packages/groups/ai.yaml arch'
```

Expected: stdout contains a line with just `vibewatch`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add packages/groups/ai.yaml && git commit -m "packages: add vibewatch as optional ai custom_install"
```

---

### Task 11: Seed `install_vibewatch` from both `manage.sh reconfig` and `install/installer.sh`

The flag must be settable in two places so fresh-install users and existing users get consistent behaviour: (a) `install/installer.sh` writes it during `./manage.sh setup` based on whether the user kept the `vibewatch` custom_install in the tree selector; (b) `manage.sh reconfig` lets existing users flip it afterwards.

**Files:**
- Modify: `~/dotfiles/manage.sh` (or whichever script under `~/dotfiles/tools/` implements `reconfig`)
- Modify: `~/dotfiles/install/installer.sh` (setup-time seeding)

- [ ] **Step 1: Locate where existing install_* flags are managed**

```bash
grep -n "install_hyprland\|install_niri\|install_development\|install_productivity\|install_multimedia" ~/dotfiles/manage.sh ~/dotfiles/tools/*.sh 2>/dev/null
```

Identify the toggle loop / array / case block that handles these flags.

- [ ] **Step 2: Add `install_vibewatch` to the same structure**

Add the flag name, a default of `true`, and a user-facing prompt label `Install vibewatch (AI agent monitor for Hyprland/Niri)?`. The exact edit depends on whatever structure your grep surfaced — copy the pattern used for `install_development` or `install_niri` verbatim.

- [ ] **Step 3: Dry-run reconfig to confirm the new toggle appears**

```bash
~/dotfiles/manage.sh reconfig
```

Expected: the menu lists `install_vibewatch` alongside the other install_ flags, with its current value (`true`). Confirm flipping it writes to `~/.config/chezmoi/chezmoi.toml`; flip it back to `true` before exiting.

- [ ] **Step 4: Confirm chezmoi data still shows `install_vibewatch = true`**

```bash
chezmoi data | grep install_vibewatch
```

Expected: `true`.

- [ ] **Step 5: Locate the setup-time flag-writing code in `install/installer.sh`**

```bash
grep -n "install_multimedia\|install_development\|install_hyprland\|install_ai\s*=\s*" ~/dotfiles/install/installer.sh | head
```

Identify the block that writes group-selection flags into chezmoi data (earlier exploration surfaced lines around 1194–1220 in installer.sh).

- [ ] **Step 6: Add setup-time seeding for `install_vibewatch`**

In the same block that sets `install_ai`, add a parallel setter for `install_vibewatch`. Derive it from whether `vibewatch` appears in the selected custom_install list for `ai.yaml`. Concretely, in the flag-writer block:

```bash
# Default: vibewatch on if the AI group is selected, off otherwise.
local install_vibewatch="$install_ai"

# If the user specifically deselected vibewatch in the tree selector,
# override to false. GROUP_CUSTOM_PACKAGE_LIST is populated by
# select_group_packages; "vibewatch" in the list means kept.
if [ "${GROUP_PACKAGE_MODE[ai]:-all}" = "custom" ]; then
    case " ${GROUP_CUSTOM_PACKAGE_LIST[ai]:-} " in
        *" vibewatch "*) install_vibewatch="true" ;;
        *) install_vibewatch="false" ;;
    esac
fi
```

Then include it in the chezmoi-data write alongside the other flags:

```
install_vibewatch = $install_vibewatch
```

Adjust the exact variable names and code style to match what the grep in Step 5 surfaced.

- [ ] **Step 7: Shellcheck + dry-run**

```bash
shellcheck ~/dotfiles/install/installer.sh 2>&1 | grep -E "error|warning" | head
```

Expected: no new errors introduced by the patch.

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles && git add manage.sh tools/ install/installer.sh && git commit -m "manage.sh, installer: seed install_vibewatch from setup + reconfig"
```

---

### Task 12: Gate Waybar bits behind `.install_vibewatch`

**Files:**
- Modify: `~/dotfiles/home/dot_config/waybar/modules.jsonc.tmpl`
- Modify: `~/dotfiles/home/dot_config/waybar/config-hyprland.tmpl`
- Modify: `~/dotfiles/home/dot_config/waybar/config-niri.tmpl`

- [ ] **Step 1: Gate the module definition**

In `~/dotfiles/home/dot_config/waybar/modules.jsonc.tmpl`, find the `// AI agent monitor (vibewatch)` comment and its following `"custom/vibewatch": { … }` object. Wrap the whole block:

```jsonc
  {{- if .install_vibewatch }}
  // AI agent monitor (vibewatch)
  "custom/vibewatch": {
    "exec": "~/.cargo/bin/vibewatch status",
    "return-type": "json",
    "interval": 2,
    "on-click": "~/.cargo/bin/vibewatch toggle-panel",
    "format": "{}"
  },
  {{- end }}
```

(Keep the existing inner body of `"custom/vibewatch"`; only add the `{{- if … }}` / `{{- end }}` wrapper.)

- [ ] **Step 2: Gate the `"custom/vibewatch"` entry inside `config-hyprland.tmpl`**

Find the existing `"custom/vibewatch"` entry inside whichever modules array it lives in (`modules-center` per earlier exploration). Wrap:

```jsonc
  "modules-center": [
    "hyprland/window",
    {{- if .install_vibewatch }}
    "custom/vibewatch",
    {{- end }}
    "clock"
  ],
```

Adjust the neighbours to match the real surrounding entries. Preserve comma discipline — Waybar's JSONC parser is tolerant of trailing commas but not of double commas.

- [ ] **Step 3: Same for `config-niri.tmpl`**

- [ ] **Step 4: Render-test with the flag ON**

```bash
chezmoi execute-template < ~/dotfiles/home/dot_config/waybar/modules.jsonc.tmpl | grep -c custom/vibewatch
```

Expected: `1`.

- [ ] **Step 5: Render-test with the flag OFF**

```bash
chezmoi execute-template --init --promptBool install_vibewatch=false < ~/dotfiles/home/dot_config/waybar/modules.jsonc.tmpl | grep -c custom/vibewatch || echo 0
```

Expected: `0`.

- [ ] **Step 6: `chezmoi diff` on live waybar configs — must be empty**

```bash
chezmoi diff ~/.config/waybar 2>&1 | head
```

Expected: empty (flag is true and rendering is unchanged).

- [ ] **Step 7: Commit**

```bash
cd ~/dotfiles && git add home/dot_config/waybar/ && git commit -m "waybar: gate vibewatch module behind .install_vibewatch"
```

---

### Task 13: Gate Hyprland + Niri autostart lines

**Files:**
- Modify: `~/dotfiles/home/dot_config/hypr/conf/autostart.conf.tmpl`
- Modify: `~/dotfiles/home/dot_config/niri/config.kdl.tmpl`

- [ ] **Step 1: Gate the Hyprland line**

In `~/dotfiles/home/dot_config/hypr/conf/autostart.conf.tmpl`, find `exec-once = ~/.cargo/bin/vibewatch daemon`. Wrap:

```
{{- if .install_vibewatch }}
exec-once = ~/.cargo/bin/vibewatch daemon
{{- end }}
```

- [ ] **Step 2: Gate the Niri line**

In `~/dotfiles/home/dot_config/niri/config.kdl.tmpl`, find the `spawn-at-startup "sh" "-c" "~/.cargo/bin/vibewatch daemon"` line. Wrap:

```
{{- if .install_vibewatch }}
spawn-at-startup "sh" "-c" "~/.cargo/bin/vibewatch daemon"
{{- end }}
```

- [ ] **Step 3: Render-test with the flag ON**

```bash
chezmoi execute-template < ~/dotfiles/home/dot_config/hypr/conf/autostart.conf.tmpl | grep vibewatch
chezmoi execute-template < ~/dotfiles/home/dot_config/niri/config.kdl.tmpl | grep vibewatch
```

Expected: each prints one line containing `vibewatch daemon`.

- [ ] **Step 4: Render-test with the flag OFF**

```bash
chezmoi execute-template --init --promptBool install_vibewatch=false < ~/dotfiles/home/dot_config/hypr/conf/autostart.conf.tmpl | grep vibewatch || echo NONE
chezmoi execute-template --init --promptBool install_vibewatch=false < ~/dotfiles/home/dot_config/niri/config.kdl.tmpl | grep vibewatch || echo NONE
```

Expected: `NONE` for both.

- [ ] **Step 5: `chezmoi diff` clean**

```bash
chezmoi diff ~/.config/hypr ~/.config/niri 2>&1 | head
```

Expected: empty.

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles && git add home/dot_config/hypr/ home/dot_config/niri/ && git commit -m "hypr, niri: gate vibewatch autostart behind .install_vibewatch"
```

---

### Task 14: Drop the hook block from `dot_claude/settings.json` (DANGER ZONE)

This is the step that, done naïvely, wipes the live hooks. The safe path is to rename the source from `dot_claude/settings.json` to `dot_claude/create_settings.json` so chezmoi seeds it on fresh installs but never rewrites an existing file afterwards. From then on `vibewatch install` is the sole owner of the live file.

Context recap: on your machine `~/.claude/settings.json` already exists (so `create_` prefix becomes a no-op — good); on a fresh machine the file is created once from the hookless source (so vibewatch's installer will be responsible for planting the hook block).

**Files:**
- Modify: `~/dotfiles/home/dot_claude/settings.json` (remove the hook block entirely)
- Rename: `~/dotfiles/home/dot_claude/settings.json` → `~/dotfiles/home/dot_claude/create_settings.json`

- [ ] **Step 1: Open the source file and remove the `"hooks": { … }` key entirely**

Open `~/dotfiles/home/dot_claude/settings.json` and delete the full `"hooks": { … }` sub-object (all 6 events, every entry). Leave `permissions`, `statusLine`, `enabledPlugins`, `extraKnownMarketplaces`, `effortLevel` and every other top-level key intact. Run a JSON lint check:

```bash
python3 -m json.tool < ~/dotfiles/home/dot_claude/settings.json >/dev/null && echo OK
```

Expected: `OK`.

- [ ] **Step 2: Confirm the rendered source has no vibewatch strings**

```bash
chezmoi execute-template < ~/dotfiles/home/dot_claude/settings.json | grep -c vibewatch || echo 0
```

Expected: `0`.

- [ ] **Step 3: PREVIEW the chezmoi diff — do NOT apply yet**

```bash
chezmoi diff ~/.claude/settings.json
```

Expected: chezmoi wants to delete the hooks block from the live file. That diff is the expected one-time loss.

- [ ] **Step 4: Rename the source file to `create_settings.json`**

```bash
cd ~/dotfiles && git mv home/dot_claude/settings.json home/dot_claude/create_settings.json
```

The `create_` prefix means chezmoi writes the file only if it doesn't already exist. Since `~/.claude/settings.json` does exist, chezmoi will stop trying to rewrite it.

- [ ] **Step 5: Re-check the chezmoi diff — should now be empty**

```bash
chezmoi diff ~/.claude/settings.json 2>&1 | head
```

Expected: empty (chezmoi no longer claims to manage the existing file).

- [ ] **Step 6: Defensive re-plant (belt-and-braces)**

```bash
vibewatch install
```

Expected: `hooks already present`. If anything else was written, verify with:

```bash
grep -c "vibewatch notify" ~/.claude/settings.json
```

Expected: `6`.

- [ ] **Step 7: Commit**

```bash
cd ~/dotfiles && git add home/dot_claude/ && git commit -m "claude: stop managing settings.json after creation — vibewatch owns hook block"
```

---

### Task 15: Toggle-off round-trip verification

**Files:** none modified (validation only).

- [ ] **Step 1: Flip the flag off in local chezmoi data**

Open `~/.config/chezmoi/chezmoi.toml` and change `install_vibewatch = true` to `install_vibewatch = false`.

- [ ] **Step 2: Preview the diff — do NOT apply**

```bash
chezmoi diff
```

Expected: vibewatch lines disappear from `waybar/modules.jsonc`, `waybar/config-hyprland.jsonc`, `waybar/config-niri.jsonc`, `hypr/conf/autostart.conf`, `niri/config.kdl`. The `create_settings.json` file should NOT appear in the diff (since it already exists and is `create_`-prefixed).

- [ ] **Step 3: Flip the flag back to `true`**

```bash
sed -i 's/install_vibewatch = false/install_vibewatch = true/' ~/.config/chezmoi/chezmoi.toml
```

- [ ] **Step 4: Confirm clean state**

```bash
chezmoi diff 2>&1 | head
```

Expected: empty.

- [ ] **Step 5: Push the branch**

```bash
cd ~/dotfiles && git push origin vibewatch
```

---

### Task 16: Merge `vibewatch` into `main`

**Files:** none modified.

- [ ] **Step 1: Confirm the list of commits going in**

```bash
cd ~/dotfiles && git log --oneline main..vibewatch
```

Expected: the 7–8 commits added above plus any previously-queued work on this branch.

- [ ] **Step 2: Merge to main**

```bash
cd ~/dotfiles && git checkout main && git merge --ff-only vibewatch && git push origin main
```

If fast-forward fails, rebase the branch onto main first and retry. Do not create a merge commit for housekeeping changes like this.

- [ ] **Step 3: Delete the local feature branch**

```bash
cd ~/dotfiles && git branch -d vibewatch
```

- [ ] **Step 4: Smoke-test once more**

```bash
chezmoi diff
vibewatch status
systemctl --user is-active vibewatch
```

Expected: clean diff, valid JSON status response, `active`.
