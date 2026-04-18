# vibewatch installer & dotfiles integration — design

**Date:** 2026-04-18
**Status:** approved

## Context

vibewatch (the AI-agent monitor Rust daemon at `~/Projects/labs/vibewatch`, public at `github.com/Moinax/vibewatch`) started out as a "works on my machine" integration: its runtime bits were hard-coded directly into these dotfiles (Claude Code hooks, Waybar module, Hyprland/Niri autostart, cursor-warp tweaks). That's fine for one user but has three problems:

1. **Non-dotfiles users can't easily install vibewatch.** The README tells them to `cargo install` but never to register the systemd unit, merge the Claude Code hooks into `settings.json`, etc. Each of those steps is discoverable only by reading the dotfiles.
2. **Dotfiles hard-code vibewatch as if it were mandatory.** It isn't. It should be an optional tool, togglable during `./manage.sh setup` like `hyprvoice` or any other custom install.
3. **Duplication between dotfiles and vibewatch.** Both now know the exact shape of the Claude Code hook block. If vibewatch later changes its hook protocol, we have to remember to update the dotfiles too.

The intended outcome: vibewatch becomes a standalone tool installable with one `curl | sh` on any Hyprland/Niri machine, **and** optionally installable through these dotfiles' `manage.sh` in a way that deselecting it cleanly omits all vibewatch-specific config. Dotfiles stop carrying anything that should belong to vibewatch's installer.

## Architecture

Two independent surfaces. Either can be used alone.

### A. vibewatch side — self-installing binary

```
┌──────────────────────────────────────────────────┐
│ install.sh  (~15-line shell bootstrap, repo root)│
│   1. check for cargo (abort with fix-up URL)     │
│   2. cargo install --git …/Moinax/vibewatch      │
│   3. exec vibewatch install "$@"                 │
└──────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────┐
│ `vibewatch install` (new Rust subcommand)        │
│   • write/refresh systemd user unit              │
│   • JSON-merge Claude hooks into settings.json   │
│   • drop canonical Waybar snippet                │
│   • print copy-paste snippets for the rest       │
└──────────────────────────────────────────────────┘
```

One source of truth (the Rust code) for everything the installer knows about the binary. The shell script exists purely for the `curl | sh` UX; it contains no domain logic.

### B. dotfiles side — optional selection in the AI group

```
packages/groups/ai.yaml       – custom_install entry for vibewatch
chezmoi data flag             – .install_vibewatch  (seeded by manage.sh reconfig)
shared chezmoi templates      – wrap vibewatch-specific blocks in {{ if .install_vibewatch }}
home/dot_claude/settings.json – vibewatch hook entries REMOVED (owned by vibewatch now)
```

## vibewatch-side design

### `install.sh`

Lives at the repo root. Invoked as:

```bash
curl -fsSL https://raw.githubusercontent.com/Moinax/vibewatch/main/install.sh | sh
```

Pseudocode (shell):

```sh
#!/bin/sh
set -eu
command -v cargo >/dev/null 2>&1 || {
  echo "cargo not found. Install rust: https://rustup.rs/"
  exit 1
}
cargo install --git https://github.com/Moinax/vibewatch
exec "${CARGO_HOME:-$HOME/.cargo}/bin/vibewatch" install "$@"
```

Any flags after the pipe (`| sh -s -- --no-service`, for example) pass through to `vibewatch install`.

### `vibewatch install` subcommand

New top-level `clap` subcommand next to `daemon` / `status` / `toggle-panel` / `notify`. All work is idempotent; re-running is a no-op.

#### Automatic steps

1. **systemd user unit.**
   - Path: `~/.config/systemd/user/vibewatch.service`.
   - Content: embedded at compile time via `include_str!("../contrib/vibewatch.service")`.
   - Actions: `systemctl --user daemon-reload`, `systemctl --user enable --now vibewatch`.
   - Skipped when `--no-service` is passed *or* when `systemctl` / an active user bus isn't available (e.g. inside a container).

