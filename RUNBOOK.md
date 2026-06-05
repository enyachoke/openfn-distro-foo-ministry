# OpenFn Lightning Air-gap Deployment Runbook

This is guide for install OpenFn Lightning on a single server with no internet access. It assumes basic Linux knowledge and that you have already installed Docker and Docker Compose v2.

## What you are installing

OpenFn Lightning on a single server with **no internet access**. It will install OpenFn lighting with it's dependt services as containers and will not install any other software on the server.

## Before you start

- **Jump host** — a machine that can reach the internet and the air-gapped server's network (used to stage the bundle)
- **Final Air-gapped server** — Ubuntu 22.04 with **Docker Engine** and **Docker Compose v2** already installed
- Bundle file: `openfn-lightning-bundle-*.tar.gz`
- At least **8 GB RAM** on the final air-gapped server, **50 GB** free disk space
- Root or sudo access on the final air-gapped server

## Step 1 — Copy the bundle to the air-gapped server

We have two options to copy the bundle to the air-gapped server:

1. **Option A — Over the network** — upload to the jump host, then `scp` to the air-gapped server
2. **Option B — USB drive** — copy to a USB stick and insert it into the air-gapped server

Both options must end with the bundle file in `/tmp/` on the air-gapped server.

### Option A — Over the network

**Upload the bundle to the jump host**

On the machine that has the bundle:

```bash
scp openfn-lightning-bundle-*.tar.gz user@jump-host:/tmp/
```

Confirm it was uploaded to the jump host:

```bash
ssh user@jump-host
ls -lh /tmp/openfn-lightning-bundle-*.tar.gz
```

**Copy from the jump host to the air-gapped server**

```bash
scp /tmp/openfn-lightning-bundle-*.tar.gz user@air-gapped-server:/tmp/
```

Confirm on the air-gapped server:

```bash
ls -lh /tmp/openfn-lightning-bundle-*.tar.gz
```

### Option B — USB drive

**On your workstation** — copy the bundle onto the USB drive:

```bash
# Plug in the USB drive, then list block devices (note the new entry, e.g. sdb1)
lsblk

sudo mkdir -p /mnt/usb
sudo mount /dev/sdb1 /mnt/usb    # replace sdb1 with your USB partition from lsblk

cp openfn-lightning-bundle-*.tar.gz /mnt/usb/
sync
sudo umount /mnt/usb
```

**On the air-gapped server** — copy the bundle to `/tmp/`:

```bash
# Plug in the USB drive, then list block devices (note the new entry, e.g. sdb1)
lsblk

sudo mkdir -p /mnt/usb
sudo mount /dev/sdb1 /mnt/usb    # replace sdb1 with your USB partition from lsblk

ls -lh /mnt/usb/openfn-lightning-bundle-*.tar.gz
cp /mnt/usb/openfn-lightning-bundle-*.tar.gz /tmp/
sync
sudo umount /mnt/usb
```

The device name (e.g. `sdb1`, `sdc1`) varies by machine and by USB port. Always check `lsblk` before mounting — do not assume `sdb1`.

If your system auto-mounts removable media, the drive may appear under `/media/` instead. List that directory:

```bash
ls /media/$USER/
cp /media/$USER/*/openfn-lightning-bundle-*.tar.gz /tmp/
```

## Step 2 — Verify the bundle integrity

```bash
cd /tmp
mkdir openfn-bundle && cd openfn-bundle
tar -xzf ../openfn-lightning-bundle-*.tar.gz
sha256sum -c SHA256SUMS
```

You must see `OK` for every file. If any line says `FAILED`, **do not continue** — re-copy the bundle.

## Step 3 — Install Lightning

```bash
cd /tmp/openfn-bundle
sudo ./deploy.sh
```

The script will ask:

1. **Deployment directory** — press Enter for default `/opt/openfn-lightning`
2. **URL_HOST** — hostname staff use in the browser (e.g. `lightning.health.gov`)
3. **EMAIL_ADMIN** — email shown as system sender
4. **Port** — press Enter for `4000`

Cryptographic secrets are **generated automatically** when you press Enter (you do not need to invent passwords). They are stored in `secrets/.env` on the server.

Installation takes several minutes (loading images, starting database, migrations).

## Step 4 — Verify success (yes / no)

```bash
cd /opt/openfn-lightning
sudo ./verify.sh
```

| Output | Meaning |
|--------|---------|
| `RESULT: PASS` | Lightning is working |
| `RESULT: FAIL — …` | Not ready — read the reason on the same line |

Open a browser on the local network: `http://<server-ip>:4000`

## Step 5 — Create your first user

Visit the registration page (if enabled) or ask your OpenFn support contact for admin setup steps.

---

## Updating Lightning

When you receive a **new bundle** for an upgrade:

1. Copy it to the air-gapped server (Step 1, Option A or B).
2. On the air-gapped server:

```bash
cd /tmp
mkdir new-bundle && cd new-bundle
tar -xzf ../openfn-lightning-bundle-NEW.tar.gz
sha256sum -c SHA256SUMS
sudo ./deploy.sh
```

If a deployment already exists, the script will:

1. Ask you to confirm (it will **stop** the running system first)
2. Keep your existing `secrets/.env`
3. Load any new images and restart services

Always run `sudo ./verify.sh` after an update.

---

## Rotating passwords

```bash
cd /opt/openfn-lightning
sudo ./rotate-secrets.sh
```

Choose option **1** to rotate only the database password (safest routine test).  
**Do not** rotate the encryption key unless OpenFn support instructs you — it invalidates stored credentials.

---

## Failure scenario: Postgres will not start (permissions)

**Symptoms**

- `verify.sh` prints `RESULT: FAIL`
- `docker compose ps` shows `postgres` restarting or exited
- Logs show “Permission denied” for `/var/lib/postgresql/data`

**Diagnose**

```bash
cd /opt/openfn-lightning
sudo docker compose logs postgres | tail -30
ls -la data/postgres
```

**Cause**

The data directory was created with the wrong owner (common if files were copied as root before first start).

**Fix**

```bash
cd /opt/openfn-lightning
sudo docker compose down
sudo chown -R 70:70 data/postgres
# Alpine Postgres image uses UID 70; if that fails, try: chown -R 999:999 data/postgres
sudo docker compose up -d
sudo ./verify.sh
```

**Prevention**

Always run `deploy.sh` once and let it create `data/postgres` — do not pre-create that folder with the wrong owner.

---

## Getting help

Note the output of:

```bash
cd /opt/openfn-lightning
sudo docker compose ps
sudo ./verify.sh
sudo docker compose logs web | tail -50
```

Send these to your OpenFn support contact.
