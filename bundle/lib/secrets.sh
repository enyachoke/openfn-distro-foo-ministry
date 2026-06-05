#!/usr/bin/env bash
# Generate and manage deployment secrets.

set -euo pipefail

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_lib_dir}/common.sh"

rand_hex() {
  openssl rand -hex "${1:-32}"
}

rand_base64() {
  openssl rand -base64 "${1:-32}" | tr -d '\n'
}

gen_secret_key_base() {
  rand_hex 64
}

gen_primary_encryption_key() {
  rand_base64 32
}

gen_worker_secret() {
  rand_hex 32
}

gen_postgres_password() {
  openssl rand -base64 24 | tr -d '/+=' | head -c 32
}

gen_worker_rsa_keys() {
  if [[ -n "${WORKER_RUNS_PRIVATE_KEY:-}" && -n "${WORKER_LIGHTNING_PUBLIC_KEY:-}" ]]; then
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  openssl genrsa -out "${tmp}/private.pem" 2048 2>/dev/null
  openssl rsa -in "${tmp}/private.pem" -pubout -out "${tmp}/public.pem" 2>/dev/null
  WORKER_RUNS_PRIVATE_KEY="$(base64 < "${tmp}/private.pem" | tr -d '\n')"
  WORKER_LIGHTNING_PUBLIC_KEY="$(base64 < "${tmp}/public.pem" | tr -d '\n')"
  rm -rf "$tmp"
}

write_secrets_env() {
  local secrets_file="$1"
  local pg_user="${POSTGRES_USER:-postgres}"
  local pg_db="${POSTGRES_DB:-lightning}"
  local pg_pass="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD required}"
  local secret_key="${SECRET_KEY_BASE:?SECRET_KEY_BASE required}"
  local enc_key="${PRIMARY_ENCRYPTION_KEY:?PRIMARY_ENCRYPTION_KEY required}"

  gen_worker_rsa_keys

  mkdir -p "$(dirname "$secrets_file")"
  cat >"$secrets_file" <<EOF
# OpenFn Lightning secrets — mode 600, do not commit.
POSTGRES_USER=${pg_user}
POSTGRES_PASSWORD=${pg_pass}
POSTGRES_DB=${pg_db}
DATABASE_URL=postgresql://${pg_user}:${pg_pass}@postgres:5432/${pg_db}
SECRET_KEY_BASE=${secret_key}
PRIMARY_ENCRYPTION_KEY=${enc_key}
WORKER_RUNS_PRIVATE_KEY=${WORKER_RUNS_PRIVATE_KEY}
WORKER_LIGHTNING_PUBLIC_KEY=${WORKER_LIGHTNING_PUBLIC_KEY}
WORKER_SECRET=${WORKER_SECRET:-$(gen_worker_secret)}
EOF
  chmod 600 "$secrets_file"
  log_info "Wrote secrets to ${secrets_file}"
}

write_config_env() {
  local config_file="$1"
  local url_host="${URL_HOST:-localhost}"
  local email="${EMAIL_ADMIN:-admin@example.com}"
  local port="${LIGHTNING_EXTERNAL_PORT:-4000}"

  cat >"$config_file" <<EOF
# OpenFn Lightning non-secret configuration
MIX_ENV=prod
NODE_ENV=production
URL_HOST=${url_host}
URL_SCHEME=http
URL_PORT=${port}
PORT=${port}
LISTEN_ADDRESS=0.0.0.0
EMAIL_ADMIN=${email}
EMAIL_SENDER_NAME="OpenFn Lightning"
ALLOW_SIGNUP=true
USAGE_TRACKING_ENABLED=false
DISABLE_DB_SSL=true
DOCKER_RESTART_POLICY=unless-stopped
LIGHTNING_EXTERNAL_PORT=0.0.0.0:${port}:${port}
EOF
  chmod 644 "$config_file"
}

generate_all_secrets() {
  POSTGRES_USER="${POSTGRES_USER:-postgres}"
  POSTGRES_DB="${POSTGRES_DB:-lightning}"
  POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(gen_postgres_password)}"
  SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(gen_secret_key_base)}"
  PRIMARY_ENCRYPTION_KEY="${PRIMARY_ENCRYPTION_KEY:-$(gen_primary_encryption_key)}"
  WORKER_SECRET="${WORKER_SECRET:-$(gen_worker_secret)}"
}

prompt_or_generate_secrets() {
  if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
    generate_all_secrets
    URL_HOST="${URL_HOST:-localhost}"
    EMAIL_ADMIN="${EMAIL_ADMIN:-admin@example.com}"
    LIGHTNING_EXTERNAL_PORT="${LIGHTNING_EXTERNAL_PORT:-4000}"
    return 0
  fi

  log_info "Press Enter to auto-generate cryptographic secrets, or type values when prompted."
  read -r -p "URL_HOST [localhost]: " URL_HOST
  URL_HOST="${URL_HOST:-localhost}"
  read -r -p "EMAIL_ADMIN [admin@${URL_HOST}]: " EMAIL_ADMIN
  EMAIL_ADMIN="${EMAIL_ADMIN:-admin@${URL_HOST}}"
  read -r -p "External port [4000]: " LIGHTNING_EXTERNAL_PORT
  LIGHTNING_EXTERNAL_PORT="${LIGHTNING_EXTERNAL_PORT:-4000}"

  generate_all_secrets
  log_info "Generated new cryptographic secrets."
}
