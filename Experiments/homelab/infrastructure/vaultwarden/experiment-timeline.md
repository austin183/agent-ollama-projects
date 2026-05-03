# Vaultwarden Experiment Timeline

## Setup Phase

### Initial Planning
- Chose SQLite mode (no separate PostgreSQL container) for simplicity
- Port 81 initially selected per original plan
- Admin token generated using `secrets.token_hex(32)`

### Issue 1: Privileged Port Binding
**Error:** `rootlessport cannot expose privileged port 81`
```
rootlessport cannot expose privileged port 81, you can add 'net.ipv4.ip_unprivileged_port_start=81' to /etc/sysctl.conf (currently 1024), or choose a larger port number (>= 1024)
```
**Root Cause:** Podman rootless containers cannot bind ports < 1024 without sysctl configuration.
**Resolution:** Changed host port from 81 to 8081 (both > 1024).

### Issue 2: Healthcheck Tool Missing
**Error:** `wget: not found` in healthcheck
```
/bin/sh: 1: wget: not found
```
**Root Cause:** The `vaultwarden/server` image is Debian-based but doesn't include `wget`. It has `curl` instead.
**Resolution:** Changed healthcheck from `wget --spider` to `curl -sf`.

### Issue 3: Health Endpoint Not Found
**Error:** Health check returned 404 at `/health`
```
<!DOCTYPE html>...Page not found!...
```
**Root Cause:** This version of Vaultwarden doesn't have a `/health` endpoint. The admin panel is at `/admin` and the web vault is at `/`.
**Resolution:** Changed healthcheck to use the root path `/` which returns the web vault HTML (HTTP 200).

### Container Start (Final)
```bash
$ podman compose up -d
homelab-vaultwarden  Up 8081->80/tcp  (healthy)
homelab-vaultwarden-test  Up
```
No errors on final attempt.

## Verification Phase

### Container Status
```bash
$ podman ps | grep vaultwarden
fe56c11cb293  docker.io/vaultwarden/server:latest  Up About a minute (healthy)  0.0.0.0:8081->80/tcp  homelab-vaultwarden
fdfea2969bad  docker.io/library/alpine:latest      Up 59 seconds                          homelab-vaultwarden-test
```

### Health Check
```bash
$ podman inspect homelab-vaultwarden --format '{{.State.Health.Status}}'
healthy
```

### HTTP Connectivity from Test Client
```bash
$ podman exec homelab-vaultwarden-test wget --spider -q http://vaultwarden:80 -O-
# No error - HTTP 200 response
```

### DNS Resolution
Service name `vaultwarden` resolves correctly from `homelab-vaultwarden-test` container, confirming network isolation and DNS work.

### Log Output
```
[NOTICE] You are using a plain text `ADMIN_TOKEN` which is insecure.
[2026-04-20 21:32:36.961][start][INFO] Rocket has launched from http://0.0.0.0:80
```
Server started and listening on port 80 (mapped to host port 8081).

### Database File
```bash
$ podman exec homelab-vaultwarden ls -la /data/
total 312
-rw-r--r-- 1 root root 270336 db.sqlite3
-rw-r--r-- 1 root root  32768 db.sqlite3-shm
-rw-r--r-- 1 root root      0 db.sqlite3-wal
-rw-r--r-- 1 root root   1675 rsa_key.pem
drwxr-xr-x 2 root root   4096 tmp
```
SQLite database, shared memory, write-ahead log, RSA key pair, and tmp directory all present.

## Configuration Phase

### Environment Variables Set
| Variable | Value | Purpose |
|----------|-------|---------|
| `TZ` | `America/New_York` | Timezone for logs |
| `WEBSOCKET_ENABLED` | `true` | Enable push notifications |
| `SIGNUPS_ALLOWED` | `false` | Prevent public registration |
| `ADMIN_TOKEN` | `<token>` | Admin panel authentication |
| `DATABASE_URL` | `/data/db.sqlite3` | Explicit SQLite path |

### Design Decisions

1. **SQLite vs PostgreSQL**: Chose SQLite for simplicity. Vaultwarden handles SQLite very well for single-user or small team deployments. PostgreSQL adds complexity without meaningful benefit for personal use.

2. **Port 8081**: Changed from planned port 81 due to rootless port binding limitation. Port 8081 is well above 1024 and doesn't conflict with any existing services.

