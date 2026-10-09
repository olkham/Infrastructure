#!/usr/bin/env bash
# Idempotent workstation setup for Ubuntu 22.04, 24.04 and 26.04.
# Usage: sudo bash setup-ubuntu.sh
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo bash $0"
TARGET_USER="${SUDO_USER:-root}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. /etc/os-release
[[ $ID == ubuntu ]] || die "Unsupported distribution: $ID"
case "$VERSION_ID" in
  22.04|24.04|26.04) ;;
  *) die "Unsupported Ubuntu version: $VERSION_ID" ;;
esac
CODENAME="$VERSION_CODENAME"
ARCH="$(dpkg --print-architecture)"

NEED_UPDATE=1
apt_update() {
  if (( NEED_UPDATE )); then
    apt-get update
    NEED_UPDATE=0
  fi
}
apt_install() {
  apt_update
  apt-get install -y "$@"
}

# Writes a file only when its content differs, so repeated runs do not refresh apt.
write_if_changed() {
  local path=$1 content=$2
  if [[ ! -f $path ]] || [[ "$(cat "$path")" != "$content" ]]; then
    printf '%s\n' "$content" > "$path"
    NEED_UPDATE=1
  fi
}

install_key() {
  local url=$1 dest=$2
  if [[ ! -s $dest ]]; then
    curl -fsSL "$url" | gpg --dearmor --yes -o "$dest.tmp"
    mv "$dest.tmp" "$dest"
  fi
  chmod 0644 "$dest"
}

has_nvidia_gpu() {
  local d
  for d in /sys/bus/pci/devices/*; do
    [[ $(<"$d/vendor") == 0x10de && $(<"$d/class") == 0x03* ]] && return 0
  done
  return 1
}

setup_ssh() {
  log "OpenSSH server"
  apt_install openssh-server
  systemctl enable --now ssh
}

setup_docker() {
  log "Docker Engine and Compose plugin"
  local codename=$CODENAME
  if ! curl -fsSI "https://download.docker.com/linux/ubuntu/dists/$codename/Release" >/dev/null; then
    warn "Docker has no repository for '$codename' yet; using 'noble' packages."
    codename=noble
  fi
  install_key https://download.docker.com/linux/ubuntu/gpg /etc/apt/keyrings/docker.gpg
  write_if_changed /etc/apt/sources.list.d/docker.list \
    "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $codename stable"
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker

  if [[ $TARGET_USER != root ]]; then
    case " $(id -nG "$TARGET_USER") " in
      *" docker "*) ;;
      *)
        usermod -aG docker "$TARGET_USER"
        warn "Added $TARGET_USER to the docker group; log out and back in to apply."
        ;;
    esac
  fi
}

setup_chrome() {
  log "Google Chrome"
  if [[ $ARCH != amd64 ]]; then
    warn "Google Chrome is only published for amd64 (this system is $ARCH); skipping."
    return
  fi
  install_key https://dl.google.com/linux/linux_signing_key.pub /etc/apt/keyrings/google-chrome.gpg
  write_if_changed /etc/apt/sources.list.d/google-chrome.list \
    "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main"
  apt_install google-chrome-stable
}

setup_vscode() {
  log "Visual Studio Code"
  install_key https://packages.microsoft.com/keys/microsoft.asc /etc/apt/keyrings/microsoft.gpg
  write_if_changed /etc/apt/sources.list.d/vscode.list \
    "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main"
  apt_install code
}

setup_python() {
  log "Python (side-by-side installs)"
  bash "$SCRIPT_DIR/setup-python.sh"
}

setup_nodejs() {
  log "Node.js LTS (NodeSource)"
  local node_major=24
  install_key https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key /etc/apt/keyrings/nodesource.gpg
  write_if_changed /etc/apt/sources.list.d/nodesource.list \
    "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${node_major}.x nodistro main"
  apt_install nodejs
}

setup_vlc() {
  log "VLC (native deb; RTSP/live555 support is built in)"
  if command -v snap >/dev/null && snap list vlc >/dev/null 2>&1; then
    warn "Snap VLC is installed and sandboxed; remove it with: sudo snap remove vlc"
  fi
  apt_install vlc
}

setup_nvtop() {
  log "nvtop"
  if ! apt-cache show nvtop >/dev/null 2>&1; then
    apt_install software-properties-common
    add-apt-repository -y universe
    NEED_UPDATE=1
  fi
  apt_install nvtop
  command -v nvidia-smi >/dev/null || warn "NVIDIA driver not detected; install it with: sudo ubuntu-drivers install"
}

setup_stack() {
  log "Media stack (Docker Compose)"
  bash "$SCRIPT_DIR/setup-docker.sh"
}

preflight() {
  local f
  for f in setup-python.sh setup-docker.sh docker-compose.yml; do
    [[ -f $SCRIPT_DIR/$f ]] || die "Missing $f in $SCRIPT_DIR"
  done
}

main() {
  preflight
  log "Base prerequisites"
  apt_install ca-certificates curl git gnupg htop lm-sensors net-tools
  install -d -m 0755 /etc/apt/keyrings

  setup_ssh
  setup_docker
  setup_chrome
  setup_vscode
  setup_python
  setup_nodejs
  setup_vlc

  if has_nvidia_gpu; then
    setup_nvtop
  else
    log "No NVIDIA GPU detected; skipping nvtop"
  fi

  setup_stack

  log "Setup complete on Ubuntu $VERSION_ID"
}

main "$@"
