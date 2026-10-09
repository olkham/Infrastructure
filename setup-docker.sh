#!/usr/bin/env bash
# Prompts for storage paths, exports compose variables, and starts the media stack.
# Usage: bash setup-docker.sh   (or DATA_DIR=... MEDIA_ROOT=... bash setup-docker.sh)
set -euo pipefail

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f $SCRIPT_DIR/docker-compose.yml ]] || die "docker-compose.yml not found in $SCRIPT_DIR"

if [[ $EUID -eq 0 && -n ${SUDO_USER:-} ]]; then
  OWNER=$SUDO_USER
else
  OWNER=$(id -un)
fi
OWNER_HOME=$(getent passwd "$OWNER" | cut -d: -f6)

resolve_path() { # name prompt default
  local name=$1 prompt=$2 default=$3 value=${!1:-} input=""
  if [[ -z $value ]]; then
    value=$default
    if [[ -r /dev/tty ]]; then
      read -r -p "$prompt [$default]: " input < /dev/tty || die "No input received."
      value=${input:-$default}
    fi
  fi
  value=${value/#\~/$OWNER_HOME}
  [[ $value == /* ]] || die "$name must be an absolute path: $value"
  printf -v "$name" '%s' "$value"
  export "$name"
}

export_identity() {
  PUID=$(id -u "$OWNER")
  PGID=$(id -g "$OWNER")
  TZ=${TZ:-$(cat /etc/timezone 2>/dev/null || echo Etc/UTC)}
  export PUID PGID TZ
}

prepare_dirs() {
  log "Creating folders"
  local dirs=(
    "$DATA_DIR/agentdvr/config" "$DATA_DIR/agentdvr/media" "$DATA_DIR/node-red"
    "$DATA_DIR/sabnzbd" "$DATA_DIR/sonarr" "$DATA_DIR/radarr" "$DATA_DIR/plex"
    "$MEDIA_ROOT/tv" "$MEDIA_ROOT/movies" "$MEDIA_ROOT/downloads"
  )
  mkdir -p "${dirs[@]}"
  if [[ $EUID -eq 0 ]]; then
    chown "$PUID:$PGID" "$DATA_DIR" "$MEDIA_ROOT" "${dirs[@]}"
  fi
}

main() {
  command -v docker >/dev/null || die "Docker is not installed; run setup-ubuntu.sh first."
  docker info >/dev/null 2>&1 || die "Cannot reach the Docker daemon; run with sudo or log out and back in after joining the docker group."

  resolve_path DATA_DIR "Where should app data be stored?" "$OWNER_HOME/data"
  resolve_path MEDIA_ROOT "Where is the media library stored?" "$OWNER_HOME/media"
  export_identity
  prepare_dirs

  log "Starting the media stack"
  cd "$SCRIPT_DIR"
  docker compose up -d
  log "Stack is up. Data: $DATA_DIR  Media: $MEDIA_ROOT"
}

main "$@"
