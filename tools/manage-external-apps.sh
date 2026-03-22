#!/bin/bash
# External Apps Manager
set -e
set -o pipefail

APPIMAGE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/AppImages"
APP_DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
APP_ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/external-apps"
DISTROBOX_STATE_DIR="$STATE_DIR/distrobox"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat <<'EOF'
Usage: ./manage.sh apps [command] [options]

Commands:
  import-appimage <file> [--name NAME]
      Copy an AppImage to a stable location and create a desktop launcher.

  install-distrobox --container NAME --package FILE [--app DESKTOP_ID] [--name APP_NAME]
      Install a local package inside a Distrobox container, export it to the host launcher,
      and save metadata for future updates.

  update-distrobox --name APP_NAME --package FILE
      Update a previously managed Distrobox app using saved metadata.

  list
      List managed Distrobox app metadata.

Run without arguments for an interactive wizard.
EOF
}

ensure_dirs() {
    mkdir -p "$APPIMAGE_DIR" "$APP_DESKTOP_DIR" "$APP_ICON_DIR" "$DISTROBOX_STATE_DIR"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

require_file() {
    if [ ! -f "$1" ]; then
        print_error "File not found: $1"
        exit 1
    fi
}

refresh_desktop_db() {
    if command_exists update-desktop-database; then
        update-desktop-database "$APP_DESKTOP_DIR" >/dev/null 2>&1 || true
    fi
}

default_picker_root() {
    if [ -d "$HOME/Downloads" ]; then
        printf '%s\n' "$HOME/Downloads"
    else
        printf '%s\n' "$HOME"
    fi
}

prompt_with_default() {
    local header="$1"
    local default_value="$2"
    local placeholder="${3:-}"
    local required="${4:-true}"

    while true; do
        local value=""

        if command_exists gum; then
            value=$(gum input \
                --header "$header" \
                --value "$default_value" \
                --placeholder "$placeholder") || return 1
        else
            printf '%s' "$header"
            if [ -n "$default_value" ]; then
                printf ' [%s]' "$default_value"
            fi
            printf ': '
            IFS= read -r value || return 1
        fi

        value=$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        if [ -z "$value" ] && [ -n "$default_value" ]; then
            value="$default_value"
        fi

        if [ -n "$value" ] || [ "$required" = "false" ]; then
            printf '%s\n' "$value"
            return 0
        fi

        echo -e "${YELLOW}[WARNING]${NC} A value is required." >&2
    done
}

pick_file_from_downloads() {
    local header="$1"
    local mode="$2"
    local root=""
    root=$(default_picker_root)

    while true; do
        local selection=""

        if command_exists gum; then
            selection=$(gum file "$root" --file --header "$header") || return 1
        else
            selection=$(prompt_with_default "$header" "$root/" "Enter a file path" true) || return 1
        fi

        selection=$(realpath "$selection" 2>/dev/null || true)
        if [ -z "$selection" ] || [ ! -f "$selection" ]; then
            echo -e "${YELLOW}[WARNING]${NC} Please select an existing file." >&2
            continue
        fi

        case "$mode" in
            appimage)
                if [[ "$selection" != *.AppImage ]]; then
                    echo -e "${YELLOW}[WARNING]${NC} Please select a .AppImage file." >&2
                    continue
                fi
                ;;
            package)
                if ! [[ "$selection" == *.deb || "$selection" == *.rpm || "$selection" == *.pkg.tar || "$selection" == *.pkg.tar.* ]]; then
                    echo -e "${YELLOW}[WARNING]${NC} Please select a .deb, .rpm, or .pkg.tar.* file." >&2
                    continue
                fi
                ;;
        esac

        printf '%s\n' "$selection"
        return 0
    done
}

confirm_summary() {
    local title="$1"
    shift
    local lines=("$@")

    if command_exists gum; then
        gum style \
            --border rounded \
            --border-foreground 212 \
            --padding "1 2" \
            --margin "1" \
            "$(gum style --foreground 212 --bold "$title")" \
            "" \
            "${lines[@]}" >/dev/tty
        gum confirm --affirmative "Proceed" --negative "Cancel" "$title?"
    else
        echo ""
        echo "$title"
        echo "========================="
        printf '%s\n' "${lines[@]}"
        echo ""
        read -r -p "Proceed? [y/N]: " answer
        [[ "$answer" =~ ^[Yy]$ ]]
    fi
}

