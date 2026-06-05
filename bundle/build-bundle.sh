#!/usr/bin/env bash
# Build air-gap bundle on an internet-connected machine.
# Image versions are read from docker-compose.yml only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/compose-images.sh
source "${SCRIPT_DIR}/lib/compose-images.sh"
# shellcheck source=lib/pull-image.sh
source "${SCRIPT_DIR}/lib/pull-image.sh"

require_cmd docker awk sort tar gzip

OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/../bundle-output}"
STAGING="${OUTPUT_DIR}/staging"
IMAGES_DIR="${STAGING}/images"
VERSION="$(grep -E 'openfn/lightning:' "${SCRIPT_DIR}/docker-compose.yml" | head -1 | sed -E 's/.*openfn\/lightning://; s/[^a-zA-Z0-9._-]//g')"
DATE_STAMP="$(date +%Y%m%d)"
BUNDLE_NAME="openfn-lightning-bundle-${VERSION:-unknown}-${DATE_STAMP}"

log_info "Building bundle: ${BUNDLE_NAME}"

rm -rf "${STAGING}"
mkdir -p "${IMAGES_DIR}"

log_info "Discovering images from docker-compose.yml..."
IMAGES=()
while IFS= read -r img; do
  [[ -n "$img" ]] && IMAGES+=("$img")
done < <(list_compose_images)
[[ ${#IMAGES[@]} -gt 0 ]] || die "No images found in docker-compose.yml"

# Ministry servers are x86_64; always bundle amd64 images (also required on Apple Silicon builders).
PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
log_info "Pulling ${#IMAGES[@]} image(s) for platform ${PLATFORM}..."
for image in "${IMAGES[@]}"; do
  log_info "  pull ${image}"
  pull_amd64_image "$image"
done

log_info "Saving images to tar archives..."
MANIFEST="${STAGING}/MANIFEST.txt"
{
  echo "OpenFn Lightning air-gap bundle"
  echo "Built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Images:"
} >"$MANIFEST"

for image in "${IMAGES[@]}"; do
  tar_name="$(image_to_filename "$image").tar"
  log_info "  save ${image} -> images/${tar_name}"
  docker image inspect "$image" >/dev/null || die "Image not present after pull: ${image}"
  # Save by repository:tag so docker load restores names (required on air-gapped host).
  docker save -o "${IMAGES_DIR}/${tar_name}" "$image"
  digest="$(docker image inspect "$image" --format '{{.Id}}')"
  echo "  ${image}  file=images/${tar_name}  id=${digest}  platform=${PLATFORM}" >>"$MANIFEST"
done

log_info "Copying deployment files..."
for item in docker-compose.yml load-images.sh deploy.sh verify.sh rotate-secrets.sh lib templates; do
  if [[ -e "${SCRIPT_DIR}/${item}" ]]; then
    cp -a "${SCRIPT_DIR}/${item}" "${STAGING}/"
  fi
done
chmod +x "${STAGING}"/*.sh 2>/dev/null || true
chmod +x "${STAGING}/lib"/*.sh 2>/dev/null || true

log_info "Generating SHA256SUMS..."
(
  cd "${STAGING}"
  find . -type f ! -name SHA256SUMS | sort | while read -r f; do
    sha256_file "$f"
  done
) >"${STAGING}/SHA256SUMS"

mkdir -p "${OUTPUT_DIR}"
TARBALL="${OUTPUT_DIR}/${BUNDLE_NAME}.tar.gz"
# Omit macOS xattrs from tarball (Linux tar warns on LIBARCHIVE.xattr.*).
if [[ "$(uname -s)" == "Darwin" ]]; then
  COPYFILE_DISABLE=1 tar -czf "${TARBALL}" -C "${STAGING}" .
else
  tar -czf "${TARBALL}" -C "${STAGING}" .
fi
SIZE="$(du -h "${TARBALL}" | cut -f1)"
log_info "Bundle created: ${TARBALL} (${SIZE})"
log_info "Transfer this file to the air-gapped server and follow RUNBOOK.md"
