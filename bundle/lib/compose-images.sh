#!/usr/bin/env bash
# Extract image references from docker-compose.yml (single source of truth).

set -euo pipefail

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ROOT="$(cd "${_lib_dir}/.." && pwd)"
COMPOSE_FILE="${BUNDLE_ROOT}/docker-compose.yml"

list_compose_images() {
  local compose_file="${BUNDLE_ROOT}/docker-compose.yml"
  if [[ ! -f "$compose_file" ]]; then
    echo "docker-compose.yml not found: $compose_file" >&2
    return 1
  fi

  # Parse image: lines directly (works without secrets/.env present).
  grep -E '^[[:space:]]*image:' "$compose_file" \
    | sed -E 's/^[[:space:]]*image:[[:space:]]*//' \
    | tr -d "\"'" \
    | sort -u
}

# Sanitize image ref for tarball filename (openfn/lightning:v2.16.6 -> openfn_lightning_v2.16.6).
image_to_filename() {
  local image="$1"
  echo "$image" | tr '/:@' '___'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  list_compose_images
fi
