#!/usr/bin/env bash
# Ministry server setup (Docker provider / amd64 container).
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Passwordless sudo for vagrant (deploy.sh, verify.sh use sudo).
echo "vagrant ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/vagrant
chmod 440 /etc/sudoers.d/vagrant

usermod -aG docker vagrant 2>/dev/null || true

mkdir -p /opt/openfn-lightning
chown vagrant:vagrant /opt/openfn-lightning

echo "=============================================="
echo "Ministry test host ready (linux/amd64)"
echo "  uname -m: $(uname -m)"
echo "  Receives bundle via scp from builder (192.168.56.10)"
echo "  Run: cd vagrant && ./test-airgap.sh"
echo "=============================================="