extract_appimage_metadata() {
    local appimage_path="$1"
    local extract_dir="$2"
    APPIMAGE_META_NAME=""
    APPIMAGE_META_ICON=""

    local work_dir=""
    work_dir=$(mktemp -d)

    if ! (cd "$work_dir" && "$appimage_path" --appimage-extract >/dev/null 2>&1); then
        rm -rf "$work_dir"
        return 0
    fi

    local squashfs_dir="$work_dir/squashfs-root"
    if [ ! -d "$squashfs_dir" ]; then
        rm -rf "$work_dir"
        return 0
    fi

    rm -rf "$extract_dir"
    mv "$squashfs_dir" "$extract_dir"
    rm -rf "$work_dir"

    local desktop_file=""
    desktop_file=$(find "$extract_dir" -maxdepth 2 -type f -name '*.desktop' | head -1 || true)
    if [ -n "$desktop_file" ]; then
        APPIMAGE_META_NAME=$(sed -n 's/^Name=//p' "$desktop_file" | head -1)
        local icon_name=""
        icon_name=$(sed -n 's/^Icon=//p' "$desktop_file" | head -1)
        if [ -n "$icon_name" ]; then
            APPIMAGE_META_ICON=$(find "$extract_dir" -type f \( -name "${icon_name}.png" -o -name "${icon_name}.svg" -o -name "${icon_name}.xpm" -o -name "${icon_name}" \) | head -1 || true)
        fi
    fi

    if [ -z "$APPIMAGE_META_ICON" ]; then
        APPIMAGE_META_ICON=$(find "$extract_dir" -type f \( -name '*.png' -o -name '*.svg' -o -name '*.xpm' \) | head -1 || true)
    fi
}

execute_import_appimage() {
    local source_path="$1"
    local app_name="$2"

    ensure_dirs
    require_file "$source_path"

    local extract_dir=""
    extract_dir=$(mktemp -d)
    trap 'rm -rf "$extract_dir"' RETURN

    extract_appimage_metadata "$source_path" "$extract_dir"

    local slug=""
    slug=$(slugify "$app_name")
    local dest_appimage="$APPIMAGE_DIR/${slug}.AppImage"
    install -Dm755 "$source_path" "$dest_appimage"

    local icon_path=""
    if [ -n "$APPIMAGE_META_ICON" ] && [ -f "$APPIMAGE_META_ICON" ]; then
        local icon_ext="${APPIMAGE_META_ICON##*.}"
        icon_path="$APP_ICON_DIR/${slug}.${icon_ext}"
        install -Dm644 "$APPIMAGE_META_ICON" "$icon_path"
    fi

    local desktop_file="$APP_DESKTOP_DIR/${slug}.desktop"
    cat > "$desktop_file" <<EOF
[Desktop Entry]
Name=$app_name
Exec=$dest_appimage
Type=Application
Categories=Utility;
Terminal=false
StartupNotify=true
EOF

    if [ -n "$icon_path" ]; then
        printf 'Icon=%s\n' "$icon_path" >> "$desktop_file"
    fi

    refresh_desktop_db
    print_success "Imported AppImage into the launcher"
    echo "  AppImage: $dest_appimage"
    echo "  Desktop entry: $desktop_file"
    if [ -n "$icon_path" ]; then
        echo "  Icon: $icon_path"
    fi
}

