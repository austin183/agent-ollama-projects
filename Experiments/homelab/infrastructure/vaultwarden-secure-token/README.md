# Vaultwarden Secure ADMIN_TOKEN (Argon2 PHC)

## Overview

This experiment demonstrates how to secure the Vaultwarden `ADMIN_TOKEN` using an Argon2id PHC (Password Hashing Configuration) string, generated automatically by an initializer container. The plaintext password is hashed at startup and passed to Vaultwarden via a shared volume, eliminating the plaintext token warning.

## Services

| Service | Port | Purpose |
|---------|------|---------|
| init | (none) | One-shot container that hashes the plaintext password with argon2 |
| vaultwarden | 8087 | Web UI + API (Bitwarden protocol) |
| vaultwarden | 8087/admin | Admin panel (requires ADMIN_TOKEN) |

## Quick Start

```bash
cd ~/homelab/infrastructure/vaultwarden-secure-token
cp .env.example env
podman compose up -d --build
```

## Testing

```bash
# Check containers are running
podman ps --filter name=homelab-vaultwarden-secure-token

# Check health status
podman inspect homelab-vaultwarden-secure-token --format '{{.State.Health.Status}}'
# Expected: healthy

# Verify ADMIN_TOKEN is a PHC string (not plaintext)
podman exec homelab-vaultwarden-secure-token sh -c 'cat /proc/1/environ' | tr '\0' '\n' | grep ADMIN
# Expected: ADMIN_TOKEN=$argon2id$v=19$m=65540,t=3,p=4$...

# Check init container generated the token
podman logs homelab-vaultwarden-secure-token-init
# Expected: PHC string written to /shared/phc-token

# Check no plaintext warning in vaultwarden logs
podman logs homelab-vaultwarden-secure-token | grep -i "plain text"
# Expected: no output (empty means no warning)

# Test admin page connectivity
podman exec homelab-vaultwarden-secure-token-test wget --spider -q http://vaultwarden:80/admin && echo "OK"
```

## How It Works

An initializer container hashes the plaintext password before Vaultwarden starts:

1. `.env` contains `PLAINTEXT_PASSWORD=your-password`
2. The `init` container (Alpine + argon2) reads the password, hashes it with Argon2id (Bitwarden defaults: m=65540, t=3, p=4), and writes the PHC string to a shared volume
3. Vaultwarden's entrypoint reads the PHC string from the shared volume and exports it as `ADMIN_TOKEN`
4. Vaultwarden starts with the hashed token — no plaintext warning

## Architecture

```
[init container] --(ARGON2)--> [phc_data volume] --(PHC string)--> [vaultwarden entrypoint]
                                                                              |
                                                                              +-- ADMIN_TOKEN=$argon2id$...
                                                                              +-- SQLite database (/data/db.sqlite3)
```

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `PLAINTEXT_PASSWORD` | (required) | Password to hash for admin access |
| `DATABASE_URL` | `/data/db.sqlite3` | Path to SQLite database |
| `WEBSOCKET_ENABLED` | `false` | Enable WebSocket for push notifications |
| `SIGNUPS_ALLOWED` | `true` | Allow new user registrations |
| `TZ` | UTC | Timezone |

## Troubleshooting

- **Port 8087 conflict** - Check with `ss -tlnp | grep :8087` before starting
- **Init container fails with permission denied** - Rootless Podman doesn't preserve execute bits on bind mounts; scripts run through `sh`
- **Warning persists** - Run `podman compose down -v` to clear stale volumes, then `podman compose up -d --build`
- **Admin login fails** - Use the password from `PLAINTEXT_PASSWORD` in `.env`, not the PHC string

## Resource Usage

| Resource | Usage |
|----------|-------|
| RAM | ~7MB (vaultwarden idle) |
| Storage | ~10-50MB (depends on vault contents) |
| CPU | Near zero when idle |

## Cleanup

```bash
# Stop the container
podman compose down

# Stop and remove all data
podman compose down -v
```
