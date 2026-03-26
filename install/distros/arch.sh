#!/bin/bash
# Arch Linux specific package management functions

# Source common functions (use local var to avoid overwriting parent's SCRIPT_DIR)
_DISTRO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DISTRO_DIR/../lib/common.sh"

# Run a pacman/paru command, converting "up to date" messages to info and
# suppressing boilerplate noise. Both stdout and stderr are captured and filtered.
_run_pkg_cmd() {
    local output_tmp
    output_tmp=$(mktemp)
    local rc=0
    "$@" &>"$output_tmp" || rc=$?
    while IFS= read -r line; do
        if [[ "$line" =~ ^warning:\ (.+)\ is\ up\ to\ date\ --\ skipping$ ]]; then
            print_info "Already installed: ${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^::\ (.+)\ is\ up\ to\ date\ --\ skipping$ ]]; then
            print_info "Already installed: ${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^\ *there\ is\ nothing\ to\ do\ *$ ]]; then
            :
        elif [[ "$line" =~ ^::\ (Resolving\ dependencies|Calculating\ (inner\ )?conflicts)\.\.\. ]]; then
            :
        else
            echo "$line"
        fi
    done < "$output_tmp"
    rm -f "$output_tmp"
    return $rc
}

# Check if paru is installed, install if not
ensure_paru() {
    if command_exists paru; then
        print_info "paru is already installed"
        return 0
    fi
    
    print_info "Installing paru (AUR helper)..."
    
    # Ensure base-devel and git are installed
    _run_pkg_cmd sudo pacman -S --needed --noconfirm git base-devel
    
    # Clone and build paru
    local temp_dir="/tmp/paru-build"
    rm -rf "$temp_dir"
    git clone https://aur.archlinux.org/paru.git "$temp_dir"
    
    (
        cd "$temp_dir" || exit 1
        makepkg -si --noconfirm
    )
    
    rm -rf "$temp_dir"
    
    if command_exists paru; then
        print_success "paru installed successfully"
        return 0
    else
        print_error "Failed to install paru"
        return 1
    fi
}

# Update the system
update_system() {
    print_info "Updating system..."
    sudo pacman -Syu --noconfirm
}

# Install packages using pacman
install_pacman_packages() {
    local packages=("$@")
    
    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi
    
    print_info "Installing ${#packages[@]} packages with pacman..."
    _run_pkg_cmd sudo pacman -S --needed --noconfirm "${packages[@]}"
}

# Install packages using paru (for AUR packages)
install_paru_packages() {
    local packages=("$@")
    
    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi
    
    ensure_paru
    
    print_info "Installing ${#packages[@]} packages with paru..."
    _run_pkg_cmd paru -S --needed --noconfirm "${packages[@]}"
}

# Install all packages (handles both official and AUR)
install_packages() {
    local packages=("$@")
    
    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi
    
    ensure_paru
    
    print_info "Installing ${#packages[@]} packages..."
    _run_pkg_cmd paru -S --needed --noconfirm "${packages[@]}"
}

# Remove packages
remove_packages() {
    local packages=("$@")

    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi

    print_info "Removing packages: ${packages[*]}"
    sudo pacman -Rns --noconfirm "${packages[@]}"
}

# Check if a package is installed
is_package_installed() {
    local package="$1"
    pacman -Qi "$package" &>/dev/null
}

# Install gum for interactive prompts
install_gum() {
    if command_exists gum; then
        print_info "gum is already installed"
        return 0
    fi
    
    print_info "Installing gum..."
    ensure_paru
    _run_pkg_cmd paru -S --needed --noconfirm gum
}

# Install chezmoi
install_chezmoi() {
    if command_exists chezmoi; then
        print_info "chezmoi is already installed"
        return 0
    fi
    
    print_info "Installing chezmoi..."
    ensure_paru
    _run_pkg_cmd paru -S --needed --noconfirm chezmoi
}

# Install yq for YAML parsing
install_yq() {
    if command_exists yq; then
        print_info "yq is already installed"
        return 0
    fi
    
    print_info "Installing yq..."
    _run_pkg_cmd sudo pacman -S --needed --noconfirm yq
}

# Install AppImage desktop integration
install_appimage_support() {
    if is_package_installed appimagelauncher; then
        print_info "AppImageLauncher is already installed"
        return 0
    fi

    print_info "Installing AppImageLauncher..."
    install_packages appimagelauncher
}