do_import_appimage() {
    local source_path=""
    local app_name=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --name)
                app_name="$2"
                shift 2
                ;;
            --help|-h)
                usage
                return 0
                ;;
            *)
                if [ -z "$source_path" ]; then
                    source_path="$1"
                else
                    print_error "Unexpected argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [ -z "$source_path" ]; then
        print_error "Missing AppImage file path"
        usage
        exit 1
    fi

    source_path=$(realpath "$source_path")
    require_file "$source_path"

    if [ -z "$app_name" ]; then
        local extract_dir=""
        extract_dir=$(mktemp -d)
        trap 'rm -rf "$extract_dir"' RETURN
        extract_appimage_metadata "$source_path" "$extract_dir"
        if [ -n "$APPIMAGE_META_NAME" ]; then
            app_name="$APPIMAGE_META_NAME"
        else
            app_name="$(basename "$source_path" .AppImage)"
        fi
    fi

    execute_import_appimage "$source_path" "$app_name"
}

interactive_import_appimage() {
    local source_path=""
    source_path=$(pick_file_from_downloads "Pick an AppImage from Downloads" appimage) || return 0

    local extract_dir=""
    extract_dir=$(mktemp -d)
    trap 'rm -rf "$extract_dir"' RETURN
    extract_appimage_metadata "$source_path" "$extract_dir"

    local detected_name=""
    if [ -n "$APPIMAGE_META_NAME" ]; then
        detected_name="$APPIMAGE_META_NAME"
    else
        detected_name="$(basename "$source_path" .AppImage)"
    fi

    local app_name=""
    app_name=$(prompt_with_default "App name" "$detected_name" "Launcher name") || return 0

    local slug=""
    slug=$(slugify "$app_name")
    local dest_appimage="$APPIMAGE_DIR/${slug}.AppImage"
    local desktop_file="$APP_DESKTOP_DIR/${slug}.desktop"
    local icon_status="No icon detected"
    if [ -n "$APPIMAGE_META_ICON" ] && [ -f "$APPIMAGE_META_ICON" ]; then
        icon_status="Icon detected: $(basename "$APPIMAGE_META_ICON")"
    fi

    if ! confirm_summary "Import AppImage" \
        "  Source: $source_path" \
        "  Name: $app_name" \
        "  Destination AppImage: $dest_appimage" \
        "  Desktop entry: $desktop_file" \
        "  $icon_status"; then
        print_info "Cancelled."
        return 0
    fi

    execute_import_appimage "$source_path" "$app_name"
}

require_distrobox() {
    if ! command_exists distrobox-enter; then
        print_error "distrobox-enter not found. Is Distrobox installed?"
        return 1
    fi
}

package_type_for_file() {
    case "$1" in
        *.deb) echo "deb" ;;
        *.rpm) echo "rpm" ;;
        *.pkg.tar|*.pkg.tar.*) echo "arch" ;;
        *)
            print_error "Unsupported package format: $1"
            print_info "Supported: .deb, .rpm, .pkg.tar.*"
            return 1
            ;;
    esac
}

run_in_distrobox() {
    local container="$1"
    shift
    distrobox-enter --name "$container" --no-tty -- "$@"
}

resolve_container_package_path_snippet() {
    cat <<'EOF'
host_pkg="$1"
if [ -f "$host_pkg" ]; then
    pkg_path="$host_pkg"
elif [ -f "/run/host$host_pkg" ]; then
    pkg_path="/run/host$host_pkg"
else
    echo "ERROR: package file not visible inside container: $host_pkg" >&2
    exit 12
fi
EOF
}

list_distrobox_containers() {
    if command_exists distrobox; then
        distrobox list --no-color 2>/dev/null \
            | tail -n +2 \
            | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); if ($1 != "") print $1}' \
            | sort -u
        return 0
    fi

    if command_exists distrobox-list; then
        distrobox-list --no-color 2>/dev/null \
            | tail -n +2 \
            | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); if ($1 != "") print $1}' \
            | sort -u
        return 0
    fi

    return 1
}

