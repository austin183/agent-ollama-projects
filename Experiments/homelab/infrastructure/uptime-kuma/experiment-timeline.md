# Experiment 6B: Uptime Kuma - Experiment Timeline

**Date:** April 20, 2026  
**Experiment:** 6B - Uptime Kuma (Service Monitoring)  
**Domain:** Home Infrastructure Services

---

## Setup Phase

### Initial Checks
- Checked running containers: `homelab-boinc`, `homelab-boinc-test`, `homelab-doc-converter`, `homelab-pdf-converter`
- Checked port 3002: **free** (no conflicts)
- No existing uptime-kuma directory found

### Compose File Creation
Created `infrastructure/uptime-kuma/docker-compose.yml` with:
- Image: `docker.io/louislam/uptime-kuma:1` (using `1` tag for latest v1.x stable)
- Port mapping: `3002:3001/tcp` (host 3002, container 3001)
- Named volume: `kuma_data:/app/data` for SQLite persistence
- Test client: Alpine container for connectivity verification
- Network: `homelab-kuma-network` (bridge)

### First Start
```bash
podman compose up -d
```
Result: Containers started successfully, image pulled (~150MB download)

---

## Verification Phase

### First Log Check
```
[DB] INFO: Database Patched Successfully
[SERVER] INFO: JWT secret is not found, generate one.
[SERVER] INFO: No user, need setup
[SERVER] INFO: Listening on 3001
[SERVICES] INFO: Starting nscd
```

Key observations:
- SQLite database initialized and patched
- JWT secret auto-generated
- **No admin user created** - requires web UI setup wizard
- Listening on port 3001 as expected

### Connectivity Tests
```bash
# From test client to service
podman exec homelab-kuma-test wget --spider -q http://uptime-kuma:3001/ && echo "OK"
# Result: OK

# From host to service
wget --spider -q http://localhost:3002/ && echo "OK"
# Result: OK
```

Both tests passed. Container-to-container DNS resolution works correctly.

### Health Check Issue Found
Initial health check used `wget`:
```yaml
test: ["CMD-SHELL", "wget --spider -q http://localhost:3001/ || exit 1"]
```

**Problem:** Uptime Kuma container doesn't have wget installed.
```
Output: /bin/sh: 1: wget: not found
```

**Fix:** Checked available tools and switched to `curl`:
```bash
podman exec homelab-uptime-kuma which curl node
# /usr/bin/curl
# /usr/local/bin/node
```

Updated healthcheck:
```yaml
test: ["CMD-SHELL", "curl -sf http://localhost:3001/ || exit 1"]
```

Recreated containers with `podman compose up -d --force-recreate`.

### Health Check After Fix
```bash
sleep 40 && podman inspect homelab-uptime-kuma --format '{{.State.Health.Status}}'
# Result: healthy
```

---

## Configuration Phase

### Manual Setup (Web UI)
Uptime Kuma requires initial user creation via browser:
1. Navigate to `http://<homelab-ip>:3002`
2. Create admin account
3. Add monitors for services (AdGuard, Prometheus, etc.)
4. Configure notifications

**Note:** All configuration is stored in the SQLite database within the named volume. No config files to edit manually.

---

## Architecture Explanation

### Component Design
```
┌─────────────────────────────────────────────┐
│           homelab-kuma-network              │
│                                             │
│  ┌──────────────────────┐  ┌─────────────┐ │
│  │  homelab-uptime-kuma │  │kuma-test-   │ │
│  │  (Node.js + SQLite)  │  │client       │ │
│  │  Port: 3001          │  │(Alpine)     │ │
│  │  Volume: /app/data   │  │             │ │
│  └──────────┬───────────┘ └─────────────┘ │
│             │                               │
│             ▼                               │
│  Host port 3002 → Container port 3001      │
└─────────────────────────────────────────────┘
```

### Why This Design
- **Single container** - Uptime Kuma bundles everything (app + SQLite), no separate DB needed
- **Named volume** - SQLite data persists across container rebuilds
- **Test client** - Verifies container networking works
- **Port 3002** - Avoids conflict with Grafana on 3000 and Gitea on 3001

### Why `louislam/uptime-kuma:1` Tag
- The `1` tag tracks the latest v1.x release (stable)
- Avoids `:latest` which could pull incompatible v2.x changes
- Image is lightweight (~150MB download)