2. **Claude Code hooks merge.**
   - Path: `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json` if the env var is set).
   - Parse as `serde_json::Value`. For each of the 6 events (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`), ensure a hook with the canonical vibewatch command string exists under `hooks.<event>[*].hooks`, deduplicated by exact command string. Never mutate other top-level keys.
   - Write back using `serde_json::to_string_pretty` with **2-space** indentation (matches current file).
   - Skipped when `--no-hooks` is passed *or* when the file doesn't exist yet (print a note telling the user where to put it once Claude Code creates one).

3. **Waybar snippet drop.**
   - Path: `~/.config/vibewatch/waybar-module.jsonc`.
   - Content: copy of `contrib/waybar-module.jsonc`.
   - Purpose: give the user a canonical, version-pinned module JSON to `@include` or copy into their Waybar config.

#### Manual steps — print, don't write

For each of these, the subcommand prints a copy-pasteable snippet with the destination file path:

- **Hyprland autostart** — `exec-once = ~/.cargo/bin/vibewatch daemon` (paste into `~/.config/hypr/…`). Absolute path because `exec-once` runs outside the interactive-shell PATH.
- **Niri autostart** — `spawn-at-startup "sh" "-c" "~/.cargo/bin/vibewatch daemon"` (paste into `~/.config/niri/config.kdl`). Same reason.
- **Waybar layout** — "Add `\"custom/vibewatch\"` to your `modules-*` array and `@include` `~/.config/vibewatch/waybar-module.jsonc`."
- **Hyprland click-focus tip (optional)** — recommend `cursor { no_warps = true }` + `input { mouse_refocus = false }` so widget-click-to-focus doesn't warp the cursor.

#### Flags

| Flag | Effect |
|---|---|
| `--no-service` | Skip systemd user unit. |
| `--no-hooks` | Skip Claude Code hooks merge. |
| `--dry-run` | Print every action, write nothing. |
| `--uninstall` | Stop & disable service, remove the unit file, remove hook entries whose command string contains `vibewatch`, delete `~/.config/vibewatch/waybar-module.jsonc`. Non-destructive: other hooks, other Waybar modules, other compositor config lines untouched. |

### README Setup section — new shape

Replace the current Setup section with:

```markdown
## Install

    curl -fsSL https://raw.githubusercontent.com/Moinax/vibewatch/main/install.sh | sh

That script does three things automatically: builds the binary (via `cargo
install`), installs the user-systemd service, and merges vibewatch's hooks
into `~/.claude/settings.json`.

You'll still need to do three short steps by hand — `vibewatch install`
prints copy-paste snippets for each:

1. Add `exec-once = ~/.cargo/bin/vibewatch daemon` (Hyprland) or the
   equivalent `spawn-at-startup` line (Niri) to your compositor config.
2. Include `~/.config/vibewatch/waybar-module.jsonc` in your Waybar
   layout and add `"custom/vibewatch"` to your modules.
3. (Optional) For cleanest widget-click-to-focus on Hyprland, add
   `cursor { no_warps = true }` and `input { mouse_refocus = false }`.

Run `vibewatch install --help` for flags (`--no-service`, `--no-hooks`,
`--dry-run`, `--uninstall`).
```

## Dotfiles-side design

### 1. `packages/groups/ai.yaml`

Add to `custom_install:` list:

```yaml
custom_install:
  # … existing entries (hyprvoice etc.) …
  - name: vibewatch
    check: command -v vibewatch || test -f "$HOME/.cargo/bin/vibewatch"
    install: curl -fsSL https://raw.githubusercontent.com/Moinax/vibewatch/main/install.sh | sh
    requires: cargo
```

Add to `descriptions:`:

```yaml
vibewatch: AI agent status bar & overlay for Hyprland/Niri (built from source via cargo)
```

Because the group installer already supports per-tool deselection via the tree selector, vibewatch is individually togglable without any installer change.

### 2. `.install_vibewatch` chezmoi data flag

Seeded in `~/.config/chezmoi/chezmoi.toml`. Two places set it:

- **`manage.sh reconfig`** — add `install_vibewatch` to the existing toggle menu (the same menu that already handles `install_hyprland`, `install_niri`, `install_development`, etc.). Follow the exact same pattern.
- **`install/installer.sh`** — when the `vibewatch` custom_install entry is selected/skipped, write the corresponding bool into chezmoi data.

### 3. Templates — gate vibewatch bits on `.install_vibewatch`

| File | Change |
|---|---|
| `home/dot_config/waybar/modules.jsonc.tmpl` | Wrap the `"custom/vibewatch": { … }` block in `{{ if .install_vibewatch }} … {{ end }}`. |
| `home/dot_config/waybar/config-hyprland.tmpl` | Gate the `"custom/vibewatch"` entry in `modules-center`. Watch trailing commas. |
| `home/dot_config/waybar/config-niri.tmpl` | Same. |
| `home/dot_config/hypr/conf/autostart.conf.tmpl` | `{{ if .install_vibewatch }}exec-once = ~/.cargo/bin/vibewatch daemon{{ end }}`. Keep the explicit path — Hyprland `exec-once` runs outside the interactive shell's PATH. |
| `home/dot_config/niri/config.kdl.tmpl` | `{{ if .install_vibewatch }}spawn-at-startup "sh" "-c" "~/.cargo/bin/vibewatch daemon"{{ end }}`. Same reason. |
| `home/dot_claude/settings.json` | **Remove** the 6 vibewatch hook entries entirely. This file stops being vibewatch-aware; `vibewatch install` owns it. |

### 4. Templates that stay unconditional (not vibewatch's problem)

- `home/dot_config/hypr/conf/cursor.conf.tmpl` — `cursor { no_warps = true }` stays. Personal preference, predates vibewatch conceptually.
- `home/dot_config/hypr/conf/input*.conf` — `mouse_refocus = false` stays. Same reason.
- `home/dot_zshenv.tmpl` — `~/.cargo/bin` on PATH stays. Generic cargo bin path, not vibewatch-specific.

vibewatch's README independently recommends the cursor/mouse tweaks, so non-dotfiles users get the same guidance.

## Migration plan (to avoid breaking your live machine)

Execute in this order so the live `~/.claude/settings.json` is **always** correct:

1. **vibewatch repo first.** Implement `install.sh` + `vibewatch install`. Land the README update. Build + install the new binary. Run `vibewatch install` on your own box. Confirm that `~/.claude/settings.json` is byte-equivalent to what chezmoi currently owns (same hook block, same keys, same indentation).
2. **Dotfiles repo second.** Add the `ai.yaml` custom_install entry. Add `install_vibewatch` to `manage.sh reconfig`. Seed `.install_vibewatch = true` in your local chezmoi data. Gate the templates. Remove the hook block from `home/dot_claude/settings.json`. Commit.
3. **`chezmoi diff`.** The *only* expected drift is: hooks are in the live file but no longer in chezmoi source. `chezmoi apply` should be a no-op on every vibewatch-gated file because `.install_vibewatch = true`, and should **not** remove the hooks (chezmoi won't re-delete content that isn't in its source — it only rewrites paths it manages).
4. **Verification toggle.** Run `manage.sh reconfig`, flip `install_vibewatch` to `false`. `chezmoi diff` must show the vibewatch lines disappearing from Waybar/autostart. Don't apply — just verify the diff. Flip back to `true`, confirm diff clears.

## Verification

### Unit tests — `vibewatch install`

Add Rust tests for the subcommand's pure functions:

- `merge_hooks_is_idempotent` — start with a settings.json containing the vibewatch hook block, merge again, assert byte-equal output.
- `merge_hooks_preserves_unrelated_keys` — settings.json with `permissions`, `enabledPlugins`, `statusLine` etc. survives round-trip untouched.
- `uninstall_removes_only_vibewatch_hooks` — a settings.json with a mix of vibewatch and non-vibewatch hook entries loses only the vibewatch ones.
- `dry_run_touches_no_filesystem` — tempdir-scoped, assert no writes occurred.
- `systemd_skipped_when_systemctl_missing` — mock `which` to return false, assert service step is skipped with a warning, not an error.

### End-to-end dry run

Fresh Arch VM (or fresh user on a fresh container). Install rustup, then:

```bash
curl -fsSL https://raw.githubusercontent.com/Moinax/vibewatch/main/install.sh | sh
```

Assertions:

- `systemctl --user is-active vibewatch` → `active`.
- `~/.claude/settings.json` contains the 6 hook entries, parses as valid JSON.
- `vibewatch status` returns JSON.
- Manual-step instructions printed at end of `vibewatch install`.

### Dotfiles round-trip on the primary machine

After migration:

- `chezmoi diff` — clean (except for the intended hook removal from source, which `chezmoi apply` will not write back because it's absent from source).
- `manage.sh reconfig` → `install_vibewatch = false` → `chezmoi diff` shows vibewatch lines disappearing from Waybar modules/layout, Hyprland/Niri autostart. (Do not apply.)
- Flip back to `true` → `chezmoi diff` clean again.

### Uninstall path

On a machine with vibewatch installed: `vibewatch install --uninstall`, then assert:

- Service stopped and disabled; unit file removed.
- `~/.claude/settings.json` still parses; hook array entries whose command contains `vibewatch` are gone; other entries intact.
- `~/.config/vibewatch/` removed (if empty after the snippet deletion).
- `which vibewatch` still works (the binary itself isn't removed — that's `cargo uninstall`'s job).

## Explicitly out of scope

- Editing the user's existing Waybar `config.jsonc`, Hyprland config, or Niri config in place. Too many hand-crafted layouts to do this safely.
- Packaging vibewatch for AUR / COPR / APT repos. `cargo install` works on every supported distro; repo packaging is a future concern.
- Supporting compositors beyond Hyprland and Niri in the installer's printed snippets. (The daemon may work elsewhere; the installer just won't print autostart snippets for them.)
- Multi-user system-wide install. `vibewatch install` writes only to `$HOME`; a system install would need a separate design.