pick_existing_distrobox_container() {
    local containers=()
    while IFS= read -r line; do
        [ -n "$line" ] && containers+=("$line")
    done < <(list_distrobox_containers || true)

    if [ ${#containers[@]} -eq 0 ]; then
        prompt_with_default "Distrobox container name" "" "Enter a container name" true
        return $?
    fi

    containers+=("Enter container name manually")
    local choice=""

    if command_exists gum; then
        choice=$(printf '%s\n' "${containers[@]}" | gum choose --header "Select a Distrobox container") || return 1
    else
        printf '%s\n' "${containers[@]}"
        choice=$(prompt_with_default "Distrobox container name" "${containers[0]}" "" true) || return 1
    fi

    if [ "$choice" = "Enter container name manually" ]; then
        prompt_with_default "Distrobox container name" "" "Enter a container name" true
        return $?
    fi

    printf '%s\n' "$choice"
}

list_desktop_ids_in_container() {
    local container="$1"
    run_in_distrobox "$container" sh -lc '
        find /usr/share/applications "$HOME/.local/share/applications" \
            -maxdepth 1 -type f -name "*.desktop" 2>/dev/null \
            | xargs -r -n1 basename | sort -u
    '
}

install_package_in_distrobox() {
    local container="$1"
    local package_path="$2"
    local package_type="$3"
    local script=""

    case "$package_type" in
        deb)
            script="$(resolve_container_package_path_snippet)
if command -v apt >/dev/null 2>&1; then
    sudo apt install -y \"\$pkg_path\"
elif command -v dpkg >/dev/null 2>&1; then
    sudo dpkg -i \"\$pkg_path\" || { sudo apt-get install -f -y && sudo dpkg -i \"\$pkg_path\"; }
else
    echo \"ERROR: no Debian package manager found in container\" >&2
    exit 13
fi"
            ;;
        rpm)
            script="$(resolve_container_package_path_snippet)
if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y \"\$pkg_path\"
elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y \"\$pkg_path\"
elif command -v zypper >/dev/null 2>&1; then
    sudo zypper --non-interactive install \"\$pkg_path\"
else
    echo \"ERROR: no RPM package manager found in container\" >&2
    exit 13
fi"
            ;;
        arch)
            script="$(resolve_container_package_path_snippet)
if command -v pacman >/dev/null 2>&1; then
    sudo pacman -U --noconfirm \"\$pkg_path\"
else
    echo \"ERROR: no pacman found in container\" >&2
    exit 13
fi"
            ;;
    esac

    run_in_distrobox "$container" sh -lc "$script" sh "$package_path"
}

select_exported_app_id() {
    local before_file="$1"
    local after_file="$2"
    local requested="$3"

    if [ -n "$requested" ]; then
        printf '%s\n' "$requested"
        return 0
    fi

    local candidates=""
    candidates=$(comm -13 "$before_file" "$after_file" || true)
    local count=""
    count=$(printf '%s\n' "$candidates" | sed '/^$/d' | wc -l | tr -d ' ')

    if [ "$count" -eq 1 ]; then
        printf '%s\n' "$candidates" | sed '/^$/d'
        return 0
    fi

    if [ "$count" -eq 0 ]; then
        print_error "Could not detect a new desktop entry automatically"
    else
        print_error "Multiple desktop entries were added; please specify one with --app"
        printf '%s\n' "$candidates" | sed '/^$/d' | sed 's/^/  - /'
    fi
    return 1
}

