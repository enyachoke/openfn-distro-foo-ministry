# Deployment decisions — OpenFn Ministry air-gap bundle

## 1. Image handling

**Approach:** `docker save` on the build machine → transfer tarball → `docker load` on the ministry server.

**Trade-offs considered**


| Option                                | Pros                                     | Cons                                                               |
| ------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------ |
| `docker save` / `load`                | Simple, no extra services, works offline | Large files; each host needs a full reload on upgrade              |
| Local registry (Harbor, distribution) | Easier incremental pulls at scale        | Another system to patch, backup, and secure; overkill for one host |
| `docker import` from tar              | —                                        | Loses image history/tags; harder to audit                          |


**Why save/load:** This deployment is a **single server** without Kubernetes or Swarm. Scripts and compose must be copied to the site anyway, so a registry does not remove transfer work—it adds a component the IT focal point must operate. Save/load matches “everything on disk before go-live” and is easy to verify with `SHA256SUMS`.

**Version source of truth:** Only `[bundle/docker-compose.yml](bundle/docker-compose.yml)`. `build-bundle.sh` parses image references from that file—never hardcoded tags in the build script.

**At 20 ministries:** Build one bundle per release in CI; optional central registry only if many sites need frequent patch rollouts on the same network. Otherwise ship updated tarballs per site.

---

## 2. Secrets

**Approach**

- **First deploy:** `deploy.sh` auto-generates `SECRET_KEY_BASE`, `PRIMARY_ENCRYPTION_KEY`, worker RSA keys, and Postgres password; prompts only for `URL_HOST`, `EMAIL_ADMIN`, and port.
- **Storage:** `secrets/.env` (mode `600`) + `config.env` (mode `644`), referenced via Compose `env_file`. A merged project `.env` is written for `${VAR}` interpolation in `docker-compose.yml`.
- **Rotation:** `rotate-secrets.sh` — Postgres via `ALTER USER`; app secrets with explicit warnings about encryption key impact.

**Rotation notes**

- Postgres password: container stays up; web/worker stopped briefly; `DATABASE_URL` updated to match.
- `PRIMARY_ENCRYPTION_KEY` rotation: **invalidates** encrypted credentials at rest—documented warning in script.

**If we have to deal with 20 ministries**

Each site is an independent single-server deployment. `deploy.sh` and `rotate-secrets.sh` already auto-generate secrets locally, so there is no need for a central secrets vault or national key-management platform across ministries—the same bundle and scripts work at every site with per-site `secrets/.env` created on first install.

Operational focus at scale is repeating the bundle transfer and update flow per site, not synchronizing secrets between sites.

Central secret management only becomes necessary if the architecture changes to **horizontal scaling** (multiple Lightning or worker nodes that must share the same `SECRET_KEY_BASE`, worker keys, and database credentials). That is out of scope for this design.

---

## 3. Updates

**Patch (e.g. v2.16.3 → v2.16.4)**

1. Build new bundle on internet-connected machine (`build-bundle.sh`).
2. Transfer + `sha256sum -c SHA256SUMS`.
3. Run `deploy.sh` on ministry server (confirms stop, preserves secrets).
4. Script loads new image tars, runs `Lightning.Release.migrate()`, `verify.sh`.

**Minor (e.g. v2.16 → v2.17)**

Same steps; higher risk of DB migrations or env var changes—read release notes before bundling. Test in Vagrant lab first.

**IT focal point difference:** Patch updates are usually drop-in image swaps. Minor updates may need new environment variables—check `MANIFEST.txt` and OpenFn release notes bundled with the new tarball.

---

## 4. Observability
Considering the server is air-gapped and we cannot push telemetry out, we will not be able to use any external monitoring services. We will only be able to monitor the server locally.  Or over the jump host if we have SSH access to the server. For that we can have;

**Minimum useful monitoring on the server**

| Check | How |
| ----- | --- |
| End-to-end health | Cron every 5 minutes: `/opt/openfn-lightning/verify.sh` (containers, Postgres, `/health_check`) |
| Disk space | Daily `df -h` on `/` and `/opt`; alert locally if use exceeds ~85% |
| Container restarts | `docker compose ps` in the same cron job; non-running `postgres` / `web` / `worker` → fail |
| Logs | Docker `json-file` driver with `max-size` / `max-file` in compose to cap disk growth |

All of the above runs **on the air-gapped host only**—no external dependencies.

**Remote checks via the jump host**

```bash
ssh -J user@jump-host user@air-gapped-server \
  'cd /opt/openfn-lightning && sudo ./verify.sh'
```

`verify.sh` already prints `RESULT: PASS` or `RESULT: FAIL` with a reason—suitable for parsing by a cron wrapper that emails or pages OpenFn on non-zero exit. The same tunnel can be used ad hoc for `docker compose ps` and `docker compose logs web --since 1h` during incident response.