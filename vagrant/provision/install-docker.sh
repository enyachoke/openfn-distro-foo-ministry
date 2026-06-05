#!/usr/bin/env bash
# Install Docker Engine + Compose v2 from Docker's official apt repository.
set -euo pipefail

in_container() {
  [[ -f /.dockerenv ]] || grep -Eq 'docker|container' /proc/1/cgroup 2>/dev/null
}

configure_dind_storage() {
  # Docker-in-Docker (Vagrant docker provider): overlay-on-overlay fails with
  # "operation not permitted" / "invalid argument". vfs is slower but works.
  if ! in_container; then
    return 0
  fi
  echo "Configuring vfs storage driver for Docker-in-Docker..."
  mkdir -p /etc/docker
  cat >/etc/docker/daemon.json <<'EOF'
{
  "storage-driver": "vfs"
}
EOF
  systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null || true
  sleep 3
}

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  echo "Docker already installed: $(docker --version)"
  configure_dind_storage
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

arch="$(dpkg --print-architecture)"
codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-jammy}")"
echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable" \
  >/etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker
configure_dind_storage
