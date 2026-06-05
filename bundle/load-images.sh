#!/usr/bin/env bash
# Load container images from bundle on air-gapped server.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/compose-images.sh
source "${SCRIPT_DIR}/lib/compose-images.sh"

require_cmd docker

BUNDLE_DIR="${BUNDLE_DIR:-$SCRIPT_DIR}"

if [[ -f "${BUNDLE_DIR}/SHA256SUMS" ]]; then
  log_info "Verifying image archive integrity (SHA256SUMS)..."
  (
    cd "$BUNDLE_DIR"
    grep './images/' SHA256SUMS >SHA256SUMS.images || true
    [[ -s SHA256SUMS.images ]] || die "No image checksums found in SHA256SUMS"
    sha256_verify SHA256SUMS.images
    rm -f SHA256SUMS.images
  ) || die "Checksum verification failed — image archives may be corrupted"
  log_info "Image checksum verification passed."
else
  log_warn "SHA256SUMS not found; skipping integrity check."
fi

IMAGES_DIR="${BUNDLE_DIR}/images"
[[ -d "$IMAGES_DIR" ]] || die "images/ directory not found in ${BUNDLE_DIR}"

shopt -s nullglob
tars=("${IMAGES_DIR}"/*.tar)
[[ ${#tars[@]} -gt 0 ]] || die "No image tar files in ${IMAGES_DIR}"

for tar_file in "${tars[@]}"; do
  log_info "Loading $(basename "$tar_file")..."
  docker load -i "$tar_file"
done

# Ensure every compose image is present and tagged (load can leave dangling IDs).
EXPECTED=()
while IFS= read -r img; do
  [[ -n "$img" ]] && EXPECTED+=("$img")
done < <(list_compose_images)

log_info "Verifying loaded images match docker-compose.yml..."
missing=0
for image in "${EXPECTED[@]}"; do
  if docker image inspect "$image" >/dev/null 2>&1; then
    log_info "  OK ${image}"
  else
    log_error "  MISSING ${image}"
    missing=1
  fi
done

if [[ $missing -eq 1 ]]; then
  log_info "Current docker images:"
  docker images || true
  die "One or more required images missing after docker load — rebuild bundle on linux/amd64"
fi

log_info "All required images loaded."
