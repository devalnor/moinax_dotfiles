#!/bin/bash
# GRUB Theme Manager — install, switch, and remove GRUB bootloader themes
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source shared utilities
source "$REPO_DIR/install/lib/common.sh"
source "$REPO_DIR/install/lib/detect.sh"

GRUB_DEFAULT="/etc/default/grub"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/grub-themes"
CLONE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/grub-theme-repos"

# Detect distro family for grub-mkconfig path differences
DISTRO=$(detect_distro)
DISTRO_FAMILY=$(get_distro_family "$DISTRO")

# ── Theme registry ───────────────────────────────────────────────────────────
# Each theme is defined by a set of variables: _REPO, _VARIANTS, _INSTALL_METHOD

THEME_IDS=("catppuccin" "vinceliuice" "poly-dark" "hyperfluent")
THEME_LABELS=("Catppuccin" "Vinceliuice grub2-themes" "Poly Dark" "HyperFluent")

# Catppuccin — 4 pastel flavors
catppuccin_REPO="https://github.com/catppuccin/grub.git"
catppuccin_VARIANTS=("latte" "frappe" "macchiato" "mocha")
catppuccin_VARIANT_LABELS=("Latte (light)" "Frappé (medium-dark)" "Macchiato (dark)" "Mocha (darkest)")

# Vinceliuice grub2-themes — 4 modern themes with built-in resolution support
vinceliuice_REPO="https://github.com/vinceliuice/grub2-themes.git"
vinceliuice_VARIANTS=("tela" "vimix" "stylish" "whitesur")
vinceliuice_VARIANT_LABELS=("Tela" "Vimix" "Stylish" "WhiteSur")

# Poly Dark — single minimalist theme
poly_dark_REPO="https://github.com/shvchk/poly-dark.git"
poly_dark_VARIANTS=()
poly_dark_VARIANT_LABELS=()

# HyperFluent — distro-specific fluent themes
hyperfluent_REPO="https://github.com/Coopydood/HyperFluent-GRUB-Theme.git"
hyperfluent_VARIANTS=("arch" "fedora" "ubuntu" "debian" "nixos" "endeavouros" "manjaro" "opensuse" "linuxmint" "gentoo" "zorin" "windows-dark" "windows-light" "macos" "linux-generic")
hyperfluent_VARIANT_LABELS=("Arch Linux" "Fedora" "Ubuntu" "Debian" "NixOS" "EndeavourOS" "Manjaro" "openSUSE" "Linux Mint" "Gentoo" "Zorin OS" "Windows (Dark)" "Windows (Light)" "macOS" "Linux (Generic)")

# ── Resolution presets ───────────────────────────────────────────────────────

RESOLUTION_LABELS=("1080p (1920x1080) — fastest, recommended" "2K (2560x1440)" "4K (3840x2160) — may feel slow" "Ultrawide (2560x1080)" "Ultrawide 2K (3440x1440)" "Auto (let GRUB decide)")
RESOLUTION_VALUES=("1920x1080" "2560x1440" "3840x2160" "2560x1080" "3440x1440" "auto")

# ── Helpers ──────────────────────────────────────────────────────────────────

usage() {
    cat <<'EOF'
Usage: ./manage.sh grub-theme [command]

Commands:
  install     Install a theme from the registry
  switch      Switch the active theme (from already installed themes)
  remove      Remove an installed theme
  resolution  Change GRUB display resolution
  status      Show current theme and resolution

Run without arguments for an interactive wizard.
EOF
}

ensure_dirs() {
    mkdir -p "$STATE_DIR" "$CLONE_CACHE_DIR"
}

_theme_var() {
    local id="$1" var="$2"
    local safe_id="${id//-/_}"
    declare -n ref="${safe_id}_${var}"
    echo "${ref[@]}"
}

_theme_var_array() {
    local id="$1" var="$2"
    local safe_id="${id//-/_}"
    declare -n ref="${safe_id}_${var}"
    printf '%s\n' "${ref[@]}"
}

