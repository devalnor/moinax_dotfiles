# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles for Arch Linux and Fedora, managed with [Chezmoi](https://www.chezmoi.io/). Uses an interactive TUI installer powered by [gum](https://github.com/charmbracelet/gum).

## Key Commands

```bash
# Bootstrap: installs gum + git, then launches interactive installer
./setup.sh

# After editing files in home/, preview and apply with Chezmoi
chezmoi diff                    # see what would change
chezmoi apply                   # apply source state to $HOME
chezmoi edit ~/.zshrc           # edit a managed file (writes back to source)

# Cursor extensions
./manage-cursor-extensions.sh export   # save current extensions list
./manage-cursor-extensions.sh install  # install from saved list
```

## Architecture

### Installer pipeline
`setup.sh` → `install/installer.sh` → distro-specific scripts + package YAML files

- `install/distros/{arch,fedora}.sh` — package manager wrappers per distro
- `install/lib/common.sh` — shared utilities
- `install/lib/detect.sh` — distro detection
- `install/lib/services.sh` — systemd service enablement

### Package definitions (`packages/`)
YAML files define packages per distro. Groups (`packages/groups/`) are selectable during install: `hyprland`, `niri`, `development`, `gaming`, `multimedia`, `productivity`.

- `packages/common.yaml` — cross-distro tools installed via custom methods (zoxide, volta, etc.)
- `packages/{arch,fedora}/base.yaml` — distro base packages

### Chezmoi source directory (`home/`)
The `home/` directory is the Chezmoi source. Files use Chezmoi naming conventions:
- `dot_` prefix → `.` (e.g., `dot_zshrc.tmpl` → `~/.zshrc`)
- `.tmpl` suffix → Go template, rendered with Chezmoi data
- `home/.chezmoiignore` — conditionally excludes configs based on template variables like `.install_hyprland`, `.install_niri`, `.install_development`, `.install_productivity`

### Managed configs (`home/dot_config/`)
Hypr, Niri, Waybar, Rofi, Mako, Wlogout (Wayland compositors/desktop), Kitty (terminal), Neovim (AstroNvim-based), Delta (git diffs), Starship (prompt), Yazi (file manager), Cursor (editor).

## Adding a new distribution

1. Create `install/distros/<distro>.sh` with package manager functions
2. Create `packages/<distro>/base.yaml`
3. Add distro-specific entries to `packages/groups/*.yaml`
4. Update `install/lib/detect.sh` if needed

## Conventions

- Shell scripts use `set -e` and consistent color-coded output helpers (`print_info`, `print_success`, `print_error`, `print_warning`)
- Package lists are YAML with per-distro keys (`arch:`, `fedora:`)
- Wayland desktop components (waybar, rofi, mako, wlogout) are shared between Hyprland and Niri
