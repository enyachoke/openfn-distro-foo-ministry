#!/usr/bin/env bash
# Rotate application and database secrets for an existing deployment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/secrets.sh
source "${SCRIPT_DIR}/lib/secrets.sh"

DEPLOY_DIR=""
NON_INTERACTIVE=0
ROTATE_ALL=0
ROTATE_PG=0
ROTATE_APP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deploy-dir) DEPLOY_DIR="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --postgres-password) ROTATE_PG=1; shift ;;
    --all) ROTATE_ALL=1; shift ;;
    -h | --help)
      echo "Usage: $0 [--deploy-dir PATH] [--all] [--postgres-password] [--non-interactive]"
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

if [[ -z "$DEPLOY_DIR" ]]; then
  if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
    DEPLOY_DIR="${SCRIPT_DIR}"
  else
    DEPLOY_DIR="${OPENFN_DEPLOY_DIR:-$(default_deploy_dir)}"
  fi
fi

export NON_INTERACTIVE
SECRETS_FILE="${DEPLOY_DIR}/secrets/.env"
[[ -f "${DEPLOY_DIR}/docker-compose.yml" ]] || die "No deployment at ${DEPLOY_DIR}"
[[ -f "$SECRETS_FILE" ]] || die "No secrets file at ${SECRETS_FILE}"

# shellcheck disable=SC1091
source "$SECRETS_FILE"

cd "$DEPLOY_DIR"
require_cmd docker openssl

if [[ $ROTATE_ALL -eq 0 && $ROTATE_PG -eq 0 && $ROTATE_APP -eq 0 ]]; then
  if [[ $NON_INTERACTIVE -eq 1 ]]; then
    ROTATE_PG=1
  else
    echo "What to rotate?"
    echo "  1) Postgres password only"
    echo "  2) Application secrets"
    echo "  3) All secrets"
    read -r -p "Choice [1]: " choice
    case "${choice:-1}" in
      1) ROTATE_PG=1 ;;
      2) ROTATE_APP=1 ;;
      3) ROTATE_ALL=1; ROTATE_PG=1; ROTATE_APP=1 ;;
      *) die "Invalid choice" ;;
    esac
  fi
fi

if [[ $ROTATE_ALL -eq 1 ]]; then
  ROTATE_PG=1
  ROTATE_APP=1
fi

bak="${SECRETS_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp -a "$SECRETS_FILE" "$bak"
log_info "Backed up secrets to ${bak}"

log_info "Stopping web and worker (Postgres stays up)..."
docker compose stop web worker 2>/dev/null || true

if [[ $ROTATE_PG -eq 1 ]]; then
  NEW_PG_PASS="$(gen_postgres_password)"
  log_info "Rotating Postgres password..."
  docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d postgres \
    -c "ALTER USER ${POSTGRES_USER} PASSWORD '${NEW_PG_PASS}';"
  POSTGRES_PASSWORD="$NEW_PG_PASS"
fi

if [[ $ROTATE_APP -eq 1 ]]; then
  log_warn "Rotating PRIMARY_ENCRYPTION_KEY will invalidate encrypted credentials at rest."
  if [[ $NON_INTERACTIVE -eq 0 ]]; then
    confirm "Continue with application secret rotation?" || die "Aborted"
  fi
  SECRET_KEY_BASE="$(gen_secret_key_base)"
  PRIMARY_ENCRYPTION_KEY="$(gen_primary_encryption_key)"
  WORKER_SECRET="$(gen_worker_secret)"
  gen_worker_rsa_keys
fi

if [[ $ROTATE_PG -eq 1 || $ROTATE_APP -eq 1 ]]; then
  write_secrets_env "$SECRETS_FILE"
fi

log_info "Starting web and worker..."
docker compose up -d web worker --pull never

sleep 10
cat "$SECRETS_FILE" "${DEPLOY_DIR}/config.env" >"${DEPLOY_DIR}/.env"
chmod 600 "${DEPLOY_DIR}/.env"
"${DEPLOY_DIR}/verify.sh"
