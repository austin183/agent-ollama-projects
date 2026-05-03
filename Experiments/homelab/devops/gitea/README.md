# Gitea Experiment

A rootless Gitea 1.26.0 instance running on Podman with PostgreSQL 16 backend. Provides self-hosted Git services with a web UI, issue tracking, and CI/CD hooks.

## Quick Links

- **Web UI:** http://localhost:3003
- **PostgreSQL:** `postgres:5432` (internal network only)

## Services

| Service | Port | Purpose |
|---------|------|---------|
| Gitea | 3003:3000 | Web UI and Git HTTPS |
| PostgreSQL 16 | 5432 (internal) | Database backend |
| Test Client | — | Connectivity verification |

## Architecture

```
                     ┌─────────────────────┐
                     │  homelab-gitea      │
                     │  (Gitea 1.26.0)     │
                      │  Web: :3000 → :3003 │
                     │  (custom image)     │
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

**Note:** SSH is currently disabled. The rootless image's builtin SSH server
supports internal connections only. SSH clone/push is not available.

## Initial Setup (One-Time)

### Copy and configure `.env`

```bash
cp .env.example .env
# Edit .env with your desired database password and admin credentials
```

The `.env` file controls:
- `GITEA_DB_PASSWORD` — PostgreSQL password
- `GITEA_ADMIN_USER` — Admin username
- `GITEA_ADMIN_PASSWORD` — Admin password
- `GITEA_ADMIN_EMAIL` — Admin email

### Start the containers

```bash
cd ~/homelab/devops/gitea
podman compose up -d
```

Wait ~30 seconds for the image to build, PostgreSQL to initialize, and Gitea to start.
The custom entrypoint wrapper handles everything automatically:

1. Builds a custom image from `Dockerfile` (wraps the rootless Gitea image)
2. Starts PostgreSQL and waits for it to be healthy
3. Generates a `SECRET_KEY` and applies all `GITEA__*` environment variables
4. Creates the admin user via `gitea admin user create`
5. Locks the installation (`INSTALL_LOCK=true`)

### Log in

Open http://localhost:3003 in a browser and log in with the admin credentials
from your `.env` file. No install wizard is needed — the setup is fully automated.

## Managing the Service

### Start/Stop

```bash
cd ~/homelab/devops/gitea

# Start
podman compose up -d

# Stop
podman compose down

# Stop and delete all data (⚠️ destructive)
podman compose down -v
```

### View Logs

```bash
# Gitea logs
podman logs -f homelab-gitea

# PostgreSQL logs
podman logs -f homelab-gitea-postgres

# Both
podman compose logs -f
```

### Check Status

```bash
# All containers
podman ps --filter name=homelab-gitea

# Resource usage
podman stats --no-stream homelab-gitea homelab-gitea-postgres
```

### Verify Database Connection

```bash
# Check that Gitea is using PostgreSQL (not SQLite)
podman exec homelab-gitea sh -c 'grep -A6 "\[database\]" /etc/gitea/app.ini'

# Expected output:
# [database]
# PATH = /var/lib/gitea/data/gitea.db
# DB_TYPE = postgres
# HOST = postgres:5432
# NAME = gitea
# USER = gitea
# PASSWD = <your DB password from .env>
```

### Backup

```bash
# Gitea data (repositories, uploads, sessions, logs)
tar czf ~/backups/gitea-data-$(date +%Y%m%d).tar.gz -C ~/.local/share/containers/storage/volumes/gitea_gitea_gitea_data _data

