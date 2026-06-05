#!/usr/bin/env bash
# Unambiguous health check — prints RESULT: PASS or RESULT: FAIL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
  DEPLOY_DIR="${SCRIPT_DIR}"
else
  DEPLOY_DIR="${DEPLOY_DIR:-${OPENFN_DEPLOY_DIR:-$(default_deploy_dir)}}"
fi
FAIL_REASON=""

fail() {
  FAIL_REASON="$1"
  echo "RESULT: FAIL — ${FAIL_REASON}"
  exit 1
}

pass() {
  echo "RESULT: PASS"
  echo "Lightning is running. Open http://<server-ip>:4000 in a browser."
  exit 0
}

[[ -f "${DEPLOY_DIR}/docker-compose.yml" ]] || fail "No deployment at ${DEPLOY_DIR}"

cd "$DEPLOY_DIR"
require_cmd docker curl

PORT=4000
POSTGRES_USER=postgres
if [[ -f secrets/.env ]]; then
  # shellcheck disable=SC1091
  source secrets/.env
fi
if [[ -f config.env ]]; then
  # shellcheck disable=SC1091
  source config.env
fi

log_info "Checking container status..."
running="$(docker compose ps --status running --format '{{.Service}}' 2>/dev/null | sort | tr '\n' ' ')"
for svc in postgres web worker; do
  echo "$running" | grep -qw "$svc" || fail "Service '${svc}' is not running"
done

log_info "Checking Postgres..."
docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}" >/dev/null 2>&1 \
  || fail "Postgres is not accepting connections"

log_info "Checking Lightning health endpoint..."
if curl -sf "http://127.0.0.1:${PORT}/health_check" >/dev/null; then
  pass
else
  fail "Health check http://127.0.0.1:${PORT}/health_check did not return success"
fi
