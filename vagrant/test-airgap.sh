#!/usr/bin/env bash
# Test air-gap bundle: build on builder host, transfer to ministry, deploy.
# Run ./cleanup-vagrant.sh first for a clean slate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUEST_DISTRO="/vagrant/openfn-distro"
GUEST_OUTPUT="${GUEST_DISTRO}/bundle-output"
BUILDER_IP="192.168.56.10"
MINISTRY_IP="192.168.56.20"
DOCKER_NET="openfn-vagrant-lab"
PROVIDER="${VAGRANT_PROVIDER:-docker}"
LIGHTNING_HOST_PORT="${LIGHTNING_HOST_PORT:-14000}"

SKIP_BUILD=0
SKIP_ROTATE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1; shift ;;
    --skip-rotate) SKIP_ROTATE=1; shift ;;
    -h | --help)
      echo "Usage: $0 [--skip-build] [--skip-rotate]"
      echo "  ./cleanup-vagrant.sh"
      echo "  builder — runs build-bundle.sh"
      echo "  ministry — receives bundle via scp, deploys"
      echo "  Lightning: http://localhost:${LIGHTNING_HOST_PORT}"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

log() { echo "[test] $*"; }
fail() { echo "[test] FAIL: $*"; exit 1; }
pass_step() { echo "[test] PASS: $*"; }

cd "$SCRIPT_DIR"
command -v vagrant >/dev/null || fail "vagrant not installed"
command -v docker >/dev/null || fail "docker not installed (required for Docker provider)"

log "Creating Docker network ${DOCKER_NET}..."
docker network inspect "$DOCKER_NET" >/dev/null 2>&1 \
  || docker network create --subnet 192.168.56.0/24 "$DOCKER_NET"

log "Starting builder + ministry (provider=${PROVIDER}, linux/amd64)..."
vagrant up builder ministry --provider="$PROVIDER"

for vm in builder ministry; do
  arch="$(vagrant ssh "$vm" -c "uname -m" 2>/dev/null | tr -d '\r')"
  [[ "$arch" == "x86_64" ]] || fail "${vm}: expected x86_64, got ${arch}"
  log "${vm} architecture: ${arch}"
done
pass_step "both hosts are x86_64"

if [[ $SKIP_BUILD -eq 0 ]]; then
  log "Building bundle on builder host (${BUILDER_IP})..."
  vagrant ssh builder -c "cd ${GUEST_DISTRO}/bundle && ./build-bundle.sh" \
    || fail "build-bundle.sh failed on builder"
  pass_step "bundle build on builder"
fi

TARBALL_NAME="$(vagrant ssh builder -c "ls -t ${GUEST_OUTPUT}/*.tar.gz | head -1 | xargs basename" 2>/dev/null | tr -d '\r')"
[[ -n "$TARBALL_NAME" ]] || fail "No tarball found on builder in ${GUEST_OUTPUT}"

REMOTE="/tmp/openfn-bundle-test"
BUNDLE_REMOTE="/tmp/${TARBALL_NAME}"

log "Transferring bundle builder → ministry (scp with Vagrant SSH key)..."
IDENTITY_FILE="$(vagrant ssh-config ministry 2>/dev/null | awk '$1 == "IdentityFile" { print $2 }' | tr -d '"')"
[[ -n "$IDENTITY_FILE" && -f "$IDENTITY_FILE" ]] || fail "Could not find Vagrant IdentityFile for ministry"

# Copy private key onto builder so scp can run non-interactively.
vagrant ssh builder -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
cat "$IDENTITY_FILE" | vagrant ssh builder -c "cat > ~/.ssh/id_rsa && chmod 600 ~/.ssh/id_rsa"

vagrant ssh builder -c "
  set -e
  TARBALL=\$(ls -t ${GUEST_OUTPUT}/*.tar.gz | head -1)
  scp -i ~/.ssh/id_rsa \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    \"\$TARBALL\" vagrant@${MINISTRY_IP}:${BUNDLE_REMOTE}
" || fail "scp from builder to ministry failed"
pass_step "bundle transfer (builder → ministry)"

log "Extracting, loading images, and deploying on ministry..."
vagrant ssh ministry -c "
  set -e
  rm -rf ${REMOTE}
  mkdir -p ${REMOTE}
  tar -xzf ${BUNDLE_REMOTE} -C ${REMOTE}
  cd ${REMOTE}
  grep './images/' SHA256SUMS > SHA256SUMS.images
  sha256sum -c SHA256SUMS.images
  ./load-images.sh
  sudo env NON_INTERACTIVE=1 URL_HOST=localhost EMAIL_ADMIN=admin@ministry.test \
    ./deploy.sh --non-interactive --deploy-dir /opt/openfn-lightning --yes
" || fail "deploy on ministry failed"
pass_step "load-images + deploy on ministry"

log "Verifying deployment..."
vagrant ssh ministry -c "cd /opt/openfn-lightning && sudo ./verify.sh" || fail "verify failed"
pass_step "verify"

if [[ $SKIP_ROTATE -eq 0 ]]; then
  log "Testing Postgres password rotation..."
  vagrant ssh ministry -c \
    "cd /opt/openfn-lightning && sudo ./rotate-secrets.sh --non-interactive --postgres-password" \
    || fail "rotate-secrets failed"
  pass_step "rotate-secrets"
fi

echo ""
echo "=========================================="
echo "  ALL TESTS PASSED"
echo "  builder: ${BUILDER_IP} (build)"
echo "  ministry: ${MINISTRY_IP} (deploy)"
echo "  Lightning: http://localhost:${LIGHTNING_HOST_PORT}"
echo "=========================================="
