# Building Container Experiments

Compose templates, patterns, and architecture guidance for creating new experiments.

## Quick Start Template

```yaml
services:
  main-service:
    image: docker.io/namespace/image:version  # Full image reference required
    container_name: homelab-service-name
    restart: unless-stopped
    ports:
      - "5000:5000/tcp"  # Use ports > 1024 for rootless
    volumes:
      - ./work:/path/to/work
      - ./conf:/path/to/conf
    environment:
      - TZ=America/New_York
    networks:
      - experiment-network
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  test-client:
    image: docker.io/alpine:3.21
    container_name: homelab-experiment-test
    command: sleep 3600
    networks:
      - experiment-network
    depends_on:
      - main-service

networks:
  experiment-network:
    driver: bridge
```

## Critical Patterns

### Always use full image references

Podman cannot resolve short names without explicit registry.

```yaml
# Required
image: docker.io/adguard/adguardhome:v0.107.61

# Fails
image: adguard/adguardhome:latest
```

### Pin image tags

Avoid `:latest` for databases and services where version matters. Use specific tags or major-version tracking (e.g., `mongo:7.0`, `uptime-kuma:1`).

### Use ports > 1024 for rootless containers

```yaml
# Works
ports:
  - "5053:53/udp"  # Host port 5053 -> container port 53
  - "8080:80/tcp"

# Fails without sysctl configuration
ports:
  - "53:53/udp"    # Rootless cannot bind privileged ports
  - "80:80/tcp"
```

### Include test client container

```yaml
test-client:
  image: docker.io/alpine:3.21
  container_name: homelab-experiment-test
  command: sleep 3600
  networks:
    - experiment-network
  depends_on:
    - main-service
```

For experiments needing specific tools (psql, mongosh, curl, etc.), create a `Dockerfile.test-client`:

```dockerfile
FROM docker.io/alpine:3.21
RUN apk add --no-cache postgresql-cli curl bind-tools iputils
```

Then reference in compose:
```yaml
test-client:
  build:
    dockerfile: Dockerfile.test-client
  container_name: homelab-experiment-test
  command: sleep 3600
  networks:
    - experiment-network
```

### Service name DNS resolution

Containers on the same network resolve each other by service name:

```bash
# From test-client, query main-service by name
podman exec homelab-experiment-test nslookup main-service
podman exec homelab-experiment-test curl http://main-service:5000/health
```

### Healthcheck matches configured port and available tools

```yaml
# If wizard/setup changes port from 3000 to 80, update healthcheck
healthcheck:
  test: ["CMD", "wget", "--spider", "-q", "http://localhost:80/status"]
```

**Check what HTTP tools are available in the image first.** Not all images have `wget`. Some have `curl`, some have neither.

```bash
# Check available tools
podman exec <container> which curl wget
```

Common substitutions:
- `wget --spider -q http://localhost:PORT/` -> `curl -sf http://localhost:PORT/`
- Not all services have `/health` — check actual endpoints

## Database-Specific Patterns

### Understand the Container's Init Mechanism

Different images initialize differently. Before configuring, check the Dockerfile's entrypoint and `/docker-entrypoint-initdb.d/` scripts.

- Environment variables may not modify runtime config files (e.g., `postgresql.conf`)
- Custom `command` fields run as root before dropping to the service user
- PostgreSQL 16 Alpine doesn't allow root execution

### Podman-compose `depends_on` Is Unreliable for Startup Ordering

Use manual wait loops in the compose `command` field:

```yaml
command: >
  sh -c '
    for i in $(seq 1 60); do
      if pg_isready -h other-service > /dev/null 2>&1; then break; fi;
      sleep 2;
    done;
    exec docker-entrypoint.sh <your-service>;
  '
```

### Clean Volumes When Changing Init Scripts

When modifying scripts in `/docker-entrypoint-initdb.d/` or similar init directories:

```bash
podman compose down -v
podman compose up -d
```

Stale data from previous runs causes silent failures.

### Heredoc Variable Expansion in Compose Commands

Single-quoted heredocs in compose commands do NOT expand variables. `$PGDATA` becomes the literal string `"$PGDATA"`. Use multiple `echo` statements instead.

### File Permissions in Rootless Podman

Bind mounts for files with strict permissions (like MongoDB KeyFiles) may fail due to user namespace mapping. Bake files into custom images instead:

```dockerfile
FROM docker.io/library/mongo:7.0
COPY keyfile/keyfile /data/config/keyfile
RUN chown mongodb:mongodb /data/config/keyfile && chmod 400 /data/config/keyfile
```

## Setup Wizard Services

For services with initial setup wizards (like AdGuard Home, Uptime Kuma):

1. Document wizard steps explicitly in README
2. Note that config files don't exist until wizard completes
3. Warn that default ports may change during setup
4. Provide log grep commands to find actual ports:
   ```bash
   podman logs homelab-service | grep "go to http"
   ```

## Volume Strategy

```yaml
volumes:
  # Named volumes for DB internals (persistent, managed by Podman)
  - db_data:/var/lib/postgresql/data

  # Bind mounts for configs (editable on host)
  - ./conf:/path/to/conf
  - ./work:/path/to/work
```

Naming convention: `<experiment>_<service>_<purpose>` (e.g., `postgresql-replication_primary_data`)

## Secret Management

### Never embed passwords in compose files

Use `.env` files loaded by compose:

```yaml
# docker-compose.yml
environment:
  - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
```

```bash
# .env (add to .gitignore)
POSTGRES_PASSWORD=securepassword123
```

Create `.env.example` with placeholder values for documentation.

### For the `atmoz/sftp` image

Use `SFTP_USERS` environment variable instead of command-line format.

## Network Naming

Use `homelab-<experiment-name>` pattern. Do NOT use redundant `name:` field:

```yaml
networks:
  homelab-experiment:    # Key name is used as network name
    driver: bridge
```

## Common Port Conflicts

- Port 5353: mDNS (often in use)
- Port 80: May be occupied by host services
- Port 53: Requires `cap_add: NET_ADMIN` + sysctl for rootless
- Port 3000: Grafana
- Port 11434: Ollama

## GPU Passthrough

For experiments needing GPU access (BOINC, OpenVINO, llama.cpp):

```yaml
devices:
  - /dev/dri:/dev/dri
```

- Works in rootless Podman without `video` group membership
- Intel Iris Xe: use SYCL or OpenCL images
- NVIDIA GPU: use NVIDIA container toolkit

## Testing Checklist

```
Experiment Setup Progress:
- [ ] Compose file uses full image references
- [ ] Image tags pinned (no :latest for databases)
- [ ] Ports are > 1024 (or documented exception)
- [ ] Test client container included
- [ ] Healthcheck port matches service config
- [ ] Healthcheck uses available tools (curl vs wget)
- [ ] Volumes use hybrid strategy (named + bind)
- [ ] Network name follows homelab-* pattern
- [ ] Secrets extracted to .env file
- [ ] .env.example created with placeholders
```

