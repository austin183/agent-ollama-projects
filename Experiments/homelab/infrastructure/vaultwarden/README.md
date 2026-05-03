# Vaultwarden (Bitwarden Compatible Password Manager)

## Overview

Vaultwarden is an unofficial, lightweight Bitwarden-compatible password vault server written in Rust. This experiment runs a self-hosted password manager accessible to all official Bitwarden clients.

## Quick Start

```bash
cd ~/homelab/infrastructure/vaultwarden
podman compose up -d
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| vaultwarden | 8086 | Web UI + API (Bitwarden protocol) |
| vaultwarden | 8086/admin | Admin panel (requires ADMIN_TOKEN) |

## Testing

```bash
# Check container is running
podman ps | grep vaultwarden

# Check health status
podman inspect homelab-vaultwarden --format '{{.State.Health.Status}}'

# Test HTTP connectivity from test client
podman exec homelab-vaultwarden-test wget --spider -q http://vaultwarden:80 -O-

# Check logs
podman logs --tail 20 homelab-vaultwarden

# Verify SQLite database
podman exec homelab-vaultwarden ls -la /data/
```

## Setup

### 1. Create the `.env` file

```bash
cd ~/homelab/infrastructure/vaultwarden
echo "ADMIN_TOKEN=$(openssl rand -hex 32)" > .env
```

This generates a random admin token required for the `/admin` panel.

### 2. Start the container

```bash
cd ~/homelab/infrastructure/vaultwarden
podman compose up -d
```

### 3. Access the admin panel

1. Open browser to `http://localhost:8086/admin`
2. Log in with the admin token (check `.env` for the value)
3. Create your first user account (signups are disabled for public access)

### 4. Configure your clients

1. Download Bitwarden clients from https://bitwarden.com/download
2. Set server URL to `http://<your-homelab-ip>:8086`
3. Log in with your credentials

## Architecture

```
[Bitwarden Clients] --> [Port 8086] --> [Vaultwarden Container]
                                      |
                                      +-- SQLite database (/data/db.sqlite3)
                                      +-- WebSocket for push notifications
```

**Data Flow:**
1. Clients connect to Vaultwarden via HTTP (port 8086)
2. All data is encrypted client-side before transmission
3. Encrypted data is stored in a single SQLite database file
4. WebSocket connection enables real-time sync across devices

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `/data/db.sqlite3` | Path to SQLite database |
| `WEBSOCKET_ENABLED` | `false` | Enable WebSocket for push notifications |
| `SIGNUPS_ALLOWED` | `true` | Allow new user registrations |
| `ADMIN_TOKEN` | (none) | Token for admin panel access |
| `TZ` | UTC | Timezone |
| `INVITATIONS_ALLOWED` | `true` | Allow users to invite others |

## Troubleshooting

- **Port 8086 conflict** - Check with `ss -tlnp | grep :8086` before starting
- **Admin token missing** - Without `ADMIN_TOKEN`, the admin panel is inaccessible
- **Signups still allowed** - Set `SIGNUPS_ALLOWED=false` to prevent public registration
- **Data persistence** - Always mount `/data` volume; SQLite file lives there
- **Healthcheck failing** - Vaultwarden needs a few seconds to start; the healthcheck has a 30s start_period

## Resource Usage

| Resource | Usage |
|----------|-------|
| RAM | ~50-80MB (SQLite mode) |
| Storage | ~10-50MB (depends on number of items stored) |
| CPU | Near zero when idle |

## Backup

```bash
# Backup the data directory
cp -r ~/homelab/infrastructure/vaultwarden/data ~/homelab/infrastructure/vaultwarden/data.backup
```

Or stop the container and copy the SQLite file:
```bash
podman compose down
cp ~/homelab/infrastructure/vaultwarden/data/db.sqlite3 ~/vaultwarden-backup.sqlite3
podman compose up -d
```

## Cleanup

```bash
# Stop the container
podman compose down

# Stop and remove all data
podman compose down -v
```
