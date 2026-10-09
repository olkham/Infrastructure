#!/usr/bin/env bash
# Idempotent system settings for Ubuntu 22.04, 24.04 and 26.04.
# Usage: sudo bash update-system-settings.sh
set -euo pipefail

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo bash $0"

. /etc/os-release
[[ $ID == ubuntu ]] || die "Unsupported distribution: $ID"
case "$VERSION_ID" in
  22.04|24.04|26.04) ;;
  *) die "Unsupported Ubuntu version: $VERSION_ID" ;;
esac

# Writes a file only when its content differs; returns 0 when it changed.
write_if_changed() {
  local path=$1 content=$2
  mkdir -p "$(dirname "$path")"
  if [[ ! -f $path ]] || [[ "$(cat "$path")" != "$content" ]]; then
    printf '%s\n' "$content" > "$path"
    return 0
  fi
  return 1
}

no_sleep_targets() {
  log "Disable suspend and hibernate targets"
  systemctl mask sleep.target suspend.target hibernate.target \
    hybrid-sleep.target suspend-then-hibernate.target >/dev/null
}

no_sleep_logind() {
  log "Ignore lid close and idle suspend (systemd-logind)"
  local content="[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
IdleAction=ignore"
  if write_if_changed /etc/systemd/logind.conf.d/10-no-sleep.conf "$content"; then
    systemctl restart systemd-logind
  fi
}

no_sleep_gnome() {
  log "GNOME power settings (desktop only)"
  if ! command -v dconf >/dev/null; then
    warn "dconf not found; skipping GNOME power settings."
    return
  fi
  local profile="user-db:user
system-db:local"
  local db="[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'"
  local changed=0
  if write_if_changed /etc/dconf/profile/user "$profile"; then changed=1; fi
  if write_if_changed /etc/dconf/db/local.d/00-no-sleep "$db"; then changed=1; fi
  if (( changed )); then
    dconf update
  fi
}

main() {
  no_sleep_targets
  no_sleep_logind
  no_sleep_gnome
  log "System settings updated"
}

main "$@"
