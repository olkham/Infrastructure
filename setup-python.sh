#!/usr/bin/env bash
# Installs side-by-side CPython builds with uv, leaving the system python3 untouched.
# Usage: sudo bash setup-python.sh
#    or: sudo -E PYTHON_VERSIONS="3.12 3.13" bash setup-python.sh
set -euo pipefail

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo bash $0"

SUPPORTED_VERSIONS=(3.11 3.12 3.13)
UV_PYTHON_DIR=/opt/python
export UV_PYTHON_INSTALL_DIR=$UV_PYTHON_DIR
VERSIONS=()

valid_selection() {
  local v
  [[ -n $1 ]] || return 1
  for v in $1; do
    [[ " ${SUPPORTED_VERSIONS[*]} " == *" $v "* ]] || return 1
  done
}

select_versions() {
  local input=${PYTHON_VERSIONS:-}
  if [[ -z $input ]]; then
    [[ -r /dev/tty ]] || die "No terminal to ask on; set PYTHON_VERSIONS, e.g. PYTHON_VERSIONS=\"3.12 3.13\"."
    while true; do
      read -r -p "Python versions to install (${SUPPORTED_VERSIONS[*]}; space or comma separated): " input < /dev/tty \
        || die "No input received."
      input=${input//,/ }
      valid_selection "$input" && break
      warn "Enter one or more of: ${SUPPORTED_VERSIONS[*]}"
    done
  fi
  input=${input//,/ }
  valid_selection "$input" || die "Unsupported selection '$input'; choose from: ${SUPPORTED_VERSIONS[*]}"
  read -ra VERSIONS <<< "$input"
}

install_system_python() {
  log "System Python tooling (system python3 left untouched)"
  apt-get update
  apt-get install -y ca-certificates curl python3 python3-venv python3-pip
  ln -sfn /usr/bin/python3 /usr/local/bin/python
  ln -sfn /usr/bin/pip3 /usr/local/bin/pip
}

install_uv() {
  command -v uv >/dev/null && return
  log "uv (Python installer)"
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh
}

install_python() {
  local v=$1 bin
  log "Python $v"
  uv python install "$v"
  bin=$(uv python find --managed-python "$v")
  ln -sfn "$bin" "/usr/local/bin/python$v"
  if [[ -x "$(dirname "$bin")/pip$v" ]]; then
    ln -sfn "$(dirname "$bin")/pip$v" "/usr/local/bin/pip$v"
  else
    warn "pip$v not found in the $v install; use: python$v -m pip"
  fi
}

install_mkenv() {
  log "mkenv command"
  cat > /usr/local/bin/mkenv <<'EOF'
#!/usr/bin/env bash
# Usage: mkenv [--name]   (default name: .venv)
set -euo pipefail

usage() { echo "Usage: mkenv [--name]" >&2; exit 1; }

name=.venv
if [[ $# -gt 0 ]]; then
  [[ $1 == --?* ]] || usage
  name=${1#--}
  shift
fi
[[ $# -eq 0 && $name != */* ]] || usage

if [[ -e $name ]]; then
  echo "mkenv: '$name' already exists" >&2
  exit 1
fi
python3 -m venv "$name"
echo "Created $name. Activate with: source $name/bin/activate"
EOF
  chmod 0755 /usr/local/bin/mkenv
}

main() {
  select_versions
  install_system_python
  install_uv
  for v in "${VERSIONS[@]}"; do
    install_python "$v"
  done
  install_mkenv
  log "Python setup complete: ${VERSIONS[*]}"
}

main "$@"
