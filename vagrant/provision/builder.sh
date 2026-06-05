#!/usr/bin/env bash
# Internet-connected amd64 build host (jump-host analogue).
set -euo pipefail

echo "vagrant ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/vagrant
chmod 440 /etc/sudoers.d/vagrant
usermod -aG docker vagrant 2>/dev/null || true

curl -sf --max-time 15 https://hub.docker.com >/dev/null \
  || echo "WARN: hub.docker.com not reachable — build may fail"

echo "=============================================="
echo "Builder host ready ($(uname -m))"
echo "  Build: cd /vagrant/openfn-distro/bundle && ./build-bundle.sh"
echo "  Output: /vagrant/openfn-distro/bundle-output/"
echo "=============================================="