# Get GRUB themes directory
get_grub_themes_dir() {
    if [ -d "/usr/share/grub/themes" ]; then
        echo "/usr/share/grub/themes"
    elif [ -d "/boot/grub/themes" ]; then
        echo "/boot/grub/themes"
    elif [ -d "/boot/grub2/themes" ]; then
        echo "/boot/grub2/themes"
    else
        # Default — will be created
        echo "/usr/share/grub/themes"
    fi
}

# Run grub-mkconfig for the current distro
run_grub_mkconfig() {
    print_info "Regenerating GRUB config..."
    if [ "$DISTRO_FAMILY" = "fedora" ]; then
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg || {
            print_error "grub2-mkconfig failed — theme files are installed but GRUB config was not updated"
            return 1
        }
    else
        sudo grub-mkconfig -o /boot/grub/grub.cfg || {
            print_error "grub-mkconfig failed — theme files are installed but GRUB config was not updated"
            return 1
        }
    fi
}

# Read current GRUB_THEME from /etc/default/grub
get_current_theme_path() {
    [ -f "$GRUB_DEFAULT" ] || return 0
    grep -E '^GRUB_THEME=' "$GRUB_DEFAULT" 2>/dev/null | head -1 | sed 's/^GRUB_THEME="//;s/"$//' || true
}

# Read current GRUB_GFXMODE
get_current_gfxmode() {
    [ -f "$GRUB_DEFAULT" ] || return 0
    grep -E '^GRUB_GFXMODE=' "$GRUB_DEFAULT" 2>/dev/null | head -1 | sed 's/^GRUB_GFXMODE="//;s/"$//' || true
}

# Pretty-print current theme name from its path
get_current_theme_name() {
    local path
    path=$(get_current_theme_path)
    if [ -z "$path" ]; then
        echo "None"
    else
        # Extract theme dir name from path like /usr/share/grub/themes/catppuccin-mocha-grub-theme/theme.txt
        local dir
        dir=$(dirname "$path")
        basename "$dir"
    fi
}

# Set a GRUB config variable (add or update)
set_grub_var() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$GRUB_DEFAULT" 2>/dev/null; then
        sudo sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$GRUB_DEFAULT"
    elif grep -q "^#\s*${key}=" "$GRUB_DEFAULT" 2>/dev/null; then
        sudo sed -i "s|^#\s*${key}=.*|${key}=\"${value}\"|" "$GRUB_DEFAULT"
    else
        echo "${key}=\"${value}\"" | sudo tee -a "$GRUB_DEFAULT" > /dev/null
    fi
}

# Comment out a GRUB config variable
comment_grub_var() {
    local key="$1"
    if grep -q "^${key}=" "$GRUB_DEFAULT" 2>/dev/null; then
        sudo sed -i "s|^${key}=|# ${key}=|" "$GRUB_DEFAULT"
    fi
}

ensure_gfxterm() {
    local current
    current=$(grep -E '^GRUB_TERMINAL_OUTPUT=' "$GRUB_DEFAULT" 2>/dev/null | head -1 | sed 's/^GRUB_TERMINAL_OUTPUT="//;s/"$//' || true)
    if [ "$current" != "gfxterm" ]; then
        print_info "Setting GRUB_TERMINAL_OUTPUT to gfxterm"
        set_grub_var "GRUB_TERMINAL_OUTPUT" "gfxterm"
    fi
}

# Clone or update a theme repo
clone_theme_repo() {
    local id="$1"
    local repo
    repo=$(_theme_var "$id" "REPO")
    local dest="$CLONE_CACHE_DIR/$id"

    if [ -d "$dest/.git" ]; then
        print_info "Updating cached repo for $id..." >&2
        git -C "$dest" pull --quiet 2>/dev/null || true
    else
        print_info "Cloning $id theme repo..." >&2
        rm -rf "$dest"
        git clone --depth 1 --quiet "$repo" "$dest" >&2
    fi
    echo "$dest"
}

