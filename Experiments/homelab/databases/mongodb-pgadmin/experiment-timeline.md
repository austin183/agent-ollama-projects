# Experiment 2A: Multi-DB Comparison Suite - MongoDB

**Date:** April 18, 2026  
**Status:** Complete - Running  
**Duration:** ~30 minutes

---

## Setup Phase

### Errors Encountered

#### Error 1: pgAdmin image not found
**Symptom:** `Error: initializing source docker://pgadmin:latest: requested access to the resource is denied`

**Root cause:** The `pgadmin` image is not in the Docker "library" org. The correct image is `dpage/pgadmin4`.

**Resolution:** Changed image reference from `docker.io/library/pgadmin:latest` to `docker.io/dpage/pgadmin4:latest`.

#### Error 2: pgAdmin email validation failure
**Symptom:** Container logs showed repeated warnings:
```
'admin@homelab.local' does not appear to be a valid email address.
The part after the @-sign is a special-use or reserved name that cannot be used with email.
```

**Root cause:** `.local` is a reserved TLD (RFC 6761 - mDNS). pgAdmin's email validation rejects it.

**Resolution:** Changed email from `admin@homelab.local` to `admin@homelab.com`.

#### Error 3: MongoDB healthcheck command quoting broken
**Symptom:** MongoDB showed `(starting)` status indefinitely. Healthcheck command was malformed:
```
/bin/sh -c mongosh' '--eval' ''db.adminCommand('"'"'ping'"'"')'
```

**Root cause:** Podman-compose mangles the quoting when converting `["CMD", "mongosh", "--eval", "..."]` format to shell commands.

**Resolution:** Changed to `CMD-SHELL` format with single string: `["CMD-SHELL", "mongosh --eval \"db.adminCommand('ping')\""]`

#### Error 4: Init script syntax error
**Symptom:** `SyntaxError: Unexpected token (2:0)` when init script ran.

**Root cause:** The `.js` file had a bash shebang (`#!/bin/bash`) and bash syntax. MongoDB's entrypoint runs `.js` files directly with `mongosh`, not through a shell interpreter.

**Resolution:** Rewrote init script as pure JavaScript without bash syntax. The MongoDB Docker entrypoint automatically runs `.js` files in `docker-entrypoint-initdb.d/` using `mongosh`.

### Successful Startup

After fixes, all three containers started successfully:
- `homelab-mongodb` - MongoDB 7.0, healthy after ~30s
- `homelab-pgadmin` - pgAdmin4, healthy after ~60s
- `homelab-multi-db-test` - Alpine test client, running immediately

---

## Verification Phase

### Container Status
```
NAMES                  STATUS                    PORTS
homelab-mongodb        Up 59 seconds (healthy)   0.0.0.0:27017->27017/tcp
homelab-pgadmin        Up 57 seconds (starting)  0.0.0.0:8085->80/tcp
homelab-multi-db-test  Up 56 seconds
```

### MongoDB Data Verification
```bash
$ podman exec homelab-mongodb mongosh -u admin -p mongo_root_pass_123 --authenticationDatabase admin --eval "db.getSiblingDB('homelab').users.find({}, {name: 1, role: 1, _id: 0})"
[
  { name: 'Alice', role: 'admin' },
  { name: 'Bob', role: 'user' },
  { name: 'Charlie', role: 'user' }
]

$ podman exec homelab-mongodb mongosh -u admin -p mongo_root_pass_123 --authenticationDatabase admin --eval "db.getSiblingDB('homelab').products.find({category: 'electronics'}, {name: 1, price: 1, _id: 0})"
[
  { name: 'Laptop', price: 999.99 },
  { name: 'Keyboard', price: 79.99 }
]
```

### Network Verification
```bash
$ podman exec homelab-multi-db-test sh -c "ping -c 2 mongodb"
PING mongodb (<CONTAINER_IP>): 56 data bytes
64 bytes from <CONTAINER_IP>: seq=0 ttl=42 time=0.020 ms
64 bytes from <CONTAINER_IP>: seq=1 ttl=42 time=0.063 ms
--- mongodb ping statistics ---
2 packets transmitted, 2 received, 0% packet loss
```

DNS resolution works - test client resolves `mongodb` service name to container IP.

---

## Configuration Phase

### Init Script
Created `init-scripts/01-init-sample-data.js` - a pure JavaScript file that runs on first startup:
- Creates `homelab` database
- Inserts 3 users, 4 products, 3 metrics documents
- Creates `sessions` collection with TTL index

Key learning: MongoDB Docker entrypoint runs `.js` files via `mongosh`, NOT through bash. Files must be pure JavaScript.

