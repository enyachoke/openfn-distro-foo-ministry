#!/usr/bin/env bash
# Shared helpers for OpenFn air-gap bundle scripts.

set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_info() { log "INFO: $*"; }
log_warn() { log "WARN: $*" >&2; }
log_error() { log "ERROR: $*" >&2; }

die() {
  log_error "$1"
  exit "${2:-1}"
}

# Resolve bundle root (directory containing docker-compose.yml).
bundle_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
  echo "$script_dir"
}

# Resolve deploy directory from env or default.
default_deploy_dir() {
  echo "${OPENFN_DEPLOY_DIR:-/opt/openfn-lightning}"
}

prompt() {
  local msg="$1"
  local default="${2:-}"
  local reply
  if [[ -n "$default" ]]; then
    read -r -p "${msg} [${default}]: " reply
    echo "${reply:-$default}"
  else
    read -r -p "${msg}: " reply
    echo "$reply"
  fi
}

confirm() {
  local msg="$1"
  local reply
  local normalized
  if [[ "${NON_INTERACTIVE:-0}" == "1" || "${YES:-0}" == "1" ]]; then
    return 0
  fi
  read -r -p "${msg} [y/N]: " reply
  # tr for Bash 3.2 (macOS default); ${var,,} needs Bash 4+.
  normalized="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
  [[ "$normalized" == "y" || "$normalized" == "yes" ]]
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
  done
}

# Portable checksum (Linux sha256sum, macOS shasum).
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

sha256_verify() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$@"
  else
    shasum -a 256 -c "$@"
  fi
}

ensure_dir() {
  mkdir -p "$@"
}

safe_copy() {
  local src="$1"
  local dest="$2"
  cp -a "$src" "$dest"
}

compose_cmd() {
  local deploy_dir="${1:-.}"
  shift || true
  docker compose -f "${deploy_dir}/docker-compose.yml" "$@"
}