# Record a theme as managed
record_installed() {
    local theme_name="$1"
    ensure_dirs
    if ! grep -qxF "$theme_name" "$STATE_DIR/installed.txt" 2>/dev/null; then
        echo "$theme_name" >> "$STATE_DIR/installed.txt"
    fi
}

# Remove a theme from the managed list
unrecord_installed() {
    local theme_name="$1"
    [ -f "$STATE_DIR/installed.txt" ] || return 0
    local tmp
    tmp=$(grep -vxF "$theme_name" "$STATE_DIR/installed.txt" || true)
    echo "$tmp" > "$STATE_DIR/installed.txt"
}

# List themes we've installed (from state file)
list_managed_themes() {
    [ -f "$STATE_DIR/installed.txt" ] || return 0
    grep -v '^$' "$STATE_DIR/installed.txt" 2>/dev/null || true
}

# ── Resolution picker ────────────────────────────────────────────────────────

pick_resolution() {
    local current_gfxmode
    current_gfxmode=$(get_current_gfxmode)

    local options=()
    for i in "${!RESOLUTION_LABELS[@]}"; do
        local label="${RESOLUTION_LABELS[$i]}"
        if [ -n "$current_gfxmode" ] && [[ "$current_gfxmode" == "${RESOLUTION_VALUES[$i]}"* ]]; then
            label="$label (current)"
        fi
        options+=("$label")
    done

    local chosen
    chosen=$(printf '%s\n' "${options[@]}" | gum choose --cursor.foreground="212" \
        --header "Select GRUB display resolution:") || return 1

    # Strip " (current)" suffix and map back to value
    chosen="${chosen% (current)}"
    for i in "${!RESOLUTION_LABELS[@]}"; do
        if [ "${RESOLUTION_LABELS[$i]}" = "$chosen" ]; then
            echo "${RESOLUTION_VALUES[$i]}"
            return 0
        fi
    done
}

# Apply resolution to GRUB config
apply_resolution() {
    local res="$1"
    if [ "$res" = "auto" ]; then
        set_grub_var "GRUB_GFXMODE" "auto"
    else
        set_grub_var "GRUB_GFXMODE" "${res}x32,${res},auto"
    fi
    set_grub_var "GRUB_GFXPAYLOAD_LINUX" "keep"
}

# ── Theme installation ───────────────────────────────────────────────────────

# These install functions are called inside $(), so only the final echo (theme.txt path)
# should go to stdout. All other output (progress, errors, sudo) must go to stderr.

install_copy_theme() {
    local src_dir="$1" dest_name="$2" themes_dir="$3"
    if [ ! -d "$src_dir" ]; then
        print_error "Theme source not found: $src_dir" >&2
        return 1
    fi
    sudo cp -r "$src_dir" "$themes_dir/$dest_name" >&2
    record_installed "$dest_name"
    echo "$themes_dir/$dest_name/theme.txt"
}

install_catppuccin() {
    local variant="$1" repo_dir="$2" themes_dir="$3"
    install_copy_theme "$repo_dir/src/catppuccin-${variant}-grub-theme" "catppuccin-${variant}-grub-theme" "$themes_dir"
}

install_vinceliuice() {
    local variant="$1" repo_dir="$2" themes_dir="$3" res_id="$4"
    local res_flag="1080p"
    case "$res_id" in
        1920x1080)    res_flag="1080p" ;;
        2560x1440)    res_flag="2k" ;;
        3840x2160)    res_flag="4k" ;;
        2560x1080)    res_flag="ultrawide" ;;
        3440x1440)    res_flag="ultrawide2k" ;;
        auto)         res_flag="1080p" ;;
    esac

    print_info "Running vinceliuice installer: theme=$variant, resolution=$res_flag" >&2
    sudo bash "$repo_dir/install.sh" -t "$variant" -s "$res_flag" >&2

    record_installed "$variant"
    echo "$themes_dir/$variant/theme.txt"
}