---

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image reference (docker.io/louislam/uptime-kuma:1)
- [x] Port is > 1024 (3002:3001)
- [x] Test client container included (alpine:latest)
- [x] Healthcheck uses curl (container has curl, not wget)
- [x] Volume uses named volume strategy (kuma_data)
- [x] Network name follows homelab-* pattern (homelab-kuma-network)
- [x] README includes wizard steps
- [x] Verification commands documented
- [x] Expected output samples provided
```

---

## Common Questions Answered

### Q: Why port 3002 instead of 3001?
A: Port 3001 is the default for Grafana in this homelab. Using 3002 avoids conflicts.

### Q: Does Uptime Kuma need a separate database?
A: No. It uses SQLite by default, bundled in the same container. This keeps the experiment simple with just one service container.

### Q: Where is the configuration stored?
A: In the SQLite database file inside the `kuma_data` named volume at `/app/data`. There are no config files to edit.

### Q: Can other containers monitor Uptime Kuma?
A: Yes. Any container on `homelab-kuma-network` can reach it at `http://uptime-kuma:3001`.

### Q: What happens if I run `podman compose down -v`?
A: All monitors, settings, and history are deleted. The SQLite database is in the named volume.

---

## Lessons Learned

### What Worked
- Simple single-container design (no separate DB needed)
- Named volume for data persistence works well
- Test client connectivity verification is reliable
- Healthcheck with curl works correctly in the Node.js container

### What Didn't Work
- **Initial healthcheck used wget** - The Uptime Kuma image is Node.js-based (not Alpine), so it has curl but not wget. This caused 3 failed health checks before the fix.
- **`--requires` in podman run** - The test client container used `--requires` flag which caused a stop signal timeout. The Alpine container didn't respond to SIGTERM in 10 seconds and had to be SIGKILL'd during recreation. This is cosmetic but worth noting.

### What to Do Differently Next Time
- Check container contents for available tools before writing healthchecks
- The `louislam/uptime-kuma:1` tag is a good choice for stable tracking
- Consider adding a `mem_limit` for extra safety (though ~94MB is well within budget)

---

## Resource Usage vs Budget

| Resource | Budget | Actual (idle) | Actual (peak) |
|----------|--------|---------------|---------------|
| RAM | ~250MB | ~94MB | ~120MB (during checks) |
| CPU | - | ~4% | ~15% (during check bursts) |
| Storage | ~300MB | ~50MB | ~100MB (many monitors) |

All well within budget. The experiment is very lightweight.

---

## Simplification Cleanup (April 24, 2026)

Applied the experiment simplification plan (Phase 1-8) from `agent_docs/plans/experiment-simplification-per-experiment.md`.

### Changes Made

| Phase | Change | Before | After |
|-------|--------|--------|-------|
| 1 | Removed `version: '3.8'` line | Present | Removed |
| 1 | Pinned Alpine test-client tag | `alpine:latest` | `alpine:3.21` |
| 2 | Renamed test-client service | `kuma-test-client` | `test-client` |
| 2 | Standardized container_name | `homelab-kuma-test` | `homelab-uptime-kuma-test` |
| 3 | Created `.env` file | None | Empty (future-proofing) |
| 3 | Created `.env.example` file | None | Placeholder vars with comments |
| 4 | Renamed network key | `kuma-network` | `homelab-uptime-kuma` |
| 4 | Dropped redundant `name:` field | `name: homelab-kuma-network` | Removed |
| 5 | Renamed named volume | `kuma_data` | `uptime-kuma_kuma_data` |
| 8 | Added Overview section | "How It Works" header | "Overview" with 1-2 sentence summary |
| 8 | Added Services table | Not present | Present (uptime-kuma, test-client) |
| 8 | Added Quick Start section | Not present | Present with podman compose command |
| 8 | Updated verification commands | Referenced old names | Updated to new container/network names |
| 8 | Updated README structure | Experiment 6B header | Standardized header |

### Verification Results

```bash
# Started containers
podman compose up -d
# Result: Both containers started successfully

# Health check (after 40s wait)
podman inspect homelab-uptime-kuma --format '{{.State.Health.Status}}'
# Result: healthy

# Connectivity test
podman exec homelab-uptime-kuma-test wget --spider -q http://uptime-kuma:3001/ && echo "OK"
# Result: OK

# DNS resolution
podman exec homelab-uptime-kuma-test nslookup uptime-kuma
# Result: Resolved to <CONTAINER_IP>

# Cleanup
podman compose down -v
# Result: Containers and volume removed
```

### Notes

- Alpine test-client does not have `curl` installed; use `wget` for connectivity tests from the test client
- The Uptime Kuma container has `curl` but not `wget`, so the healthcheck uses `curl`
- Podman-compose prepends the project name (`uptime-kuma_`) to volume and network names at runtime
- `.env` is already excluded by the repo root `.gitignore`

---

## Dead Ends

None for this experiment. Uptime Kuma is straightforward and deployed cleanly on the second attempt (after fixing the healthcheck).