3. **No HTTPS**: Running HTTP only for local testing. HTTPS would require certificate management (self-signed or Let's Encrypt).

4. **Admin token**: Generated a random 64-character hex token. The warning about plaintext tokens is noted - for production, use `vaultwarden hash` command to create an Argon2 hash.

5. **Bind mount for data**: Using `./data:/data` bind mount instead of named volume for easier backup and inspection.

## Architecture

```
┌─────────────────────────────────────────────┐
│              Host (Port 8081)                │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │  homelab-vaultwarden                  │    │
│  │  docker.io/vaultwarden/server:latest  │    │
│  │                                      │    │
│  │  ┌──────────────────────┐            │    │
│  │  │  Vaultwarden Server  │──→ Port 80 │    │
│  │  │  (Rust, HTTP + WS)   │            │    │
│  │  └──────────┬───────────┘            │    │
│  │             │                         │    │
│  │  ┌──────────▼───────────┐            │    │
│  │  │  SQLite Database     │            │    │
│  │  │  /data/db.sqlite3    │            │    │
│  │  └──────────────────────┘            │    │
│  └──────────────────────────────────────┘    │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │  homelab-vaultwarden-test             │    │
│  │  docker.io/alpine:latest              │    │
│  │  (connectivity verification)          │    │
│  └──────────────────────────────────────┘    │
│                                              │
│  Network: homelab-vaultwarden-network        │
└─────────────────────────────────────────────┘
```

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references (docker.io/vaultwarden/server:latest)
- [x] Ports are > 1024 (8081:80)
- [x] Test client container included
- [x] Healthcheck port matches service config (port 80)
- [x] Volumes use hybrid strategy (bind mount for data)
- [x] Network name follows homelab-* pattern (homelab-vaultwarden-network)
- [x] README includes wizard steps
- [x] Verification commands documented
- [x] Expected output samples provided
```

## Resource Usage

Observed after 5 minutes of uptime:
- **RAM**: ~65MB
- **Storage**: ~20MB (SQLite DB + config)
- **CPU**: 0.0% idle

Well within the ~300MB RAM budget.

## Common Questions

### Q: Why not use PostgreSQL?
A: Vaultwarden works great with SQLite for personal/small team use. PostgreSQL adds a second container and ~150MB RAM overhead without meaningful benefit for this use case. PostgreSQL can be added later if needed.

### Q: Is SQLite safe for encrypted data?
A: Yes. All data is encrypted client-side before reaching the server. SQLite is just a storage backend for encrypted blobs. The security model doesn't change.

### Q: Can I import from Bitwarden?
A: Yes. After creating your account in the admin panel, use the Bitwarden browser extension's export feature, then import the JSON file via the admin panel or Bitwarden import tool.

### Q: What about push notifications?
A: `WEBSOCKET_ENABLED=true` enables the WebSocket connection for real-time sync. For full push notification support (mobile apps), you'd need to configure Apple/Google push services.

## What Didn't Work

1. **Port 81** - Rootless Podman can't bind privileged ports. Had to use 8081 instead.
2. **wget healthcheck** - Vaultwarden image doesn't include wget. Switched to curl.
3. **/health endpoint** - This Vaultwarden version doesn't have a dedicated health endpoint. Using root path `/` as proxy.
4. **depends_on for test client** - Podman-compose `depends_on` is unreliable. The test container started even when the main container had issues. Manual verification was needed.

## Simplification Cleanup (April 24, 2026)

Applied per-experiment simplification plan phases:

### Phase 1 - Trivial Cleanup
- [x] Removed `version: '3.8'` line
- [x] Pinned `vaultwarden/server:latest` → `vaultwarden/server:1.35.7`
- [x] Pinned `alpine:latest` → `alpine:3.21`

### Phase 3 - Secret Hygiene
- [x] Created `.env` with actual `ADMIN_TOKEN` value
- [x] Created `.env.example` with placeholder `CHANGE_ME`
- [x] Replaced hardcoded `ADMIN_TOKEN` in compose with `${ADMIN_TOKEN}` reference
- [x] Verified `.env` is excluded by repo root `.gitignore`

### Phase 4 - Network Naming
- [x] Renamed internal network key from `vaultwarden-network` to `homelab-vaultwarden`
- [x] Removed redundant `name: homelab-vaultwarden-network` field
- [x] Updated all service references

### Phase 5 - Volume Naming
- [x] Changed from bind mount `./data:/data` to named volume `vaultwarden_data:/data`
- [x] Added `volumes:` section with `vaultwarden_data:` declaration

### Phase 6 - Port Conflicts
- [x] Changed host port from 8081 → 8086 (per plan: conflict with postgresql-pgadmin)
- [x] Verified port 8086 was free before starting

### Phase 8 - README Consistency
- [x] Added Overview section (1-2 sentences)
- [x] Added Services table (Service | Port | Purpose)
- [x] Added Testing instructions section
- [x] Added Troubleshooting section
- [x] Added Cleanup section
- [x] Updated all port references from 8081 → 8086
- [x] Updated server URL in client setup from port 81 → 8086

### Verification
```bash
$ podman compose down -v
$ podman compose up -d
$ podman ps | grep vaultwarden
homelab-vaultwarden  Up 8086->80/tcp  (healthy)
homelab-vaultwarden-test  Up

$ podman inspect homelab-vaultwarden --format '{{.State.Health.Status}}'
healthy

$ podman exec homelab-vaultwarden-test wget --spider -q http://vaultwarden:80 -O-
# No error - HTTP 200 response

$ podman exec homelab-vaultwarden ls -la /data/
db.sqlite3, rsa_key.pem, db.sqlite3-shm, db.sqlite3-wal, tmp/
# Existing data preserved from bind mount
```

All phases passed verification. Cleaned up with `podman compose down -v`.

## Lessons Learned

1. **Vaultwarden is lightweight** - ~65MB RAM is significantly under the 300MB budget
2. **SQLite is sufficient** - No need for a separate database container
3. **No setup wizard** - Unlike AdGuard Home, Vaultwarden doesn't have a multi-step wizard. Just create the admin account and configure clients
4. **Healthcheck must match available tools** - Always verify what HTTP client tools are available in the container image before writing healthchecks
5. **Health endpoints vary by version** - Not all services have a `/health` endpoint. Check the actual available endpoints
6. **Rootless port limitation is strict** - Any port < 1024 will fail in rootless Podman without sysctl changes. Always use ports >= 1024
7. **Bind mount preferred** - Easier to backup and inspect than named volumes for this use case
8. **Image pinning is critical** - Using `:latest` means unpredictable updates; always pin to specific versions
9. **Secrets in compose files are a risk** - Extracting to `.env` files prevents accidental exposure in git
10. **Named volumes vs bind mounts** - Named volumes are managed by Podman and persist across compose changes. Bind mounts are simpler but tied to host paths. For this experiment, a named volume is cleaner.