# PostgreSQL data
pg_dump -h localhost -U gitea gitea > ~/backups/gitea-db-$(date +%Y%m%d).sql
```

## Configuration

### Environment Variables

All Gitea configuration is done via environment variables in `docker-compose.yml`.
The rootless image's `docker-setup.sh` translates these into `/etc/gitea/app.ini`.

Key variables:

| Variable | Current Value | Description |
|----------|--------------|-------------|
| `GITEA__DATABASE__DB_TYPE` | `postgres` | Database backend |
| `GITEA__DATABASE__HOST` | `postgres:5432` | PostgreSQL connection |
| `GITEA__DATABASE__NAME` | `gitea` | Database name |
| `GITEA__DATABASE__USER` | `gitea` | Database user |
 | `GITEA__DATABASE__PASSWD` | `${GITEA_DB_PASSWORD}` (from `.env`) | Database password |
| `GITEA__SERVER__ROOT_URL` | `http://localhost:3003/` | Public-facing URL |
| `GITEA__SERVER__DISABLE_SSH` | `true` | Disable SSH (rootless limitation) |
| `GITEA__SECURITY__INSTALL_LOCK` | `true` | Skips install wizard (setup is automated) |
| `GITEA__SERVICE__DISABLE_REGISTRATION` | `true` | No self-registration |
| `GITEA__MAILER__ENABLED` | `false` | No email notifications |
| `GITEA_ADMIN_USER` | `${GITEA_ADMIN_USER}` (from `.env`) | Admin username for auto-setup |
| `GITEA_ADMIN_PASSWORD` | `${GITEA_ADMIN_PASSWORD}` (from `.env`) | Admin password for auto-setup |
| `GITEA_ADMIN_EMAIL` | `${GITEA_ADMIN_EMAIL}` (from `.env`) | Admin email for auto-setup |

### Changing Configuration After Install

The entrypoint wrapper runs `gitea admin user create` on every startup. If the admin user
already exists, the command fails harmlessly with a warning in the logs.

To change Gitea config values, use the web UI (Settings → General, etc.) or edit
`/etc/gitea/app.ini` inside the container:

```bash
# Access the config file via a temporary container
podman run --rm -it -v gitea_gitea_gitea_data:/data docker.io/alpine:latest sh
# Then: cat /data/gitea/conf/app.ini
```

### Changing the PostgreSQL Password

```bash
# Stop containers
podman compose down

# Update .env
# GITEA_DB_PASSWORD=new_password

# Restart
podman compose up -d
```

### Changing the Web Port

Edit the port mapping in `docker-compose.yml`:

```yaml
ports:
   - "3003:3000/tcp"  # Change 3003 to your desired host port
```

Also update `GITEA__SERVER__ROOT_URL` to match.

## Troubleshooting

### I want to reset and start fresh

```bash
podman compose down -v   # deletes all data
podman compose up -d
```

### Gitea won't connect to PostgreSQL

```bash
# Check PostgreSQL is healthy
podman ps --filter name=homelab-gitea-postgres

# Check PostgreSQL logs
podman logs homelab-gitea-postgres

# Verify Gitea can reach PostgreSQL
podman exec homelab-gitea wget -qO- --timeout=5 http://postgres:5432
```

### Port conflict on 3003

```bash
# Check what's using port 3003
ss -tlnp | grep 3003

# Change the port in docker-compose.yml
ports:
  - "3004:3000/tcp"  # Use a different port
```

### Gitea is slow to start

The healthcheck has a 60s start period. Gitea can take 20-40 seconds on first start
while it generates cryptographic keys, initializes the database, and the entrypoint
wrapper creates the admin user.

### Reset everything

```bash
cd ~/homelab/devops/gitea
podman compose down -v
podman volume rm gitea_gitea_gitea_data gitea_gitea_postgres_data 2>/dev/null
podman compose up -d
```

## Testing

```bash
# Check Gitea web UI responds
podman exec homelab-gitea-test wget -qO- --timeout=5 http://gitea:3000/ | head -5

# Check PostgreSQL is reachable
podman exec homelab-gitea-test sh -c 'echo > /dev/tcp/postgres/5432 && echo "PostgreSQL reachable"'

# Verify database configuration
podman exec homelab-gitea sh -c 'grep -A6 "\[database\]" /etc/gitea/app.ini'

# Verify admin user exists
podman exec homelab-gitea /usr/local/bin/gitea admin user list

# Test API authentication
curl -u admin:"$GITEA_ADMIN_PASSWORD" http://localhost:3003/api/v1/user
```

## Cleanup

```bash
podman compose down -v
```

## Notes

- **No SSH:** The rootless image uses a builtin SSH server that requires UID mapping.
  For now, use HTTPS clones: `git clone http://localhost:3003/user/repo.git`
- **No email:** SMTP is disabled. Password reset emails will not work.
  Use the admin account to reset passwords via the web UI.
- **No self-registration:** Users must be created by an admin.
- **Rootless image:** Runs as `git` (uid 1000). Does not require root on the host.
- **Custom Dockerfile:** A custom image is built from `Dockerfile` that wraps the
  rootless Gitea entrypoint. The wrapper (`work/entrypoint.sh`) auto-creates the admin
  user on startup. See `experiment-timeline.md` for the full development history.
