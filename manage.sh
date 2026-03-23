#!/bin/bash
# Dotfiles Management Script — single entry point for all dotfiles operations
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities
source "$SCRIPT_DIR/install/lib/common.sh"
source "$SCRIPT_DIR/install/lib/detect.sh"

CHEZMOI_CONF="$HOME/.config/chezmoi/chezmoi.toml"

# ── Helpers ──────────────────────────────────────────────────────────────────

usage() {
    cat <<'EOF'
Usage: ./manage.sh [command]

Commands:
  setup       Run full installer (bootstrap + interactive setup)
  apply       Apply dotfiles via chezmoi
  diff        View dotfiles diff
  whisper     Update whisper model for hyprvoice dictation
  reconfig    Reconfigure chezmoi data flags
  cursor      Manage Cursor extensions
  apps        Manage AppImages and Distrobox apps
  update      Update system packages
  lazy-lock   Sync nvim lazy-lock.json back to dotfiles source
  help        Show this help message

Run without arguments for an interactive menu.
EOF
}

is_desktop_install() {
    [ -f "$CHEZMOI_CONF" ] && grep -Eq '^[[:space:]]*install_purpose[[:space:]]*=[[:space:]]*"desktop"' "$CHEZMOI_CONF"
}

external_apps_available() {
    is_desktop_install && command_exists distrobox-enter
}

# ── Actions ──────────────────────────────────────────────────────────────────

do_setup() {
    exec "$SCRIPT_DIR/tools/setup.sh"
}

do_apply() {
    print_info "Applying dotfiles..."
    chezmoi apply --force
    print_success "Dotfiles applied"
}

do_diff() {
    chezmoi diff
}

do_whisper() {
    if ! command_exists hyprvoice; then
        print_error "hyprvoice is not installed"
        exit 1
    fi

    # Get current model from chezmoi config
    local current_model=""
    if [ -f "$CHEZMOI_CONF" ]; then
        current_model=$(grep 'hyprvoice_model' "$CHEZMOI_CONF" 2>/dev/null | sed 's/.*= *"\?\([^"]*\)"\?/\1/' || true)
    fi

    # Parse available models from hyprvoice output (whisper-cpp section)
    local model_list
    model_list=$(hyprvoice model list 2>/dev/null)
    local models=()
    local model_names=()
    while IFS= read -r line; do
        # Match lines like "  [x] small - Free/offline; ..." or "  [ ] medium - Free/offline; ..."
        if [[ "$line" =~ ^[[:space:]]*\[.\][[:space:]]+(.+)$ ]]; then
            local entry="${BASH_REMATCH[1]}"
            local name="${entry%% -*}"
            name="${name%% *}"
            if [ "$name" = "$current_model" ]; then
                models+=("$entry (current)")
            else
                models+=("$entry")
            fi
            model_names+=("$name")
        fi
    done <<< "$model_list"

    if [ ${#models[@]} -eq 0 ]; then
        print_error "No whisper models found"
        exit 1
    fi

    # Let user choose a model, pre-selecting the current one
    local cursor_arg=""
    if [ -n "$current_model" ]; then
        for i in "${!model_names[@]}"; do
            if [ "${model_names[$i]}" = "$current_model" ]; then
                cursor_arg="$((i + 1))"
                break
            fi
        done
    fi

    local chosen
    chosen=$(printf '%s\n' "${models[@]}" | gum choose --cursor.foreground="212" \
        ${cursor_arg:+--cursor-prefix="> " --selected-prefix="> "} \
        --header "Select whisper model:") || {
        echo "Cancelled."
        return
    }

    # Strip " (current)" suffix and description to get model name
    chosen="${chosen% (current)}"
    chosen="${chosen%% -*}"
    chosen="${chosen%% *}"

    if [ "$chosen" = "$current_model" ]; then
        print_info "Model '$chosen' is already the current model"
        return
    fi

    print_info "Downloading whisper model: $chosen"
    if hyprvoice model download "$chosen"; then
        print_success "Model '$chosen' downloaded"
    else
        print_error "Failed to download model '$chosen'"
        return 1
    fi

    # Update chezmoi.toml
    if [ -f "$CHEZMOI_CONF" ]; then
        if grep -q 'hyprvoice_model = ' "$CHEZMOI_CONF"; then
            sed -i 's/hyprvoice_model = .*/hyprvoice_model = "'"$chosen"'"/' "$CHEZMOI_CONF"
        else
            sed -i '/^\[data\]/a\    hyprvoice_model = "'"$chosen"'"' "$CHEZMOI_CONF"
        fi
        print_success "Updated hyprvoice_model in chezmoi.toml"
    fi

    # Re-apply hyprvoice config
    print_info "Re-applying hyprvoice config..."
    chezmoi apply --force ~/.config/hyprvoice

    # Restart daemon if running
    if hyprvoice status 2>/dev/null | grep -q "status="; then
        print_info "Restarting hyprvoice daemon..."
        hyprvoice stop &>/dev/null || true
        hyprvoice serve &>/dev/null &
        disown
        # Wait up to 5s for daemon to be ready
        for _ in $(seq 1 10); do
            sleep 0.5
            hyprvoice status 2>/dev/null | grep -q "status=" && break
        done
        print_success "Hyprvoice daemon restarted"
    fi
}

do_reconfig() {
    if [ ! -f "$CHEZMOI_CONF" ]; then
        print_error "chezmoi.toml not found at $CHEZMOI_CONF"
        print_info "Run the full installer first: ./manage.sh setup"
        exit 1
    fi

    print_header "Reconfigure Chezmoi Data"

    # Read boolean flags from [data] section
    local flags=()
    local in_data=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[data\] ]]; then
            in_data=true
            continue
        fi
        if $in_data; then
            # Stop at next section
            [[ "$line" =~ ^\[.+\] ]] && break
            # Match boolean flags like: install_hyprland = true
            if [[ "$line" =~ ^[[:space:]]*([a-z_]+)[[:space:]]*=[[:space:]]*(true|false) ]]; then
                local key="${BASH_REMATCH[1]}"
                local val="${BASH_REMATCH[2]}"
                flags+=("$key = $val")
            fi
        fi
    done < "$CHEZMOI_CONF"

    if [ ${#flags[@]} -eq 0 ]; then
        print_warning "No boolean flags found in [data] section"
        return
    fi

    # Show current flags, let user select which to toggle
    print_info "Select flags to toggle (space to select, enter to confirm):"
    local selected
    selected=$(printf '%s\n' "${flags[@]}" | gum filter --no-limit --header "Toggle flags:") || {
        echo "Cancelled."
        return
    }

    if [ -z "$selected" ]; then
        print_info "No flags selected"
        return
    fi

    # Toggle each selected flag
    while IFS= read -r entry; do
        local key="${entry%% =*}"
        local val="${entry##*= }"
        local new_val
        if [ "$val" = "true" ]; then
            new_val="false"
        else
            new_val="true"
        fi
        sed -i "s/${key} = ${val}/${key} = ${new_val}/" "$CHEZMOI_CONF"
        print_info "Toggled $key: $val → $new_val"
    done <<< "$selected"

    print_success "Flags updated in chezmoi.toml"

    # Offer to apply immediately
    if gum confirm "Apply dotfiles now?"; then
        do_apply
    fi
}

do_cursor() {
    exec "$SCRIPT_DIR/tools/manage-cursor-extensions.sh" "$@"
}

do_apps() {
    if ! is_desktop_install; then
        print_error "External apps helper is only available for desktop installs"
        return 1
    fi

    if ! command_exists distrobox-enter; then
        print_error "distrobox-enter is not installed"
        print_info "Run the desktop installer or install Distrobox first."
        return 1
    fi

    exec "$SCRIPT_DIR/tools/manage-external-apps.sh" "$@"
}

do_update() {
    local distro
    distro=$(detect_distro)
    local family
    family=$(get_distro_family "$distro")

    print_header "Update System Packages"

    case "$family" in
        arch)
            if command_exists paru; then
                print_info "Updating with paru..."
                paru -Syu
            elif command_exists yay; then
                print_info "Updating with yay..."
                yay -Syu
            else
                print_info "Run: sudo pacman -Syu"
            fi
            ;;
        fedora)
            print_info "Run: sudo dnf upgrade --refresh"
            ;;
        debian)
            print_info "Run: sudo apt update && sudo apt upgrade"
            ;;
        *)
            print_error "Unsupported distro family: $family"
            exit 1
            ;;
    esac
}

