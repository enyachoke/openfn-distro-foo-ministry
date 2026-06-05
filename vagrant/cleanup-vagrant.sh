#!/usr/bin/env bash
# Tear down Vagrant Docker lab state and free ports/containers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_NET="openfn-vagrant-lab"

log() { echo "[cleanup] $*"; }

cd "$SCRIPT_DIR"

for vm in builder ministry; do
  log "Stopping ${vm}..."
  vagrant halt "$vm" 2>/dev/null || true
  log "Destroying ${vm}..."
  vagrant destroy -f "$vm" 2>/dev/null || true
done

log "Removing Vagrant metadata..."
rm -rf "${SCRIPT_DIR}/.vagrant"

if command -v docker >/dev/null 2>&1; then
  for name in openfn-builder openfn-ministry builder ministry; do
    cid="$(docker ps -aq --filter "name=${name}" 2>/dev/null | head -1 || true)"
    if [[ -n "$cid" ]]; then
      log "Removing container ${name} (${cid})..."
      docker rm -f "$cid" 2>/dev/null || true
    fi
  done
  log "Removing Docker network ${DOCKER_NET}..."
  docker network rm "$DOCKER_NET" 2>/dev/null || true
fi

log "Done. Run ./test-airgap.sh to start a fresh test."