### PostgreSQL Note
pgAdmin was included for comparison purposes but has limited utility since:
- The PostgreSQL containers from other experiments are on different networks
- pgAdmin is a PostgreSQL admin tool, not a MongoDB tool
- For MongoDB administration, `mongosh` CLI or MongoDB Compass (desktop app) is more appropriate

---

## Architecture Explanation

```
┌─────────────────────────────────────────────────┐
│              homelab-multi-db-network            │
│                                                  │
│  ┌──────────────────┐    ┌──────────────────┐   │
│  │   homelab-mongodb│    │   homelab-pgadmin│   │
│  │  MongoDB 7.0     │    │   pgAdmin4       │   │
│  │  Port 27017      │    │   Port 8085      │   │
│  │  Named volume:   │    │   (Web UI)       │   │
│  │  mongo_data      │    │                  │   │
│  └────────┬─────────┘    └────────┬─────────┘   │
│           │                       │              │
│           └──── homelab-multi-db-test ──┘        │
│              (Alpine 3.19)                       │
└─────────────────────────────────────────────────┘
```

**Data flow:**
1. MongoDB container starts, entrypoint detects empty data directory
2. Init script (`01-init-sample-data.js`) runs via `mongosh`
3. Sample data is inserted into `homelab` database
4. Healthcheck verifies MongoDB responds to `ping` command
5. pgAdmin container starts, serves web UI on port 80 (mapped to 8085)
6. Test client can reach both services by Docker DNS names

---

## Design Decisions

### Why MongoDB 7.0?
- Current LTS version with stable feature set
- Supports multi-document ACID transactions
- Good documentation and community support

### Why port 27017?
- MongoDB's default port
- Confirmed free (no port conflicts)
- No need for non-standard port mapping

### Why include pgAdmin?
- Allows comparing MongoDB (NoSQL) query patterns against PostgreSQL (SQL)
- Provides a familiar database admin interface for contrast
- Can theoretically connect to other PostgreSQL containers if on same network

### Volume strategy
- **Named volume** for MongoDB data (`mongo_data`): Clean lifecycle management, Podman handles backups
- **Bind mount** for init scripts: Version-controlled, editable on host

### Why pure JS init script?
- MongoDB Docker entrypoint runs `.js` files through `mongosh`, not bash
- Shell script wrapper doesn't work with `.js` extension
- Pure JS is simpler and more portable

