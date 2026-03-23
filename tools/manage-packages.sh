#!/bin/bash
# Package Manager — add/remove packages from group definitions
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGES_DIR="$DOTFILES_DIR/packages"
GROUPS_DIR="$PACKAGES_DIR/groups"
CHEZMOI_CONF="$HOME/.config/chezmoi/chezmoi.toml"

# Source shared utilities
source "$DOTFILES_DIR/install/lib/common.sh"
source "$DOTFILES_DIR/install/lib/detect.sh"
source "$DOTFILES_DIR/install/lib/services.sh"

# Detect distro and source distro-specific functions
DISTRO=$(detect_distro)
DISTRO_FAMILY=$(get_distro_family "$DISTRO")

if [ -f "$DOTFILES_DIR/install/distros/$DISTRO_FAMILY.sh" ]; then
    source "$DOTFILES_DIR/install/distros/$DISTRO_FAMILY.sh"
else
    print_error "Unsupported distribution family: $DISTRO_FAMILY"
    exit 1
fi

# Check if install purpose is "terminal" (for filtering desktop_only packages)
is_terminal_install() {
    [ -f "$CHEZMOI_CONF" ] && grep -Eq '^[[:space:]]*install_purpose[[:space:]]*=[[:space:]]*"terminal"' "$CHEZMOI_CONF"
}

# ── YAML helpers ─────────────────────────────────────────────────────────────

# Get group name from YAML file
get_group_name() {
    local file="$1"
    if command_exists yq; then
        yq -r '.name // ""' "$file" 2>/dev/null
    else
        grep -m1 '^name:' "$file" | sed 's/^name:[[:space:]]*//'
    fi
}

# Get group icon from YAML file
get_group_icon() {
    local file="$1"
    if command_exists yq; then
        yq -r '.icon // ""' "$file" 2>/dev/null
    else
        grep -m1 '^icon:' "$file" | sed 's/^icon:[[:space:]]*//'
    fi
}

# Get group ID from filename (e.g., development.yaml -> development)
get_group_id() {
    local file="$1"
    basename "$file" .yaml
}

# Get chezmoi flag name for a group (e.g., development -> install_development)
get_chezmoi_flag() {
    local group_id="$1"
    echo "install_${group_id}"
}

# Read current chezmoi flag value (true/false/empty if not found)
get_chezmoi_flag_value() {
    local flag="$1"
    if [ -f "$CHEZMOI_CONF" ]; then
        grep -oP "^\s*${flag}\s*=\s*\K(true|false)" "$CHEZMOI_CONF" 2>/dev/null || true
    fi
}

# Update a chezmoi flag value
update_chezmoi_flag() {
    local flag="$1"
    local value="$2"

    if [ ! -f "$CHEZMOI_CONF" ]; then
        print_warning "chezmoi.toml not found, skipping flag update"
        return
    fi

    if grep -q "${flag} = " "$CHEZMOI_CONF"; then
        sed -i "s/${flag} = .*/${flag} = ${value}/" "$CHEZMOI_CONF"
        print_success "Updated ${flag} = ${value} in chezmoi.toml"
    fi
}

# ── Package list helpers ─────────────────────────────────────────────────────

# Build a list of packages for a group on the current distro,
# filtered by install purpose (desktop/terminal).
# Outputs one package name per line.
get_group_packages() {
    local file="$1"
    local all_packages desktop_only_list

    all_packages=$(parse_packages "$file" "$DISTRO_FAMILY")
    if [ -z "$all_packages" ]; then
        return
    fi

    # Filter desktop_only packages when in terminal mode
    if is_terminal_install; then
        desktop_only_list=$(parse_desktop_only "$file")
        if [ -n "$desktop_only_list" ]; then
            local filtered=""
            while IFS= read -r pkg; do
                if ! echo "$desktop_only_list" | grep -qxF "$pkg"; then
                    filtered+="${pkg}"$'\n'
                fi
            done <<< "$all_packages"
            echo -n "$filtered" | grep -v "^$"
            return
        fi
    fi

    echo "$all_packages"
}

# Build a descriptions associative array (pkg -> desc) from a group file
# Usage: load_descriptions "file.yaml"
# Sets global DESCRIPTIONS associative array
load_descriptions() {
    local file="$1"
    declare -gA DESCRIPTIONS=()
    local line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local key="${line%%=*}"
        local val="${line#*=}"
        DESCRIPTIONS["$key"]="$val"
    done < <(parse_descriptions "$file")
}

# ── Display helpers ──────────────────────────────────────────────────────────

