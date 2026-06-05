# OpenFn Lightning — Air-gap distribution for Foo Ministry

Deployment package for installing [OpenFn Lightning](https://github.com/OpenFn/lightning) on a **single air-gapped Linux server**. This is a repo for preparing an air-gap distribution for a fictional Foo Ministry.

## Repository layout

```
bundle/           Packaging scripts, production compose, server install scripts
vagrant/          Two-host Vagrant lab (Docker provider, amd64)
RUNBOOK.md        Step-by-step guide for ministry IT
DECISIONS.md      Architecture and trade-off memo
README.md         This file
```

## Quick start

### Prerequisites

- Docker Engine + Compose v2 on the build machine
- For Vagrant tests: [Vagrant](https://www.vagrantup.com/) with the Docker provider, ~8–12 GB RAM free

### Build the bundle (internet-connected machine)

```bash
cd bundle
./build-bundle.sh
# Output: ../bundle-output/openfn-lightning-bundle-*.tar.gz
```

### Test with Vagrant

Two **linux/amd64** Vagrant hosts on a shared Docker network—a builder and an air-gapped target.

| Host | Role |
|------|------|
| `builder` (192.168.56.10) | Internet, runs `build-bundle.sh` |
| `ministry` (192.168.56.20) | Receives bundle via `scp`, load + deploy |

```bash
cd vagrant
./cleanup-vagrant.sh
./test-airgap.sh
```

Requires: Vagrant, Docker. Options: `--skip-build`, `--skip-rotate`.

After success: **http://localhost:14000**

Uses Docker-in-Docker with `vfs` storage on both hosts.

### Manual test

```bash
cd bundle && ./build-bundle.sh
mkdir -p /tmp/openfn-test && tar -xzf ../bundle-output/*.tar.gz -C /tmp/openfn-test
cd /tmp/openfn-test
sha256sum -c SHA256SUMS
./load-images.sh
sudo ./deploy.sh --non-interactive --deploy-dir /tmp/openfn-lightning --yes
sudo DEPLOY_DIR=/tmp/openfn-lightning ./verify.sh
```
