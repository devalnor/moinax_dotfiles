#!/bin/bash
# Distro detection functions

# Detect the current Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    elif [ -f /etc/fedora-release ]; then
        echo "fedora"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Get the pretty name of the distro
get_distro_name() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$PRETTY_NAME"
    else
        echo "Unknown Linux Distribution"
    fi
}

# Check if distro is supported (only tested distros are listed here)
# Derivatives like manjaro, endeavouros, rhel, centos, etc. are mapped in
# get_distro_family() on a best-effort basis but are NOT officially supported.
is_supported_distro() {
    local distro="$1"
    case "$distro" in
        arch|\
        fedora|\
        ubuntu|debian|linuxmint|pop|elementary|neon|zorin|kali)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Get the distro family (maps individual distros to their package manager family)
get_distro_family() {
    local distro="$1"
    case "$distro" in
        ubuntu|debian|linuxmint|pop|elementary|neon|zorin|kali) echo "debian" ;;
        arch|manjaro|endeavouros|garuda) echo "arch" ;;
        fedora|rhel|centos|rocky|alma) echo "fedora" ;;
        *) echo "unknown" ;;
    esac
}

# Get list of supported (tested) distros
# Note: derivatives (manjaro, endeavouros, garuda, rhel, centos, rocky, alma)
# are mapped in get_distro_family() on a best-effort basis but are not tested.
get_supported_distros() {
    echo "arch fedora ubuntu debian linuxmint pop elementary neon zorin kali"
}

# Check if the system has an NVIDIA GPU
has_nvidia_gpu() {
    command -v lspci &>/dev/null || return 1
    lspci 2>/dev/null | grep -qi 'nvidia' && return 0
    return 1
}

# Check if NVIDIA suspend/resume systemd services are installed (i.e. drivers present)
has_nvidia_services() {
    systemctl list-unit-files nvidia-suspend.service 2>/dev/null | grep -q nvidia-suspend
}

# Get the installed NVIDIA driver major version number (e.g. "595").
# Prints the major version to stdout and returns 0, or returns 1 if not detectable.
get_nvidia_driver_version() {
    local version=""

    # Method 1: nvidia-smi (most reliable, works across all distros)
    if command -v nvidia-smi &>/dev/null; then
        version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    fi

    # Method 2: modinfo (works even without nvidia-smi)
    if [ -z "$version" ] && command -v modinfo &>/dev/null; then
        version=$(modinfo -F version nvidia 2>/dev/null | head -1)
    fi

    # Method 3: /proc/driver/nvidia/version (works if driver is loaded)
    if [ -z "$version" ] && [ -f /proc/driver/nvidia/version ]; then
        version=$(grep -oP 'Kernel Module\s+\K[0-9]+\.[0-9.]+' /proc/driver/nvidia/version 2>/dev/null | head -1)
    fi

    # Method 4: package manager query (works after install, before reboot)
    if [ -z "$version" ] && command -v rpm &>/dev/null; then
        version=$(rpm -q --qf '%{VERSION}\n' akmod-nvidia 2>/dev/null | grep -v 'not installed' | head -1)
    fi
    if [ -z "$version" ] && command -v dpkg-query &>/dev/null; then
        version=$(dpkg-query -W -f='${Version}\n' nvidia-driver 2>/dev/null | grep -oP '^[0-9]+\.[0-9.]+' | head -1)
    fi
    if [ -z "$version" ] && command -v pacman &>/dev/null; then
        version=$(pacman -Q nvidia-utils 2>/dev/null | awk '{print $2}' | grep -oP '^[0-9]+\.[0-9.]+' | head -1)
    fi

    if [ -z "$version" ]; then
        return 1
    fi

    # Extract major version number (e.g. "595.58.03" -> "595")
    echo "${version%%.*}"
}

# Check if the system has a fingerprint reader.
# Pre-install detection: scan lsusb for "fingerprint"/"biometric" strings or for the
# vendor IDs of dedicated fingerprint chip makers — Goodix (27c6), Validity (138a),
# AuthenTec (08ff), Upek (147e).
has_fingerprint_reader() {
    command -v lsusb &>/dev/null || return 1
    lsusb 2>/dev/null | grep -qiE 'fingerprint|biometric|ID (27c6|138a|08ff|147e):'
}

# Check if the NVIDIA driver supports kernel suspend notifiers (driver 595+).
# See the version-dependent suspend comment in setup_nvidia() (installer.sh) for implications.
# Returns 0 if supported, 1 otherwise (including when version is undetectable — safe fallback).
nvidia_has_kernel_suspend_notifiers() {
    local major
    major=$(get_nvidia_driver_version) || return 1
    [ "$major" -ge 595 ] 2>/dev/null
}
