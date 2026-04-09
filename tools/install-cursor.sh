#!/bin/bash
# Install Cursor editor on non-Arch Linux distros.
# Fetches the latest version from the Cursor API and installs via
# the native package format (RPM for Fedora, DEB for Debian/Ubuntu)
# or AppImage as a fallback.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_DIR/install/lib/common.sh"
source "$REPO_DIR/install/lib/detect.sh"

CURSOR_API="https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable"
USER_AGENT="Mozilla/5.0"

# Fetch download metadata from the Cursor API
fetch_download_info() {
    local json
    json=$(curl -sfSL -A "$USER_AGENT" "$CURSOR_API") || {
        print_error "Failed to fetch Cursor download info"
        return 1
    }
    echo "$json"
}

extract_url() {
    local json="$1" key="$2"
    printf '%s' "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)[sys.argv[1]])" "$key"
}

install_rpm() {
    local url="$1"
    print_info "Installing Cursor via RPM..."
    sudo dnf install -y "$url"
}

install_deb() {
    local url="$1"
    local tmp
    tmp=$(mktemp /tmp/cursor-XXXXX.deb)
    trap "rm -f '$tmp'" EXIT
    print_info "Downloading Cursor .deb..."
    curl -fSL -A "$USER_AGENT" -o "$tmp" "$url"
    print_info "Installing Cursor via dpkg..."
    # dpkg may fail on missing deps; apt-get -f resolves them
    sudo dpkg -i "$tmp" || sudo apt-get install -f -y
}

install_appimage() {
    local url="$1"
    local tmp
    tmp=$(mktemp /tmp/cursor-XXXXX.AppImage)
    trap "rm -f '$tmp'" EXIT
    print_info "Downloading Cursor AppImage..."
    curl -fSL -A "$USER_AGENT" -o "$tmp" "$url"
    chmod +x "$tmp"
    "$SCRIPT_DIR/manage-external-apps.sh" import-appimage "$tmp" --name Cursor
}

main() {
    local json
    json=$(fetch_download_info) || exit 1

    local distro
    distro=$(detect_distro)
    local family
    family=$(get_distro_family "$distro")

    case "$family" in
        fedora)
            install_rpm "$(extract_url "$json" rpmUrl)"
            ;;
        debian)
            install_deb "$(extract_url "$json" debUrl)"
            ;;
        *)
            install_appimage "$(extract_url "$json" downloadUrl)"
            ;;
    esac

    print_success "Cursor installed successfully"
}

main "$@"