install_poly_dark() {
    local repo_dir="$1" themes_dir="$2"
    local dest_name="poly-dark"
    sudo mkdir -p "$themes_dir/$dest_name" >&2
    sudo rsync -a --exclude='.git' --exclude='.gitignore' --exclude='README.md' \
        --exclude='LICENSE' --exclude='install.sh' "$repo_dir/" "$themes_dir/$dest_name/" >&2
    record_installed "$dest_name"
    echo "$themes_dir/$dest_name/theme.txt"
}

install_hyperfluent() {
    local variant="$1" repo_dir="$2" themes_dir="$3"
    # HyperFluent stores variants in named directories at repo root
    install_copy_theme "$repo_dir/$variant" "hyperfluent-${variant}" "$themes_dir"
}

# Dispatch to the right install function
dispatch_install() {
    local theme_id="$1" variant="$2" repo_dir="$3" themes_dir="$4" resolution="$5"
    case "$theme_id" in
        catppuccin)  install_catppuccin "$variant" "$repo_dir" "$themes_dir" ;;
        vinceliuice) install_vinceliuice "$variant" "$repo_dir" "$themes_dir" "$resolution" ;;
        poly-dark)   install_poly_dark "$repo_dir" "$themes_dir" ;;
        hyperfluent) install_hyperfluent "$variant" "$repo_dir" "$themes_dir" ;;
        *)           print_error "Unknown theme: $theme_id"; return 1 ;;
    esac
}

# Clone, install, and activate a theme — shared by do_install and do_setup
clone_install_activate() {
    local theme_id="$1" variant="$2" resolution="$3"

    local repo_dir
    repo_dir=$(clone_theme_repo "$theme_id")

    local themes_dir
    themes_dir=$(get_grub_themes_dir)
    sudo mkdir -p "$themes_dir"

    local theme_txt
    theme_txt=$(dispatch_install "$theme_id" "$variant" "$repo_dir" "$themes_dir" "$resolution")

    if [ -z "$theme_txt" ]; then
        return 1
    fi

    set_grub_var "GRUB_THEME" "$theme_txt"
    apply_resolution "$resolution"
    ensure_gfxterm
    run_grub_mkconfig
}

# ── Main actions ─────────────────────────────────────────────────────────────

do_status() {
    local theme_name
    theme_name=$(get_current_theme_name)
    local gfxmode
    gfxmode=$(get_current_gfxmode)

    echo ""
    gum style --border rounded --border-foreground 212 --padding "1 2" --margin "0 1" \
        "Current GRUB theme: $(gum style --foreground 212 "$theme_name")" \
        "Resolution (GFXMODE): $(gum style --foreground 212 "${gfxmode:-not set}")"
    echo ""
}

