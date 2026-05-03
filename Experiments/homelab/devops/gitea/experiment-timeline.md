# Gitea Experiment - Timeline

**Phase:** 8A (DevOps & Git Services)  
**Date:** April 19-20, 2026  
**Status:** Complete — Fully automated setup, admin user created at startup, no wizard needed

---

## Architecture

```
                    ┌─────────────────────┐
                    │  homelab-gitea      │
                    │  (Gitea 1.26.0)     │
                    │  Web: :3000 → :3001 │
                    │  (rootless image)   │
                    └─────────┬───────────┘
                              │
                    ┌─────────▼───────────┐
                    │  homelab-gitea-      │
                    │  postgres            │
                    │  (PostgreSQL 16)     │
                    │  :5432               │
                    └─────────┬───────────┘
                              │
                    ┌─────────▼───────────┐
                    │  homelab-gitea-test  │
                    │  (Alpine)            │
                    │  connectivity check  │
                    └─────────────────────┘
                              │
                    homelab-gitea-network (bridge)
```

**Note:** SSH is currently disabled (`DISABLE_SSH=true`). The rootless image's builtin SSH
server (port 2222) may work but requires UID mapping. Consider enabling in a future session.

---

## Previous Attempts (Sessions 1-5)

### Attempt 1: Bind mount config file

**Compose config:**
```yaml
volumes:
  - gitea_data:/data
  - ./conf/gitea:/data/gitea/conf
```

**Error:** Gitea's entrypoint runs as root, then switches to the `git` user (uid 1000). The bind mount created files owned by root, and when Gitea tried to write `SECRET_KEY` into `app.ini`, it got `permission denied`.

**Logs:**
```
[F] Error saving internal token: failed to save "/data/gitea/conf/app.ini": open /data/gitea/conf/app.ini: permission denied
```

**Fix attempted:** `chmod 644` and `chown 1000:1000` on the host file. Did not work because Podman rootless containers use UID mapping — the host UID 1000 maps to root inside the container.

---

### Attempt 2: Bake config into custom image via Dockerfile

**Approach:** Create a `Dockerfile` that copies `app.ini` into the image.

```dockerfile
FROM docker.io/gitea/gitea:1.22.3
COPY conf/gitea/app.ini /data/gitea/conf/app.ini
```

**Error:** Config was baked in, but Gitea was still showing "Prepare to run install page" — meaning it wasn't reading the baked config.

**Root cause:** Gitea's `--custom-path` defaults to `{WorkPath}/custom`, not `{WorkPath}`. The config was placed at `/data/gitea/conf/app.ini` but Gitea looks for it at `/data/gitea/custom/conf/app.ini`.

---

### Attempt 3: Custom entrypoint script

**Approach:** Write an entrypoint that creates the config at the correct path, then execs `gitea web`.

```dockerfile
FROM docker.io/gitea/gitea:1.22.3
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

**Error chain:**
1. Wrong binary path — `/app/gitea/web` doesn't exist. Binary is at `/usr/local/bin/gitea`.
2. Gitea refuses to run as root (PID 1): `[F] Gitea is not supposed to be run as root.`
3. `gosu` not available in Debian-based Gitea image.
4. `apk add gosu` — package doesn't exist in Alpine repos.
5. `su -s /bin/sh gitea` — the user in the Gitea image is `git` (uid 1000), not `gitea`.

**Fix:** Changed to `su -s /bin/sh git -c "gitea web"`.

**Result:** Gitea started! But the custom config was at `/data/gitea/custom/conf/app.ini` (correct path) while Gitea was still reading from `/data/gitea/conf/app.ini` (the default baked-in location).

**Root cause:** The `GITEA_CUSTOM` environment variable or `-C` flag was needed to tell Gitea where the custom config lives.

---

### Attempt 4: Run as non-root user via compose `user` field

**Approach:** Use `user: "1000:1000"` in the compose file.

```yaml
user: "1000:1000"
```

**Error:** `s6-svscan: fatal: unable to open .s6-svscan/lock: Permission denied`

**Root cause:** The Gitea image uses s6-overlay as its init system. The s6 directory structure (`~/.s6-svscan/`) is owned by root in the image. Running as uid 1000 can't access it.

**Lesson:** You can't use `user:` override on the Gitea image — it breaks the s6 init system.

---

### Attempt 5: Stock image, no custom config

**Approach:** Remove all custom Dockerfile/entrypoint complexity. Use the stock `gitea/gitea:1.22.3` image. Let Gitea run as root (it handles the internal switch). Use the default SQLite backend initially, then migrate to PostgreSQL later.

**Status:** Containers are up and running. Gitea is serving on port 3001. The install wizard should be accessible at `http://localhost:3001`.