do_lazy_lock() {
    local src="$HOME/.config/nvim/lazy-lock.json"
    local dest="$SCRIPT_DIR/home/dot_config/nvim/lazy-lock.json"

    if [[ ! -f "$src" ]]; then
        print_error "No lazy-lock.json found at $src"
        exit 1
    fi

    cp "$src" "$dest"
    print_success "Synced lazy-lock.json to dotfiles source"
    print_info "Review with 'git diff' and commit when ready"
}

# ── Interactive menu ─────────────────────────────────────────────────────────

do_menu() {
    if ! command_exists gum; then
        print_error "gum is not installed. Run './manage.sh setup' first or install gum manually."
        exit 1
    fi

    while true; do
        print_header "Dotfiles Manager"

        # Build menu options dynamically
        local options=()
        options+=("Run full installer")
        options+=("Apply dotfiles")
        options+=("View dotfiles diff")
        if command_exists hyprvoice; then
            options+=("Update whisper model")
        fi
        options+=("Reconfigure chezmoi data")
        if command_exists cursor; then
            options+=("Manage Cursor extensions")
        fi
        if external_apps_available; then
            options+=("Manage external apps")
        fi
        options+=("Update system packages")
        options+=("Exit")

        local choice
        choice=$(printf '%s\n' "${options[@]}" | gum choose --cursor.foreground="212" --header "What would you like to do?") || break

        case "$choice" in
            "Run full installer")          do_setup ;;
            "Apply dotfiles")              do_apply ;;
            "View dotfiles diff")          do_diff ;;
            "Update whisper model")        do_whisper ;;
            "Reconfigure chezmoi data")    do_reconfig ;;
            "Manage Cursor extensions")    do_cursor ;;
            "Manage external apps")        do_apps ;;
            "Update system packages")      do_update ;;
            "Exit")                        break ;;
        esac
    done
}

# ── CLI dispatch ─────────────────────────────────────────────────────────────

case "${1:-}" in
    setup)      do_setup ;;
    apply)      do_apply ;;
    diff)       do_diff ;;
    whisper)    do_whisper ;;
    reconfig)   do_reconfig ;;
    cursor)     shift; do_cursor "$@" ;;
    apps)       shift; do_apps "$@" ;;
    update)     do_update ;;
    lazy-lock)  do_lazy_lock ;;
    help|--help|-h) usage ;;
    *)          do_menu ;;
esac
