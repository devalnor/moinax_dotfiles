#!/usr/bin/env bash
# setup-sunshine.sh - Sunshine game streaming server setup
# Works on Arch Linux (via AUR/paru) and Fedora (via official RPM)
# Idempotent: safe to re-run

set -euo pipefail

log()  { printf "\033[1;34m[sunshine]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[sunshine]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[sunshine]\033[0m %s\n" "$*" >&2; exit 1; }

# ---------- detect distro ----------
if [ -r /etc/os-release ]; then
  . /etc/os-release
  DISTRO="${ID:-unknown}"
else
  die "Cannot detect distro (no /etc/os-release)"
fi
log "Detected: $DISTRO"

# ---------- install sunshine ----------
install_arch() {
  if pacman -Q sunshine &>/dev/null || pacman -Q sunshine-bin &>/dev/null; then
    log "Sunshine already installed (pacman)"
    return
  fi
  command -v paru >/dev/null || die "paru not found - install AUR helper first"
  log "Installing sunshine via paru (AUR build, 5-10 min)..."
  paru -S --needed --noconfirm sunshine
}

install_fedora() {
  if rpm -q sunshine &>/dev/null; then
    log "Sunshine already installed (rpm)"
    return
  fi
  log "Fetching latest Sunshine RPM URL from GitHub API..."
  local FEDORA_VER
  FEDORA_VER="$(rpm -E %fedora)"
  local TMP_JSON
  TMP_JSON="$(mktemp)"
  trap 'rm -f "$TMP_JSON"' RETURN
  curl -fsSL https://api.github.com/repos/LizardByte/Sunshine/releases/latest -o "$TMP_JSON"
  local URL
  URL="$(grep -oE -m1 "https://[^\"]+/Sunshine-[^\"]+-1\.fc${FEDORA_VER}\.x86_64\.rpm" "$TMP_JSON" || true)"
  [ -n "$URL" ] || die "No matching Fedora ${FEDORA_VER} RPM in latest release"
  log "Installing: $URL"
  sudo dnf install -y "$URL"
}

case "$DISTRO" in
  arch)            install_arch ;;
  fedora)          install_fedora ;;
  ubuntu|debian)   die "Debian/Ubuntu not implemented (use deb from LizardByte/Sunshine releases)" ;;
  *)               die "Unsupported distro: $DISTRO" ;;
esac

# ---------- uinput setup ----------
log "Configuring uinput (udev rule + module autoload)..."
UDEV_RULE=/etc/udev/rules.d/85-sunshine-uinput.rules
if ! [ -f "$UDEV_RULE" ]; then
  echo 'KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"' \
    | sudo tee "$UDEV_RULE" >/dev/null
  log "Udev rule installed at $UDEV_RULE"
fi

MODULES_CONF=/etc/modules-load.d/uinput.conf
if ! [ -f "$MODULES_CONF" ]; then
  echo "uinput" | sudo tee "$MODULES_CONF" >/dev/null
  log "Module autoload at $MODULES_CONF"
fi

if ! lsmod | grep -q '^uinput'; then
  sudo modprobe uinput
  log "uinput module loaded"
fi

sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=uinput || true

# ---------- user in input group ----------
if ! id -nG "$USER" | grep -qw input; then
  log "Adding $USER to input group (relog needed for effect)"
  sudo usermod -aG input "$USER"
else
  log "$USER already in input group"
fi

# ---------- sunshine config (CSRF + KMS capture for virtio-gpu) ----------
SUNSHINE_DIR="$HOME/.config/sunshine"
SUNSHINE_CONF="$SUNSHINE_DIR/sunshine.conf"
mkdir -p "$SUNSHINE_DIR"

LAN_IP="$(ip -4 -o addr show scope global 2>/dev/null | awk 'NR==1{split($4,a,"/"); print a[1]}')"

# Detect if we're on virtio-gpu (Proxmox/QEMU VM) — default wlr capture is broken
# on Niri/Hyprland + virgl. Force KMS capture which bypasses wlroots screencopy.
IS_VIRTIO_GPU=0
if [ -e /sys/class/drm/card1-Virtual-1 ] || \
   lspci -nn 2>/dev/null | grep -qi "virtio-gpu\|Red Hat.*Virtio\|QXL\|Virtual GPU"; then
  IS_VIRTIO_GPU=1
  log "virtio-gpu detected — will force capture=kms (wlr path is buggy on virgl)"
fi

# Build new sunshine.conf preserving existing user settings we don't manage
TMP_CONF="$(mktemp)"
{
  # Preserve any user lines that aren't ours
  if [ -f "$SUNSHINE_CONF" ]; then
    grep -vE "^(csrf_allowed_origins|capture|output_name|min_log_level)\s*=" "$SUNSHINE_CONF" 2>/dev/null || true
  fi
  # Our managed settings
  [ -n "$LAN_IP" ] && printf "csrf_allowed_origins = https://%s:47990\n" "$LAN_IP"
  if [ "$IS_VIRTIO_GPU" = 1 ]; then
    printf "capture = kms\n"
    printf "output_name = 0\n"
  fi
} > "$TMP_CONF"
mv "$TMP_CONF" "$SUNSHINE_CONF"
log "Wrote $SUNSHINE_CONF"
[ -n "$LAN_IP" ] && log "  csrf_allowed_origins = https://${LAN_IP}:47990"
[ "$IS_VIRTIO_GPU" = 1 ] && log "  capture = kms, output_name = 0"

# ---------- enable user service ----------
log "Enabling sunshine user service..."
SUNSHINE_UNIT=""
for unit in sunshine.service app-dev.lizardbyte.app.Sunshine.service; do
  if systemctl --user list-unit-files "$unit" 2>/dev/null | grep -q "$unit"; then
    SUNSHINE_UNIT="$unit"
    break
  fi
done
[ -n "$SUNSHINE_UNIT" ] || die "No sunshine.service found in user units"
log "Unit: $SUNSHINE_UNIT"

systemctl --user daemon-reload
systemctl --user enable "$SUNSHINE_UNIT"
systemctl --user restart "$SUNSHINE_UNIT" || warn "Restart failed - start from inside Hyprland session"

# ---------- summary ----------
echo ""
echo "[sunshine] ===== SETUP COMPLETE ====="
echo "  Unit:      $SUNSHINE_UNIT"
echo "  Web UI:    https://localhost:47990"
echo "  LAN URL:   https://${LAN_IP:-unknown}:47990"
echo "  SSH tunnel (recommended for CSRF):"
echo "    ssh -L 47990:localhost:47990 ${USER}@${LAN_IP:-<host>}"
echo "    then open https://localhost:47990 in your browser"
echo ""
echo "Next steps:"
echo "  1. If added to 'input' group: logout/login to apply"
echo "  2. Open Web UI, create admin user/password"
echo "  3. Pair Moonlight clients via the UI"
echo ""
echo "Status:"
echo "  systemctl --user status $SUNSHINE_UNIT"