**Next steps needed:**
1. Complete the Gitea install wizard via browser at `http://localhost:3001`
2. Configure PostgreSQL as the database backend (or stick with SQLite for simplicity)
3. Set up the first user/admin account
4. Test SSH access on port 2223
5. Create a test repository and push/pull

---

## Session 6: Rootless Image Migration

### Why switch to rootless image?

The rootful `gitea/gitea:1.22.3` image has caused persistent issues:
- Bind-mounted config files get wrong ownership in rootless Podman
- Custom entrypoint scripts fail because Gitea's s6-overlay init system runs as root
- `user:` override in compose breaks s6 overlay
- Config path is at `/data/gitea/custom/conf/app.ini` (not intuitive)
- Version is 1.22.3 (outdated — current is 1.26.0)

Research found Gitea's official **rootless image** (`docker.gitea.com/gitea:1.26.0-rootless`) which is designed specifically for rootless/containerized setups and solves these problems natively.

---

### Key findings about the rootless image

**Image:** `docker.gitea.com/gitea:1.26.0-rootless`

**User:** Runs as `git` (uid 1000, gid 1000) — confirmed with `id` command.

**Key differences from rootful image:**
| Aspect | Rootful (1.22.3) | Rootless (1.26.0) |
|--------|-------------------|-------------------|
| Data path | `/data` | `/var/lib/gitea` |
| Config path | `/data/gitea/custom/conf/app.ini` | `/etc/gitea/app.ini` |
| SSH port | 22 (mapped to 2223) | 2222 (internal only) |
| Init system | s6-overlay | `dumb-init` + docker-entrypoint.sh |
| Default DB | SQLite | SQLite |

**Entrypoint flow:**
1. `/usr/bin/dumb-init -- /usr/local/bin/docker-entrypoint.sh`
2. `docker-entrypoint.sh` runs `/usr/local/bin/docker-setup.sh` if it exists
3. `docker-setup.sh` generates config from template using `envsubst` if config doesn't exist
4. `environment-to-ini` replaces `GITEA__SECTION__KEY` env vars in config
5. Finally: `exec /usr/local/bin/gitea -c ${GITEA_APP_INI} web`