---

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references
- [x] Ports are > 1024 (27017, 18085)
- [x] Test client container included
- [x] Healthcheck port matches service config
- [x] Volumes use hybrid strategy (named + bind)
- [x] Network name follows homelab-* pattern
- [x] README includes wizard/verification steps
- [x] Verification commands documented
- [x] Expected output samples provided
- [x] version: '3.8' removed
- [x] Image tags pinned (pgAdmin 9.9.0, Alpine 3.21)
- [x] Test-client container_name standardized
- [x] Secrets extracted to .env
- [x] Network naming standardized
- [x] Volume naming standardized
```

---

## Common Questions

### Q: Why does MongoDB require authentication now?
A: MongoDB 7.0 Docker image enables authentication by default when `MONGO_INITDB_ROOT_USERNAME` and `MONGO_INITDB_ROOT_PASSWORD` are set. All queries need `-u admin -p <password> --authenticationDatabase admin`.

### Q: Can I connect from a local MongoDB Compass?
A: Yes. Configure Compass to connect to `localhost:27017` with:
- Authentication: Standard (SCRAM-SHA-256)
- Username: `admin`
- Password: `mongo_root_pass_123`
- Auth Database: `admin`

### Q: Why is pgAdmin taking so long to start?
A: pgAdmin initializes its web server and creates internal tables on first run. It typically takes 30-60 seconds. Check logs with `podman logs homelab-pgadmin`.

### Q: How do I add more sample data?
A: After the initial startup, the init script won't run again (it only runs on empty data directories). To add more data, use `mongosh` directly:
```bash
podman exec -it homelab-mongodb mongosh -u admin -p mongo_root_pass_123 --authenticationDatabase admin
```

### Q: What happens if I remove the volume?
A: `podman compose down -v` removes the volume and all data. The init script will run again on next startup if the volume is fresh.

---

## Resource Usage

| Container | RAM | CPU | Notes |
|-----------|-----|-----|-------|
| homelab-mongodb | ~73 MB | 9% | Very lightweight, well under 500MB budget |
| homelab-pgadmin | ~249 MB | 46% | Initial startup spike, should settle lower |
| homelab-multi-db-test | ~49 KB | 0.8% | Negligible |
| **Total** | **~322 MB** | | Well within 1.5GB budget |

---

## Lessons Learned

### What worked well
1. **Pure JS init scripts** - Clean, portable, and work correctly with MongoDB entrypoint
2. **Named volumes** - Simple lifecycle, automatic cleanup with `down -v`
3. **Sample data** - Good for quick verification and testing query patterns
4. **Test client** - Confirms inter-container networking works

### What to do differently
1. **Skip pgAdmin** - It's not useful for MongoDB experiments. Replace with MongoDB Compass documentation or a MongoDB-specific admin tool in a future iteration
2. **Use `.sh` init scripts** - If bash logic is needed, use `.sh` extension and invoke `mongosh` inside. But pure JS is simpler for most cases
3. **Healthcheck format** - Always use `CMD-SHELL` format for complex commands to avoid quoting issues with podman-compose

### Surprises
1. MongoDB 7.0 has auth enabled by default with root credentials - this is good security practice but wasn't obvious from the docs
2. The `.local` TLD rejection by pgAdmin was unexpected but makes sense from a standards perspective
3. MongoDB container is surprisingly lightweight (~73MB idle)

---

## Next Steps

1. Test MongoDB aggregation pipelines and indexing
2. Compare query syntax between MongoDB and PostgreSQL
3. Import real-world data into MongoDB collections
4. Set up MongoDB replica set (future experiment)
5. Consider replacing pgAdmin with MongoDB-specific admin documentation

---

## Simplification Cleanup (April 24, 2026)

Applied per-experiment simplification plan phases 1-8.

### Changes Made

#### Phase 1 - Trivial Cleanup
- Removed `version: '3.8'` line (deprecated in modern compose)
- Pinned `dpage/pgadmin4:latest` → `dpage/pgadmin4:9.9.0` (current stable)
- Pinned `alpine:3.19` → `alpine:3.21` for test-client

#### Phase 2 - Test-Client Standardization
- Renamed container_name: `homelab-multi-db-test` → `homelab-mongodb-pgadmin-test`
- Updated image reference: `docker.io/library/alpine:3.19` → `docker.io/alpine:3.21`

#### Phase 3 - Secret Hygiene
- Created `.env` with `MONGO_INITDB_ROOT_PASSWORD=mongo_root_pass_123`
- Created `.env.example` with placeholder value and comments
- Replaced hardcoded `mongo_root_pass_123` in compose with `${MONGO_INITDB_ROOT_PASSWORD}`
- Verified `.env` excluded by repo root `.gitignore`

#### Phase 4 - Network Naming
- Renamed network key: `multi-db-network` → `homelab-mongodb-pgadmin`
- Removed redundant `name: homelab-multi-db-network` field
- Updated all service references to use new network key

#### Phase 5 - Volume Naming
- Renamed volume: `mongo_data` → `mongodb-pgadmin_mongodb_data`
- Updated service volume reference

#### Phase 6 - Port Verification
- MongoDB: host 27017 → container 27017 (no conflict, unique allocation)
- pgAdmin: host 18085 → container 80 (matches plan, moved from 8085 to 18085 to avoid conflict with timescaledb-replication)

#### Phase 8 - README Updates
- Rewrote README with template structure: Overview, Quick Start, Services table, Testing, Troubleshooting, Cleanup
- Updated all container names, network names, volume names
- Updated version references (pgAdmin 9.9.0, Alpine 3.21)
- Updated port references (18085 instead of 8085)
- Added env var note for MongoDB credentials

### Verification Results

```
$ podman ps --filter network='mongodb-pgadmin_homelab-mongodb-pgadmin'
CONTAINER ID  IMAGE                           STATUS                    PORTS                     NAMES
c1d2fcad6d99  docker.io/library/mongo:7.0     Up 26 seconds (healthy)   0.0.0.0:27017->27017/tcp  homelab-mongodb
834b3f8709bd  docker.io/dpage/pgadmin4:9.9.0  Up 17 seconds (starting)  0.0.0.0:18085->80/tcp     homelab-pgadmin
491fdda9fa75  docker.io/library/alpine:3.21   Up 16 seconds                                       homelab-mongodb-pgadmin-test
```

DNS resolution test (from test-client):
- `ping mongodb` → 0% packet loss, 0.050ms avg
- `ping pgadmin` → 0% packet loss, 0.043ms avg

MongoDB healthcheck: `{ ok: 1 }`

All containers started and verified successfully. Cleaned up with `podman compose down -v`.

### Notes

- Volume name in podman becomes `mongodb-pgadmin_mongodb-pgadmin_mongodb_data` due to project name prefixing by podman-compose. This is expected behavior.
- Network name in podman becomes `mongodb-pgadmin_homelab-mongodb-pgadmin` for the same reason.
- Port 18085 was already correct per the plan (moved from 8085 to avoid conflict with timescaledb-replication).
