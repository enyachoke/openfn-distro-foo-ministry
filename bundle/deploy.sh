#!/usr/bin/env bash
# Install or update OpenFn Lightning on air-gapped server.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_SOURCE="${BUNDLE_SOURCE:-$SCRIPT_DIR}"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/secrets.sh
source "${SCRIPT_DIR}/lib/secrets.sh"

YES=0
NON_INTERACTIVE=0
DEPLOY_DIR=""

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --deploy-dir PATH   Deployment directory
  --yes               Skip confirmation prompts
  --non-interactive   Non-interactive mode
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deploy-dir) DEPLOY_DIR="$2"; shift 2 ;;
    --yes) YES=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; YES=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

export YES NON_INTERACTIVE
DEPLOY_DIR="${DEPLOY_DIR:-$(default_deploy_dir)}"

if [[ $NON_INTERACTIVE -eq 0 ]]; then
  prompted="$(prompt "Deployment directory" "$DEPLOY_DIR")"
  DEPLOY_DIR="$prompted"
fi

export OPENFN_DEPLOY_DIR="$DEPLOY_DIR"
require_cmd docker openssl

IS_UPDATE=0
if [[ -f "${DEPLOY_DIR}/docker-compose.yml" ]]; then
  IS_UPDATE=1
  log_warn "Existing deployment found at ${DEPLOY_DIR}"
  if [[ -f "${BUNDLE_SOURCE}/MANIFEST.txt" ]]; then
    log_info "New bundle manifest:"
    head -5 "${BUNDLE_SOURCE}/MANIFEST.txt" || true
  fi
  if [[ $YES -eq 0 ]]; then
    confirm "This will stop Lightning and update files. Continue?" || die "Aborted by user"
  fi
  log_info "Stopping existing deployment..."
  (cd "$DEPLOY_DIR" && docker compose down) || true
fi

log_info "Preparing deployment directory: ${DEPLOY_DIR}"
ensure_dir "${DEPLOY_DIR}/secrets" "${DEPLOY_DIR}/data/postgres" "${DEPLOY_DIR}/images"

log_info "Loading container images from bundle..."
BUNDLE_DIR="$BUNDLE_SOURCE" "${BUNDLE_SOURCE}/load-images.sh" || die "load-images.sh failed"

log_info "Copying deployment files to ${DEPLOY_DIR}..."
for item in docker-compose.yml load-images.sh deploy.sh verify.sh rotate-secrets.sh lib templates MANIFEST.txt SHA256SUMS; do
  if [[ -e "${BUNDLE_SOURCE}/${item}" ]]; then
    cp -a "${BUNDLE_SOURCE}/${item}" "${DEPLOY_DIR}/"
  fi
done
chmod +x "${DEPLOY_DIR}"/*.sh "${DEPLOY_DIR}/lib"/*.sh 2>/dev/null || true

if [[ -d "${BUNDLE_SOURCE}/images" ]]; then
  cp -a "${BUNDLE_SOURCE}/images/"* "${DEPLOY_DIR}/images/" 2>/dev/null || true
fi

SECRETS_FILE="${DEPLOY_DIR}/secrets/.env"
CONFIG_FILE="${DEPLOY_DIR}/config.env"

if [[ $IS_UPDATE -eq 1 && -f "$SECRETS_FILE" ]]; then
  log_info "Keeping existing secrets/.env"
else
  prompt_or_generate_secrets
  write_secrets_env "$SECRETS_FILE"
  write_config_env "$CONFIG_FILE"
fi

# Docker Compose reads .env for ${VAR} interpolation in docker-compose.yml.
cat "$SECRETS_FILE" "$CONFIG_FILE" >"${DEPLOY_DIR}/.env"
chmod 600 "${DEPLOY_DIR}/.env"

cd "$DEPLOY_DIR"

log_info "Starting Postgres..."
docker compose up -d postgres --pull never

log_info "Waiting for Postgres to become healthy..."
# shellcheck disable=SC1091
source secrets/.env
for i in $(seq 1 30); do
  if docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

log_info "Running database migrations..."
docker compose run --rm --no-deps web /app/bin/lightning eval "Lightning.Release.migrate()"

log_info "Starting all services..."
docker compose up -d --pull never

log_info "Waiting for services to become healthy..."
sleep 30

DEPLOY_DIR="$DEPLOY_DIR" "${DEPLOY_DIR}/verify.sh"