pick_exported_app_id_interactive() {
    local before_file="$1"
    local after_file="$2"
    local candidates=()

    while IFS= read -r line; do
        [ -n "$line" ] && candidates+=("$line")
    done < <(comm -13 "$before_file" "$after_file" 2>/dev/null || true)

    if [ ${#candidates[@]} -eq 1 ]; then
        printf '%s\n' "${candidates[0]}"
        return 0
    fi

    if [ ${#candidates[@]} -gt 1 ]; then
        if command_exists gum; then
            printf '%s\n' "${candidates[@]}" | gum choose --header "Pick the desktop entry to export"
        else
            prompt_with_default "Desktop entry id" "${candidates[0]}" "example.desktop" true
        fi
        return $?
    fi

    prompt_with_default "Desktop entry id" "" "example.desktop" true
}

export_distrobox_app() {
    local container="$1"
    local app_id="$2"
    run_in_distrobox "$container" distrobox-export --app "$app_id"
}

metadata_file_for_name() {
    printf '%s/%s.env\n' "$DISTROBOX_STATE_DIR" "$(slugify "$1")"
}

save_distrobox_metadata() {
    local app_name="$1"
    local container="$2"
    local package_type="$3"
    local app_id="$4"
    local metadata_file=""
    metadata_file=$(metadata_file_for_name "$app_name")

    {
        printf 'APP_NAME=%q\n' "$app_name"
        printf 'CONTAINER=%q\n' "$container"
        printf 'PACKAGE_TYPE=%q\n' "$package_type"
        printf 'APP_ID=%q\n' "$app_id"
    } > "$metadata_file"
}

load_distrobox_metadata() {
    local app_name="$1"
    local metadata_file=""
    metadata_file=$(metadata_file_for_name "$app_name")
    if [ ! -f "$metadata_file" ]; then
        print_error "No saved metadata for app: $app_name"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$metadata_file"
}

list_saved_metadata_files() {
    ensure_dirs
    shopt -s nullglob
    local files=("$DISTROBOX_STATE_DIR"/*.env)
    shopt -u nullglob
    printf '%s\n' "${files[@]}"
}

pick_saved_distrobox_app() {
    local files=()
    while IFS= read -r file; do
        [ -n "$file" ] && files+=("$file")
    done < <(list_saved_metadata_files)

    if [ ${#files[@]} -eq 0 ]; then
        return 1
    fi

    local options=()
    local file
    for file in "${files[@]}"; do
        # shellcheck disable=SC1090
        source "$file"
        options+=("$APP_NAME | container=$CONTAINER | app=$APP_ID | type=$PACKAGE_TYPE")
    done

    local choice=""
    if command_exists gum; then
        choice=$(printf '%s\n' "${options[@]}" | gum choose --header "Pick a managed Distrobox app") || return 1
    else
        choice=$(prompt_with_default "Managed app" "${options[0]}" "" true) || return 1
    fi

    local index=0
    for option in "${options[@]}"; do
        if [ "$option" = "$choice" ]; then
            printf '%s\n' "${files[$index]}"
            return 0
        fi
        index=$((index + 1))
    done

    return 1
}

execute_install_distrobox() {
    local container="$1"
    local package_path="$2"
    local app_name="$3"
    local requested_app_id="$4"

    ensure_dirs
    require_distrobox || return 1
    require_file "$package_path"

    local package_type=""
    package_type=$(package_type_for_file "$package_path") || return 1

    local before_file=""
    local after_file=""
    before_file=$(mktemp)
    after_file=$(mktemp)
    trap 'rm -f "$before_file" "$after_file"' RETURN

    print_info "Collecting desktop entries from container '$container'..."
    list_desktop_ids_in_container "$container" > "$before_file"

    print_info "Installing package in container '$container'..."
    install_package_in_distrobox "$container" "$package_path" "$package_type"

    print_info "Collecting updated desktop entries..."
    list_desktop_ids_in_container "$container" > "$after_file"

    local app_id=""
    app_id=$(select_exported_app_id "$before_file" "$after_file" "$requested_app_id") || return 1

    if [ -z "$app_name" ]; then
        app_name="${app_id%.desktop}"
    fi

    print_info "Exporting '$app_id' to the host launcher..."
    export_distrobox_app "$container" "$app_id"
    save_distrobox_metadata "$app_name" "$container" "$package_type" "$app_id"

    print_success "Installed and exported Distrobox app"
    echo "  App: $app_name"
    echo "  Container: $container"
    echo "  Desktop entry: $app_id"
}

do_install_distrobox() {
    local container=""
    local package_path=""
    local app_id=""
    local app_name=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --container)
                container="$2"
                shift 2
                ;;
            --package)
                package_path="$2"
                shift 2
                ;;
            --app)
                app_id="$2"
                shift 2
                ;;
            --name)
                app_name="$2"
                shift 2
                ;;
            --help|-h)
                usage
                return 0
                ;;
            *)
                print_error "Unexpected argument: $1"
                exit 1
                ;;
        esac
    done

    if [ -z "$container" ] || [ -z "$package_path" ]; then
        print_error "install-distrobox requires --container and --package"
        usage
        exit 1
    fi

    package_path=$(realpath "$package_path")
    execute_install_distrobox "$container" "$package_path" "$app_name" "$app_id"
}

interactive_install_distrobox() {
    require_distrobox || return 0

    local container=""
    container=$(pick_existing_distrobox_container) || return 0

    local package_path=""
    package_path=$(pick_file_from_downloads "Pick a package from Downloads" package) || return 0

    local package_type=""
    package_type=$(package_type_for_file "$package_path") || return 0

    local suggested_name=""
    suggested_name="$(basename "$package_path")"
    suggested_name="${suggested_name%.deb}"
    suggested_name="${suggested_name%.rpm}"
    suggested_name="${suggested_name%.pkg.tar}"
    suggested_name="${suggested_name%.pkg.tar.zst}"
    suggested_name="${suggested_name%.pkg.tar.xz}"
    suggested_name="${suggested_name%.pkg.tar.gz}"

    local app_name=""
    app_name=$(prompt_with_default "App name" "$suggested_name" "Saved app name" true) || return 0

    if ! confirm_summary "Install package in Distrobox" \
        "  Container: $container" \
        "  Package: $package_path" \
        "  Type: $package_type" \
        "  App name: $app_name" \
        "  Desktop entry: auto-detect after install"; then
        print_info "Cancelled."
        return 0
    fi

    ensure_dirs
    local before_file=""
    local after_file=""
    before_file=$(mktemp)
    after_file=$(mktemp)
    trap 'rm -f "$before_file" "$after_file"' RETURN

    print_info "Collecting desktop entries from container '$container'..."
    list_desktop_ids_in_container "$container" > "$before_file"

    print_info "Installing package in container '$container'..."
    install_package_in_distrobox "$container" "$package_path" "$package_type" || {
        print_error "Package installation failed."
        return 1
    }

    print_info "Collecting updated desktop entries..."
    list_desktop_ids_in_container "$container" > "$after_file"

    local app_id=""
    app_id=$(pick_exported_app_id_interactive "$before_file" "$after_file") || {
        print_info "Cancelled."
        return 0
    }

    print_info "Exporting '$app_id' to the host launcher..."
    export_distrobox_app "$container" "$app_id" || {
        print_error "Export failed."
        return 1
    }

    save_distrobox_metadata "$app_name" "$container" "$package_type" "$app_id"
    print_success "Installed and exported Distrobox app"
    echo "  App: $app_name"
    echo "  Container: $container"
    echo "  Desktop entry: $app_id"
}

execute_update_distrobox() {
    local app_name="$1"
    local package_path="$2"

    ensure_dirs
    require_distrobox || return 1
    require_file "$package_path"
    load_distrobox_metadata "$app_name" || return 1

    local new_package_type=""
    new_package_type=$(package_type_for_file "$package_path") || return 1
    if [ "$new_package_type" != "$PACKAGE_TYPE" ]; then
        print_warning "Saved package type is '$PACKAGE_TYPE' but new file looks like '$new_package_type'"
    fi

    print_info "Updating '$APP_NAME' in container '$CONTAINER'..."
    install_package_in_distrobox "$CONTAINER" "$package_path" "$new_package_type"

    print_info "Refreshing exported desktop entry '$APP_ID'..."
    export_distrobox_app "$CONTAINER" "$APP_ID"
    save_distrobox_metadata "$APP_NAME" "$CONTAINER" "$new_package_type" "$APP_ID"

    print_success "Updated Distrobox app"
    echo "  App: $APP_NAME"
    echo "  Container: $CONTAINER"
    echo "  Desktop entry: $APP_ID"
}

do_update_distrobox() {
    local app_name=""
    local package_path=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --name)
                app_name="$2"
                shift 2
                ;;
            --package)
                package_path="$2"
                shift 2
                ;;
            --help|-h)
                usage
                return 0
                ;;
            *)
                print_error "Unexpected argument: $1"
                exit 1
                ;;
        esac
    done

    if [ -z "$app_name" ] || [ -z "$package_path" ]; then
        print_error "update-distrobox requires --name and --package"
        usage
        exit 1
    fi

    package_path=$(realpath "$package_path")
    execute_update_distrobox "$app_name" "$package_path"
}

interactive_update_distrobox() {
    require_distrobox || return 0

    local metadata_file=""
    metadata_file=$(pick_saved_distrobox_app) || {
        print_info "No managed Distrobox apps found."
        return 0
    }

    # shellcheck disable=SC1090
    source "$metadata_file"

    local package_path=""
    package_path=$(pick_file_from_downloads "Pick the updated package from Downloads" package) || return 0

    local new_package_type=""
    new_package_type=$(package_type_for_file "$package_path") || return 0
    local type_warning=""
    if [ "$new_package_type" != "$PACKAGE_TYPE" ]; then
        type_warning="  Warning: saved type $PACKAGE_TYPE, new file looks like $new_package_type"
    fi

    if ! confirm_summary "Update Distrobox app" \
        "  App: $APP_NAME" \
        "  Container: $CONTAINER" \
        "  Desktop entry: $APP_ID" \
        "  Saved type: $PACKAGE_TYPE" \
        "  New package: $package_path" \
        "  New type: $new_package_type" \
        "${type_warning:-  Package type matches saved metadata}"; then
        print_info "Cancelled."
        return 0
    fi

    print_info "Updating '$APP_NAME' in container '$CONTAINER'..."
    install_package_in_distrobox "$CONTAINER" "$package_path" "$new_package_type" || {
        print_error "Package update failed."
        return 1
    }

    print_info "Refreshing exported desktop entry '$APP_ID'..."
    export_distrobox_app "$CONTAINER" "$APP_ID" || {
        print_error "Export refresh failed."
        return 1
    }

    save_distrobox_metadata "$APP_NAME" "$CONTAINER" "$new_package_type" "$APP_ID"
    print_success "Updated Distrobox app"
    echo "  App: $APP_NAME"
    echo "  Container: $CONTAINER"
    echo "  Desktop entry: $APP_ID"
}

do_list() {
    ensure_dirs
    shopt -s nullglob
    local files=("$DISTROBOX_STATE_DIR"/*.env)
    shopt -u nullglob

    if [ ${#files[@]} -eq 0 ]; then
        print_info "No managed Distrobox apps found"
        return 0
    fi

    local file
    for file in "${files[@]}"; do
        # shellcheck disable=SC1090
        source "$file"
        echo "$APP_NAME | container=$CONTAINER | app=$APP_ID | type=$PACKAGE_TYPE"
    done
}

main_menu() {
    while true; do
        local action=""

        if command_exists gum; then
            action=$(gum choose \
                "Import AppImage" \
                "Install package in Distrobox" \
                "Update Distrobox app" \
                "List managed Distrobox apps" \
                "Cancel") || action="Cancel"
        else
            echo "1) Import AppImage"
            echo "2) Install package in Distrobox"
            echo "3) Update Distrobox app"
            echo "4) List managed Distrobox apps"
            echo "5) Cancel"
            read -r -p "Choose an option [1-5]: " choice
            case "$choice" in
                1) action="Import AppImage" ;;
                2) action="Install package in Distrobox" ;;
                3) action="Update Distrobox app" ;;
                4) action="List managed Distrobox apps" ;;
                *) action="Cancel" ;;
            esac
        fi

        case "$action" in
            "Import AppImage")
                interactive_import_appimage || true
                ;;
            "Install package in Distrobox")
                interactive_install_distrobox || true
                ;;
            "Update Distrobox app")
                interactive_update_distrobox || true
                ;;
            "List managed Distrobox apps")
                do_list || true
                ;;
            *)
                print_info "Cancelled."
                return 0
                ;;
        esac
    done
}

case "${1:-}" in
    import-appimage)
        shift
        do_import_appimage "$@"
        ;;
    install-distrobox)
        shift
        do_install_distrobox "$@"
        ;;
    update-distrobox)
        shift
        do_update_distrobox "$@"
        ;;
    list)
        do_list
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        main_menu
        ;;
esac