**No s6-overlay** in the rootless image — this was the key difference that made the `user:` override work (but we don't need it since the image already runs as `git`).

**Config template at:** `/etc/templates/app.ini` — uses `$VARIABLE` syntax, substituted by `envsubst`.

**Environment variables recognized by `docker-setup.sh`:**
- `APP_NAME`, `RUN_MODE`, `RUN_USER`, `SSH_DOMAIN`, `HTTP_PORT`, `ROOT_URL`
- `DISABLE_SSH`, `SSH_PORT`, `SSH_LISTEN_PORT`, `LFS_START_SERVER`
- `DB_TYPE`, `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWD`, `INSTALL_LOCK`
- `DISABLE_REGISTRATION`, `REQUIRE_SIGNIN_VIEW`, `SECRET_KEY`
- Any `GITEA__SECTION__KEY` format (e.g., `GITEA__DATABASE__TYPE=postgres`)

---

### Attempt 6: Rootless image with baked config

**Dockerfile:**
```dockerfile
FROM docker.gitea.com/gitea:1.26.0-rootless
COPY conf/gitea/app.ini /etc/gitea/app.ini
```

**docker-compose.yml:**
```yaml
volumes:
  - gitea_data:/var/lib/gitea
  - gitea_data:/data
  - ./conf/gitea/app.ini:/etc/gitea/app.ini:rw
```

**Error 1:** `COPY --chmod=755` failed with `Operation not permitted` — Podman rootless can't set executable bit during COPY.

**Fix:** Used `COPY --chmod=755` which works in Podman 4.9.3.

**Error 2:** Gitea tries to write `JWT_SECRET` to the config file at runtime, but the bind-mounted file is root-owned in rootless Podman:
```
[F] save oauth2.JWT_SECRET failed: failed to save "/etc/gitea/app.ini": open /etc/gitea/app.ini: permission denied
```

**Fix:** Removed bind mount, generate config at runtime via entrypoint script.

**Error 3:** Gitea needs `/data` directory (for git home):
```
[F] unable to prepare git home directory /data/gitea/home, err: mkdir /data: permission denied
```

**Fix:** Added `-v gitea_data:/data` bind mount (same volume as `/var/lib/gitea`).

**Error 4:** `openssl` not available in rootless image for secret generation:
```
/entrypoint.sh: line 41: openssl: not found
```

**Fix:** Switched to `dd if=/dev/urandom | od -An -tx1 | tr -d ' \n'` for secret generation.

**Current error:** Gitea starts but fails to connect to PostgreSQL:
```
[E] ORM engine initialization attempt #1/10 failed. Error: failed to connect to database: unknown database type: 
```

The `TYPE` field is empty in the generated config. The config file shows `TYPE = postgres` but Gitea reads it as empty.

---

## Session 7: Built-in Env Var Approach — SUCCESS

### Root cause of Session 6 failure

The custom entrypoint (`work/entrypoint.sh`) was conflicting with the rootless image's
built-in `docker-entrypoint.sh`. When both run:

1. ENTRYPOINT runs: `/usr/bin/dumb-init -- /usr/local/bin/docker-entrypoint.sh`
2. CMD runs: `/entrypoint.sh`
3. Result: `docker-entrypoint.sh` receives `/entrypoint.sh` as an argument — nonsensical

The `docker-entrypoint.sh` runs `docker-setup.sh` which:
1. Copies template from `/etc/templates/app.ini` → `/etc/gitea/app.ini`
2. Runs `envsubst` to substitute `$VARIABLE` placeholders
3. Runs `environment-to-ini` to replace `GITEA__SECTION__KEY` env vars

The custom entrypoint then overwrote this config, but with bugs (wrong heredoc quoting,
empty TYPE field, etc.).

### Solution: Remove custom entrypoint, use built-in env vars

The rootless image's `docker-setup.sh` already supports two mechanisms:
- `$VARIABLE` in template → substituted by `envsubst` (for secrets like SECRET_KEY)
- `GITEA__SECTION__KEY=value` env vars → replaced by `environment-to-ini` (for config)

**Changes made:**
1. Deleted `Dockerfile` and `work/entrypoint.sh`
2. Changed `GITEA__DATABASE__TYPE=postgres` → `GITEA__DATABASE__DB_TYPE=postgres`
   (the template has `DB_TYPE = sqlite3` as default; `TYPE` is a separate field)
3. Let Gitea generate secrets automatically (empty SECRET_KEY is fine — Gitea generates on first run)

### Key finding: DB_TYPE vs TYPE

The rootless image's template has:
```ini
[database]
PATH = /var/lib/gitea/data/gitea.db
DB_TYPE = sqlite3
```

Setting `GITEA__DATABASE__TYPE=postgres` added `TYPE = postgres` as a SEPARATE field.
Gitea reads `DB_TYPE` to determine the database backend, not `TYPE`.

**Fix:** Use `GITEA__DATABASE__DB_TYPE=postgres` to override the template's default.

### Current config (generated by docker-setup.sh)
```ini
[database]
PATH = /var/lib/gitea/data/gitea.db
DB_TYPE = postgres
HOST = postgres:5432
NAME = gitea
USER = gitea
PASSWD = gitea_secret
SSL_MODE = disable

[server]
HTTP_PORT = 3000
ROOT_URL = http://localhost:3001/
DISABLE_SSH = true
START_SSH_SERVER = false

[security]
INSTALL_LOCK = false
SECRET_KEY =         # empty — Gitea generates on install
```

### Container Status
```
homelab-gitea            Up (starting)  0.0.0.0:3001->3000/tcp
homelab-gitea-postgres   Up (healthy)
homelab-gitea-test       Up
```

### What's Working
- PostgreSQL 16: healthy, database `gitea` created with user `gitea`
- Gitea 1.26.0-rootless: running, DB_TYPE=postgres, install page accessible
- Web UI: http://localhost:3001 shows "Installation - Gitea" page
- Test client: can reach both services by name
- Config generated correctly at `/etc/gitea/app.ini`
- No custom Dockerfile or entrypoint needed

### What's NOT Working
- **Install wizard not completed:** Still showing installation page
- **SSH:** Disabled (DISABLE_SSH=true) — rootless image's builtin SSH may have UID issues
- **Secrets:** SECRET_KEY, JWT_SECRET are empty in config (will be generated on install)

### Next Steps
1. Complete the Gitea install wizard at http://localhost:3001
   - The install wizard will create the admin user and initialize the PostgreSQL database
   - SECRET_KEY, JWT_SECRET, INTERNAL_TOKEN will be generated and saved to config
   - INSTALL_LOCK will be set to true automatically
2. After install, verify: `podman exec homelab-gitea cat /etc/gitea/app.ini`
3. Test repository creation and git clone/push
4. Consider enabling SSH (requires UID mapping for builtin SSH server)

---

## Key Findings & Lessons

### 1. Rootless image has different paths
- Data: `/var/lib/gitea` (not `/data`)
- Config: `/etc/gitea/app.ini` (not `/data/gitea/custom/conf/app.ini`)
- SSH port: 2222 (not 22) — only internal SSH supported in rootless

### 2. Rootless image has no s6-overlay
- Uses `dumb-init` + `docker-entrypoint.sh` + `docker-setup.sh`
- Config generation via `envsubst` from template at `/etc/templates/app.ini`
- `environment-to-ini` replaces `GITEA__SECTION__KEY` env vars

### 3. Config file must be writable at runtime
- Gitea writes `JWT_SECRET` to config on first run
- Bind-mounted files are root-owned in rootless Podman → permission denied
- Solution: generate config at runtime via entrypoint, or use env vars

### 4. `/data` volume needed for git home
- Rootless image creates git home at `/data/gitea/home`
- Must mount a volume to `/data` even though data lives in `/var/lib/gitea`

### 5. `dd`/`od`/`tr` available for secret generation
- `openssl` not available in rootless image
- `dd if=/dev/urandom bs=32 count=1 | od -An -tx1 | tr -d ' \n'` works

### 6. `COPY --chmod=755` works in Podman 4.9.3
- `RUN chmod +x` fails in rootless builds
- `COPY --chmod=755` is the correct approach

### 7. `environment-to-ini` may overwrite config values
- The `docker-setup.sh` script calls `environment-to-ini` which replaces `GITEA__SECTION__KEY` patterns
- This could be overwriting the `TYPE` field if an empty `GITEA__DATABASE__TYPE` env var is set

### 8. DB_TYPE vs TYPE (Session 7)
- The rootless image template uses `DB_TYPE` (not `TYPE`) for database backend selection
- Setting `GITEA__DATABASE__TYPE=postgres` adds a separate `TYPE` field that Gitea ignores
- Must use `GITEA__DATABASE__DB_TYPE=postgres` to override the template's `sqlite3` default

### 9. Custom entrypoint conflicts with built-in setup (Session 7)
- Overriding CMD with a custom script causes the ENTRYPOINT to receive it as an argument
- The rootless image's `docker-entrypoint.sh` is designed to work without overrides
- Use env vars instead of custom entrypoint scripts

---

## What Didn't Work

| Approach | Why it failed |
|----------|--------------|
| Bind mount config file | Root-owned files can't be written by Gitea's internal user in rootless Podman |
| Bake config into image at wrong path | Gitea looks in `custom/conf/app.ini`, not `conf/app.ini` |
| Custom entrypoint with gosu | gosu not available in Debian-based Gitea image |
| Custom entrypoint with `su` | Needed correct username (`git`, not `gitea`) |
| `GITEA_CUSTOM` env var | Didn't resolve the custom path correctly |
| `user: "1000:1000"` in compose | Breaks s6-overlay init system (rootful image only) |
| `RUN chmod +x` in Dockerfile | Fails in rootless Podman builds |
| `openssl` for secret generation | Not available in rootless image |
| `COPY --chmod=755` (earlier attempt) | Failed on older Podman version, works on 4.9.3 |
| Custom entrypoint overriding CMD | Conflicts with rootless image's built-in docker-entrypoint.sh |
| `GITEA__DATABASE__TYPE=postgres` | Template has `DB_TYPE` not `TYPE`; Gitea reads `DB_TYPE` for backend selection |

---

## Verification

### Connectivity tests
```bash
# From test client, Gitea should respond with install page
podman exec homelab-gitea-test wget -qO- --timeout=5 http://gitea:3000/ | head -5

# From test client, PostgreSQL should be reachable
podman exec homelab-gitea-test sh -c 'echo > /dev/tcp/postgres/5432 && echo "PostgreSQL reachable"'

# From host, Gitea web UI should be accessible
# Open: http://localhost:3001

# Check Gitea logs
podman logs homelab-gitea

# Check Gitea internal log file
podman exec homelab-gitea cat /var/lib/gitea/data/log/gitea.log | tail -20

# Check generated config
podman exec homelab-gitea cat /etc/gitea/app.ini

# Check database type in config
podman exec homelab-gitea sh -c 'grep -A6 "\[database\]" /etc/gitea/app.ini'
```

### Expected output after Session 7
```
# Gitea logs should show:
[I] Prepare to run install page
[I] Listen: http://0.0.0.0:3000

# Config database section:
[database]
PATH = /var/lib/gitea/data/gitea.db
DB_TYPE = postgres
HOST = postgres:5432
NAME = gitea
USER = gitea
PASSWD = gitea_secret

# Web UI: http://localhost:3001 shows "Installation - Gitea: Git with a cup of tea"
```

---

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references
- [x] Ports are > 1024 (3001)
- [x] Test client container included
- [x] Healthcheck port matches service config
- [x] Volumes use hybrid strategy (named volumes for data)
- [x] Network name follows homelab-* pattern (homelab-gitea-network)
- [ ] README includes wizard steps (needs completion)
- [x] Verification commands documented
- [x] Expected output samples provided
- [x] Database connection working (DB_TYPE=postgres, PostgreSQL healthy)
- [x] Web UI accessible (http://localhost:3003 shows login page)
- [ ] SSH clone works (SSH disabled for now)
- [x] Install wizard skipped via INSTALL_LOCK=true
- [x] Admin user created automatically at startup
- [ ] Test repository created and git clone/push verified
```

---

## Lessons Learned (Session 7)

### What worked
- **Removing custom entrypoint entirely** — the rootless image's built-in setup handles config generation
- **Using `GITEA__SECTION__KEY` env vars** — clean, no Dockerfile needed
- **Using `GITEA__DATABASE__DB_TYPE=postgres`** — correctly overrides the template's `sqlite3` default
- **Letting Gitea generate secrets** — empty SECRET_KEY is fine, Gitea generates on first run

### What didn't work
- **Custom entrypoint + CMD override** — conflicts with rootless image's docker-entrypoint.sh
- **`GITEA__DATABASE__TYPE=postgres`** — wrong field name; template uses `DB_TYPE`
- **Heredoc-based config generation** — fragile, prone to quoting issues

### Key insight
The rootless image's `docker-setup.sh` is designed to be used with environment variables.
There's no need for custom Dockerfiles or entrypoint scripts. The two mechanisms are:

1. **Template substitution:** `$VARIABLE` in `/etc/templates/app.ini` → `envsubst`
   - Used for: SECRET_KEY, JWT_SECRET, INTERNAL_TOKEN (can be empty, Gitea generates)
2. **Env var injection:** `GITEA__SECTION__KEY=value` → `environment-to-ini`
   - Used for: DB_TYPE, HOST, USER, PASSWD, DISABLE_SSH, INSTALL_LOCK, etc.

---

## Open Questions for Next Session

1. **Install wizard completion:** Need to complete the wizard at http://localhost:3001 to create admin user and initialize PostgreSQL database.

2. **SSH:** Disabled for now. Rootless image's builtin SSH server (port 2222) may work but requires UID mapping. Consider enabling in a future session.

3. **ROOT_URL:** Currently `http://localhost:3001/` — works for browser on this machine. For LAN access, users would need `http://<homelab-ip>:3001/`.

4. **PostgreSQL password:** `gitea_secret` is weak. Should be changed to a stronger password in a production setup.

5. **Secrets generation:** SECRET_KEY, JWT_SECRET, INTERNAL_TOKEN are empty in the generated config. Gitea generates these during install wizard completion. Verify they're populated after install.

---

## Resource Usage

| Container | RAM (est.) | Storage (est.) |
|-----------|-----------|----------------|
| Gitea 1.26.0-rootless | ~50-100MB | ~100MB (fresh install) |
| PostgreSQL 16 | ~80-120MB | ~15MB (empty DB) |
| Test client | ~2MB | ~5MB (Alpine) |
| **Total** | **~170MB** | **~120MB** |

Well within the 400MB RAM budget from the experiment plan.

---

## Rollback Plan

If the rootless image approach doesn't work:

1. Revert `docker-compose.yml` to use `image: docker.io/gitea/gitea:1.22.3`
2. Remove `build: .` and Dockerfile
3. Use stock image with install wizard (no baked config)
4. Configure PostgreSQL via web UI at `http://localhost:3001`

This fallback is viable because the rootful image does run — it just can't connect to PostgreSQL without manual wizard configuration.

---

---

## Session 8: README Automation — Skip Install Wizard

**Date:** April 25, 2026  
**Goal:** Eliminate manual install wizard step per `agent_docs/plans/readme-automation.md`

### Research: docker-setup.sh internals

Pulled the rootless image and inspected `/usr/local/bin/docker-setup.sh`:

```bash
docker-setup.sh flow:
1. Creates HOME, GITEA_CUSTOM, GITEA_TEMP dirs
2. If ${GITEA_APP_INI} doesn't exist:
   a. Creates config dir
   b. If SECRET_KEY is set and INSTALL_LOCK is empty → sets INSTALL_LOCK=true
   c. Runs envsubst on /etc/templates/app.ini → ${GITEA_APP_INI}
3. Runs environment-to-ini to apply GITEA__SECTION__KEY env vars
```

**Key findings:**
- `docker-setup.sh` only generates config ONCE (checks `if [ ! -f ${GITEA_APP_INI} ]`)
- Setting `SECRET_KEY` env var auto-enables `INSTALL_LOCK=true`
- Config file is written to `/etc/gitea/app.ini`
- `environment-to-ini` runs on every start, applying `GITEA__SECTION__KEY` vars

### Test: INSTALL_LOCK=true with SECRET_KEY

Started Gitea with `INSTALL_LOCK=true` + `SECRET_KEY=testkey123`:
- DB schema was created successfully (ORM engine initialization successful)
- Gitea started and served HTTP on port 3000
- No install wizard shown — goes straight to login page
- All DB tables created, no errors

### Test: Admin user creation via CLI

Ran `gitea admin user create` inside the container:
```bash
podman exec homelab-gitea-test-run gitea admin user create \
  --username admin \
  --password adminpassword123 \
  --email admin@example.com \
  --admin \
  --must-change-password=false
```

**Result:** `New user 'admin' has been successfully created!`

### Approach: Init container with /install POST

The plan is to use an init container that POSTs to Gitea's `/install` endpoint.
The `/install` form accepts these fields:
- `db_type`, `host`, `name`, `user`, `passwd` (database)
- `install_lock` (boolean)
- Admin user fields

**Alternative:** Pre-seed `SECRET_KEY` + `INSTALL_LOCK=true` in compose, then use init
container to exec into gitea and run `gitea admin user create`.

### Podman socket not available

Tried mounting the Podman socket into the init container for `podman exec` but
`~/.local/share/containers/podman/podman.sock` doesn't exist. The init container
will need to use HTTP API instead.

### Next steps (paused)

1. Test `/install` POST endpoint from init container
2. If POST works, create init-gitea.sh with curl POST to `/install`
3. If POST doesn't work, try pre-seeding SECRET_KEY + init container execs into gitea
4. Update docker-compose.yml with init service
5. Update .env.example with admin credentials
6. Update README.md

---

## Session 9: Entrypoint Wrapper — Full Automation Success

**Date:** April 25, 2026  
**Goal:** Fully automated Gitea setup — no manual wizard, admin user created at startup

### Approach: Entrypoint wrapper

Instead of an init container (which can't exec into Gitea without Podman socket), use a
wrapper script that:

1. Runs the original `docker-entrypoint.sh` in background
2. Polls `/api/healthz` until Gitea is ready
3. Creates admin user via `gitea admin user create` CLI
4. Waits for the entrypoint process (keeps container alive)

**Dockerfile:**
```dockerfile
FROM docker.gitea.com/gitea:1.26.0-rootless
COPY --chmod=755 work/entrypoint.sh /usr/local/bin/entrypoint-wrapper.sh
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/entrypoint-wrapper.sh"]
```

**Compose changes:**
- `image:` → `build: .`
- `GITEA__SECURITY__INSTALL_LOCK=true` (skips wizard)
- Added `GITEA_ADMIN_USER`, `GITEA_ADMIN_PASSWORD`, `GITEA_ADMIN_EMAIL` env vars

### Errors encountered

**Error 1: Wrong health endpoint** — `/healthz` returns 404 in Gitea 1.26.0. Correct endpoint is `/api/healthz`.

**Error 2: Wrong port in wrapper** — Used `GITEA__SERVER__ROOT_URL` (`http://localhost:3003/`) for health checks, but inside the container Gitea listens on port 3000. Fixed to use `GITEA__SERVER__HTTP_PORT` instead.

### Results

**All containers healthy:**
```
homelab-gitea           Up (healthy)  0.0.0.0:3003->3000/tcp
homelab-gitea-postgres  Up (healthy)
homelab-gitea-test      Up
```

**Admin user created automatically:**
```
ID   Username Email             IsActive IsAdmin
1    admin    admin@example.com true     true
```

**Secrets generated:**
- `SECRET_KEY`: auto-generated by wrapper (via `dd`/`od`/`tr`)
- `INTERNAL_TOKEN`: auto-generated by Gitea on first run
- `JWT_SECRET`: auto-generated by Gitea on first run
- `INSTALL_LOCK`: set to `true`

**API auth works:** `curl -u admin:adminpassword123 http://localhost:3003/api/v1/user` → 200

### Key findings

1. **Gitea 1.26.0 health endpoint is `/api/healthz`** — not `/healthz` or `/ping`
2. **`docker-entrypoint.sh` must run with no arguments** — passing args causes it to run `envsubst` on them
3. **`GITEA__SERVER__ROOT_URL` is for external access** — inside container, use `HTTP_PORT`
4. **`gitea admin user create` works post-startup** — no need for init-before-start patterns
5. **`set -e` is important** — without it, failed `grep` in the wrapper would not exit

### What changed from Session 8

| Aspect | Session 8 plan | Session 9 implementation |
|--------|---------------|-------------------------|
| Init method | Init container with HTTP POST | Entrypoint wrapper with CLI |
| Admin creation | `/install` API endpoint | `gitea admin user create` |
| Podman socket | Needed (unavailable) | Not needed |
| Complexity | Multi-service compose | Single Dockerfile + wrapper |

---

*Last updated: April 25, 2026 — Session 9 (complete)*
*Status: Fully automated — `podman compose up -d` is the only step needed*