do_install() {
    if [ ! -f "$GRUB_DEFAULT" ]; then
        print_error "$GRUB_DEFAULT not found — is GRUB installed?"
        return 1
    fi

    # Pick a theme from registry
    local theme_options=()
    for i in "${!THEME_IDS[@]}"; do
        theme_options+=("${THEME_LABELS[$i]}")
    done

    local chosen_label
    chosen_label=$(printf '%s\n' "${theme_options[@]}" | gum choose --cursor.foreground="212" \
        --header "Select a theme to install:") || return 0

    # Map back to ID
    local theme_id=""
    for i in "${!THEME_LABELS[@]}"; do
        if [ "${THEME_LABELS[$i]}" = "$chosen_label" ]; then
            theme_id="${THEME_IDS[$i]}"
            break
        fi
    done

    # Pick variant if the theme has variants
    local variants=()
    local variant_labels=()
    mapfile -t variants < <(_theme_var_array "$theme_id" "VARIANTS")
    mapfile -t variant_labels < <(_theme_var_array "$theme_id" "VARIANT_LABELS")

    local chosen_variant=""
    if [ ${#variants[@]} -gt 0 ] && [ -n "${variants[0]}" ]; then
        local chosen_variant_label
        chosen_variant_label=$(printf '%s\n' "${variant_labels[@]}" | gum choose --cursor.foreground="212" \
            --header "Select variant:") || return 0

        for i in "${!variant_labels[@]}"; do
            if [ "${variant_labels[$i]}" = "$chosen_variant_label" ]; then
                chosen_variant="${variants[$i]}"
                break
            fi
        done
    fi

    local resolution
    resolution=$(pick_resolution) || return 0

    ensure_dirs

    if gum confirm "Activate this theme now?"; then
        clone_install_activate "$theme_id" "$chosen_variant" "$resolution"
        print_success "Theme activated! Changes will take effect on next boot."
    else
        # Install without activating
        local repo_dir
        repo_dir=$(clone_theme_repo "$theme_id")
        local themes_dir
        themes_dir=$(get_grub_themes_dir)
        sudo mkdir -p "$themes_dir"
        dispatch_install "$theme_id" "$chosen_variant" "$repo_dir" "$themes_dir" "$resolution"
        print_info "Theme installed but not activated. Use 'Switch theme' to activate later."
    fi
}

do_switch() {
    if [ ! -f "$GRUB_DEFAULT" ]; then
        print_error "$GRUB_DEFAULT not found"
        return 1
    fi

    local themes_dir
    themes_dir=$(get_grub_themes_dir)

    # Scan for installed themes (any dir with theme.txt)
    local installed=()
    if [ -d "$themes_dir" ]; then
        for d in "$themes_dir"/*/; do
            [ -f "$d/theme.txt" ] && installed+=("$(basename "$d")")
        done
    fi

    if [ ${#installed[@]} -eq 0 ]; then
        print_warning "No themes installed in $themes_dir"
        print_info "Use 'Install theme' to add one first."
        return 0
    fi

    # Add "None (disable theme)" option
    local options=("None (disable theme)")
    local current_name
    current_name=$(get_current_theme_name)
    for name in "${installed[@]}"; do
        if [ "$name" = "$current_name" ]; then
            options+=("$name (current)")
        else
            options+=("$name")
        fi
    done

    local chosen
    chosen=$(printf '%s\n' "${options[@]}" | gum choose --cursor.foreground="212" \
        --header "Select active theme:") || return 0

    chosen="${chosen% (current)}"

    if [ "$chosen" = "None (disable theme)" ]; then
        comment_grub_var "GRUB_THEME"
        run_grub_mkconfig
        print_success "Theme disabled"
        return 0
    fi

    # Pick resolution
    local resolution
    resolution=$(pick_resolution) || return 0

    set_grub_var "GRUB_THEME" "$themes_dir/$chosen/theme.txt"
    apply_resolution "$resolution"
    ensure_gfxterm
    run_grub_mkconfig
    print_success "Switched to theme: $chosen"
}

do_remove() {
    local managed
    managed=$(list_managed_themes)

    if [ -z "$managed" ]; then
        print_warning "No managed themes to remove"
        print_info "Only themes installed by this tool can be removed."
        return 0
    fi

    local options=()
    while IFS= read -r name; do
        [ -n "$name" ] && options+=("$name")
    done <<< "$managed"

    local chosen
    chosen=$(printf '%s\n' "${options[@]}" | gum choose --cursor.foreground="212" \
        --header "Select theme to remove:") || return 0

    local themes_dir
    themes_dir=$(get_grub_themes_dir)

    if ! gum confirm "Remove theme '$chosen'?"; then
        echo "Cancelled."
        return 0
    fi

    # Check if this is the active theme
    local current_name was_active=false
    current_name=$(get_current_theme_name)
    if [ "$chosen" = "$current_name" ]; then
        print_info "This is the active theme — disabling it first"
        comment_grub_var "GRUB_THEME"
        was_active=true
    fi

    # For vinceliuice themes, try the uninstaller first
    local repo_cache="$CLONE_CACHE_DIR/vinceliuice"
    if [ -f "$repo_cache/install.sh" ] && [[ " tela vimix stylish whitesur " =~ " $chosen " ]]; then
        print_info "Running vinceliuice uninstaller..."
        sudo bash "$repo_cache/install.sh" -r -t "$chosen" 2>/dev/null || true
    else
        sudo rm -rf "$themes_dir/$chosen"
    fi

    unrecord_installed "$chosen"

    if [ "$was_active" = true ]; then
        run_grub_mkconfig
    fi

    print_success "Theme '$chosen' removed"
}

do_resolution() {
    if [ ! -f "$GRUB_DEFAULT" ]; then
        print_error "$GRUB_DEFAULT not found"
        return 1
    fi

    local resolution
    resolution=$(pick_resolution) || return 0

    apply_resolution "$resolution"
    run_grub_mkconfig
    print_success "Resolution updated"
}

# ── Wizard ───────────────────────────────────────────────────────────────────

do_wizard() {
    if ! command_exists gum; then
        print_error "gum is not installed"
        exit 1
    fi

    if [ ! -f "$GRUB_DEFAULT" ]; then
        print_error "$GRUB_DEFAULT not found — GRUB does not appear to be installed"
        exit 1
    fi

    while true; do
        do_status

        local choice
        choice=$(gum choose --cursor.foreground="212" --header "GRUB Theme Manager" \
            "Install theme" \
            "Switch theme" \
            "Remove theme" \
            "Change resolution" \
            "Exit") || break

        case "$choice" in
            "Install theme")     do_install ;;
            "Switch theme")      do_switch ;;
            "Remove theme")      do_remove ;;
            "Change resolution") do_resolution ;;
            "Exit")              break ;;
        esac
    done
}

# ── Installer integration ────────────────────────────────────────────────────
# Called from install/installer.sh during setup — non-interactive flow

do_setup() {
    if [ ! -f "$GRUB_DEFAULT" ]; then
        print_info "$GRUB_DEFAULT not found — skipping GRUB theme setup"
        return 0
    fi

    print_header "GRUB Theme"

    # Build theme + variant options for a single selection
    local options=("Keep current (skip)")
    declare -A option_to_theme  # label → "theme_id|variant"

    for i in "${!THEME_IDS[@]}"; do
        local id="${THEME_IDS[$i]}"
        local label="${THEME_LABELS[$i]}"
        local variants=()
        mapfile -t variants < <(_theme_var_array "$id" "VARIANTS")
        local variant_labels=()
        mapfile -t variant_labels < <(_theme_var_array "$id" "VARIANT_LABELS")

        if [ ${#variants[@]} -gt 0 ] && [ -n "${variants[0]}" ]; then
            for vi in "${!variants[@]}"; do
                local display="$label — ${variant_labels[$vi]}"
                options+=("$display")
                option_to_theme["$display"]="${id}|${variants[$vi]}"
            done
        else
            options+=("$label")
            option_to_theme["$label"]="${id}|"
        fi
    done

    local chosen
    chosen=$(printf '%s\n' "${options[@]}" | gum choose --cursor.foreground="212" \
        --header "Select a GRUB theme (or skip):") || return 0

    if [ "$chosen" = "Keep current (skip)" ]; then
        print_info "Keeping current GRUB theme"
        return 0
    fi

    # Map selection back to theme_id and variant
    local mapping="${option_to_theme[$chosen]:-}"
    if [ -z "$mapping" ]; then
        print_error "Could not determine selected theme"
        return 1
    fi
    local theme_id="${mapping%%|*}"
    local variant="${mapping#*|}"

    local resolution
    resolution=$(pick_resolution) || return 0

    ensure_dirs

    if ! clone_install_activate "$theme_id" "$variant" "$resolution"; then
        print_warning "Theme installation failed — skipping"
        return 0
    fi

    print_success "GRUB theme configured"
}

# ── CLI dispatch ─────────────────────────────────────────────────────────────

case "${1:-}" in
    install)    do_install ;;
    switch)     do_switch ;;
    remove)     do_remove ;;
    resolution) do_resolution ;;
    status)     do_status ;;
    setup)      do_setup ;;
    help|--help|-h) usage ;;
    *)          do_wizard ;;
esac