# Format a package line for display: "package_name — description"
format_package() {
    local pkg="$1"
    local desc="${DESCRIPTIONS[$pkg]:-}"
    if [ -n "$desc" ]; then
        echo "${pkg} — ${desc}"
    else
        echo "$pkg"
    fi
}

# Extract package name from a formatted line
extract_package_name() {
    local line="$1"
    echo "$line" | sed 's/ — .*//'
}

# ── Group selection ──────────────────────────────────────────────────────────

# Show a gum chooser with all groups and their install counts.
# Returns the chosen group YAML file path, or empty on cancel.
choose_group() {
    local header="${1:-Select a group}"
    local group_files=("$GROUPS_DIR"/*.yaml)
    local labels=()
    local files=()

    for file in "${group_files[@]}"; do
        local name icon packages installed=0 total=0
        name=$(get_group_name "$file")
        icon=$(get_group_icon "$file")

        while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue
            total=$((total + 1))
            if is_package_installed "$pkg"; then
                installed=$((installed + 1))
            fi
        done < <(get_group_packages "$file")

        # Skip groups with no packages for this distro
        [ "$total" -eq 0 ] && continue

        labels+=("${icon} ${name} (${installed}/${total} installed)")
        files+=("$file")
    done

    if [ ${#labels[@]} -eq 0 ]; then
        print_warning "No package groups found for $DISTRO_FAMILY"
        return 1
    fi

    local chosen
    chosen=$(printf '%s\n' "${labels[@]}" | gum choose --cursor.foreground="212" --header "$header") || return 1

    # Find the matching file
    for i in "${!labels[@]}"; do
        if [ "${labels[$i]}" = "$chosen" ]; then
            echo "${files[$i]}"
            return 0
        fi
    done
    return 1
}

# ── Browse flow ──────────────────────────────────────────────────────────────

show_browse() {
    while true; do
        local file
        file=$(choose_group "Browse group packages") || return

        local name icon
        name=$(get_group_name "$file")
        icon=$(get_group_icon "$file")
        load_descriptions "$file"

        print_header "${icon} ${name}"

        local pkg
        while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue
            local desc="${DESCRIPTIONS[$pkg]:-}"
            local status
            if is_package_installed "$pkg"; then
                status="${GREEN}[x]${NC}"
            else
                status="${RED}[ ]${NC}"
            fi
            if [ -n "$desc" ]; then
                echo -e "  ${status} ${pkg} — ${desc}"
            else
                echo -e "  ${status} ${pkg}"
            fi
        done < <(get_group_packages "$file")

        echo ""
        read -rp "Press Enter to continue..."
    done
}

# ── Add flow ─────────────────────────────────────────────────────────────────

show_add() {
    local file
    file=$(choose_group "Add packages from group") || return

    local name group_id
    name=$(get_group_name "$file")
    group_id=$(get_group_id "$file")
    load_descriptions "$file"

    # Build list of NOT-installed packages
    local available=()
    local pkg
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        if ! is_package_installed "$pkg"; then
            available+=("$(format_package "$pkg")")
        fi
    done < <(get_group_packages "$file")

    if [ ${#available[@]} -eq 0 ]; then
        print_success "All packages in ${name} are already installed"
        return
    fi

    print_info "Select packages to install from ${name} (tab to select, enter to confirm):"
    local selected
    selected=$(printf '%s\n' "${available[@]}" | gum filter --no-limit \
        --header "Packages to install:" \
        --placeholder "Type to filter...") || {
        echo "Cancelled."
        return
    }

    if [ -z "$selected" ]; then
        print_info "No packages selected"
        return
    fi

    # Extract package names
    local to_install=()
    while IFS= read -r line; do
        to_install+=("$(extract_package_name "$line")")
    done <<< "$selected"

    echo ""
    print_info "Will install: ${to_install[*]}"
    if ! gum confirm "Proceed with installation?"; then
        echo "Cancelled."
        return
    fi

    install_packages "${to_install[@]}"

    # Check if all group packages are now installed
    local all_installed=true
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        if ! is_package_installed "$pkg"; then
            all_installed=false
            break
        fi
    done < <(get_group_packages "$file")

    # Offer to enable chezmoi flag if the whole group is now installed
    local flag flag_val
    flag=$(get_chezmoi_flag "$group_id")
    flag_val=$(get_chezmoi_flag_value "$flag")

    if [ "$all_installed" = true ] && [ "$flag_val" = "false" ]; then
        echo ""
        if gum confirm "All ${name} packages are installed. Enable ${flag} in chezmoi.toml?"; then
            update_chezmoi_flag "$flag" "true"
            if gum confirm "Apply dotfiles now?"; then
                chezmoi apply --force
                print_success "Dotfiles applied"
            fi
        fi
    fi

    # Offer to enable services
    local services
    services=$(parse_services "$file")
    if [ -n "$services" ]; then
        local stopped_services=()
        while IFS= read -r svc; do
            [ -z "$svc" ] && continue
            if ! systemctl is-enabled "$svc" &>/dev/null; then
                stopped_services+=("$svc")
            fi
        done <<< "$services"

        if [ ${#stopped_services[@]} -gt 0 ]; then
            echo ""
            print_info "Associated services not enabled: ${stopped_services[*]}"
            if gum confirm "Enable these services?"; then
                for svc in "${stopped_services[@]}"; do
                    enable_service "$svc"
                done
            fi
        fi
    fi
}

# ── Remove flow ──────────────────────────────────────────────────────────────

show_remove() {
    local file
    file=$(choose_group "Remove packages from group") || return

    local name group_id
    name=$(get_group_name "$file")
    group_id=$(get_group_id "$file")
    load_descriptions "$file"

    # Build list of installed packages
    local removable=()
    local pkg
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        if is_package_installed "$pkg"; then
            removable+=("$(format_package "$pkg")")
        fi
    done < <(get_group_packages "$file")

    if [ ${#removable[@]} -eq 0 ]; then
        print_info "No packages from ${name} are currently installed"
        return
    fi

    print_info "Select packages to remove from ${name} (tab to select, enter to confirm):"
    local selected
    selected=$(printf '%s\n' "${removable[@]}" | gum filter --no-limit \
        --header "Packages to remove:" \
        --placeholder "Type to filter...") || {
        echo "Cancelled."
        return
    }

    if [ -z "$selected" ]; then
        print_info "No packages selected"
        return
    fi

    # Extract package names
    local to_remove=()
    while IFS= read -r line; do
        to_remove+=("$(extract_package_name "$line")")
    done <<< "$selected"

    echo ""
    print_warning "Will remove: ${to_remove[*]}"
    if ! gum confirm "Proceed with removal?"; then
        echo "Cancelled."
        return
    fi

    remove_packages "${to_remove[@]}"

    # Check if any group packages remain installed
    local any_installed=false
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        if is_package_installed "$pkg"; then
            any_installed=true
            break
        fi
    done < <(get_group_packages "$file")

    # Offer to disable chezmoi flag if no group packages remain
    local flag flag_val
    flag=$(get_chezmoi_flag "$group_id")
    flag_val=$(get_chezmoi_flag_value "$flag")

    if [ "$any_installed" = false ] && [ "$flag_val" = "true" ]; then
        echo ""
        if gum confirm "No ${name} packages remain installed. Disable ${flag} in chezmoi.toml?"; then
            update_chezmoi_flag "$flag" "false"
            if gum confirm "Apply dotfiles now?"; then
                chezmoi apply --force
                print_success "Dotfiles applied"
            fi
        fi
    fi

    # Offer to disable services
    local services
    services=$(parse_services "$file")
    if [ -n "$services" ]; then
        local active_services=()
        while IFS= read -r svc; do
            [ -z "$svc" ] && continue
            if systemctl is-enabled "$svc" &>/dev/null; then
                active_services+=("$svc")
            fi
        done <<< "$services"

        if [ ${#active_services[@]} -gt 0 ] && [ "$any_installed" = false ]; then
            echo ""
            print_info "Associated services still enabled: ${active_services[*]}"
            if gum confirm "Disable these services?"; then
                for svc in "${active_services[@]}"; do
                    disable_service "$svc"
                done
            fi
        fi
    fi
}

# ── Main menu ────────────────────────────────────────────────────────────────

usage() {
    cat <<'EOF'
Usage: ./manage.sh packages [command]

Commands:
  browse      Browse groups and see installed status
  add         Add packages from a group
  remove      Remove packages from a group
  help        Show this help message

Run without arguments for an interactive menu.
EOF
}

main_menu() {
    if ! command_exists gum; then
        print_error "gum is not installed. Run './manage.sh setup' first."
        exit 1
    fi

    while true; do
        print_header "Package Manager"

        local choice
        choice=$(printf '%s\n' "Browse groups" "Add packages" "Remove packages" "Back" \
            | gum choose --cursor.foreground="212" --header "What would you like to do?") || break

        case "$choice" in
            "Browse groups")    show_browse ;;
            "Add packages")     show_add ;;
            "Remove packages")  show_remove ;;
            "Back")             break ;;
        esac
    done
}

# ── CLI dispatch ─────────────────────────────────────────────────────────────

case "${1:-}" in
    browse)             show_browse ;;
    add)                show_add ;;
    remove)             show_remove ;;
    help|--help|-h)     usage ;;
    *)                  main_menu ;;
esac
