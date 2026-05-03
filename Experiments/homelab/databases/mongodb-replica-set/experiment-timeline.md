# MongoDB Replica Set - Experiment Timeline

## Overview

Experiment to set up a 3-node MongoDB replica set with automatic failover using Podman rootless containers.

## Setup Date

April 18, 2026

## Directory

`~/homelab/databases/mongodb-replica-set/`

## Timeline

### Initial Setup

**Goal**: Create 3-node MongoDB replica set with KeyFile authentication

**Approach**:
- 3 MongoDB 7.0 containers on ports 27018, 27019, 27020
- KeyFile for inter-node authentication
- Custom init container to initialize replica set
- Test client container for verification

### Error 1: KeyFile Permissions - "Too Open"

**Error**: `Read security file failed: permissions on /data/config/keyfile are too open`

**Cause**: KeyFile had `444` (world-readable) permissions. MongoDB requires `400` or `600` (owner/group read-only).

**Fix**: Changed keyFile permissions to `400` (owner read-only).

```bash
chmod 400 keyfile/keyfile
```

### Error 2: KeyFile Permissions - "Bad File"

**Error**: `Read security file failed: error opening file: /data/config/keyfile: bad file`

**Cause**: In Podman rootless with user namespace mapping, the `mongodb` user (UID 999) inside the container maps to a different UID on the host. The keyFile with `400` permissions (owned by host user `labratorian`) was not readable by the container's mongodb user.

**Fix**: Created a custom Docker image that bakes the keyFile into the image with correct ownership:

```dockerfile
FROM docker.io/library/mongo:7.0
COPY keyfile/keyfile /data/config/keyfile
RUN chown mongodb:mongodb /data/config/keyfile && chmod 400 /data/config/keyfile
```

Updated `docker-compose.yml` to use `localhost/homelab-mongo-replica:latest` instead of `docker.io/library/mongo:7.0` and removed the keyFile bind mount.

**Lesson**: In Podman rootless, user namespace mapping breaks file permission assumptions. Baking files into custom images is more reliable than bind mounts for files with strict permissions.

### Error 3: Replica Set Init Failed - Quorum Check

**Error**: `replSetInitiate quorum check failed because not all proposed set members responded affirmatively: mongo3:27017 failed with Error connecting to mongo3:27017`

**Cause**: The init script only waited for mongo1 to be ready before running `rs.initiate()`. mongo2 and mongo3 were still starting up when the init script tried to connect to them.

**Fix**: Updated `init-replica-set.sh` to wait for all three nodes (mongo1, mongo2, mongo3) to be ready before initializing the replica set:

```bash
for node in mongo1 mongo2 mongo3; do
  for i in $(seq 1 30); do
    if mongosh --host "$node" ... --eval "db.adminCommand('ping')"; then
      echo "$node is ready!"
      break
    fi
    sleep 5
  done
done
```

**Lesson**: MongoDB replica set initialization requires all members to be running and accepting connections before `rs.initiate()` can succeed.

### Error 4: depends_on Unreliable for DB Startup

**Observation**: Used `depends_on` in docker-compose.yml for the test-client container, but not for mongo-init. Per AGENTS.md, `depends_on` is unreliable for DB startup ordering.

**Fix**: Used explicit wait loops in the init script instead of relying on `depends_on` for MongoDB containers.

**Lesson**: Always use explicit wait loops for database readiness checks, not `depends_on`.

## Verification Results

### Replica Set Status

```
mongo1:27017: PRIMARY
mongo2:27017: SECONDARY
mongo3:27017: SECONDARY
```

### Replication Test

- Inserted 3 documents on primary (mongo1)
- Verified all 3 documents replicated to mongo2 (secondary 1)
- Verified all 3 documents replicated to mongo3 (secondary 2)
- Write to secondary failed with `MongoServerError: not primary` (expected)

### Failover Test

1. Stopped primary (mongo1)
2. After ~12 seconds, mongo2 was elected as new PRIMARY
3. Write to new primary (mongo2) succeeded
4. Restored mongo1 - it rejoined as SECONDARY
5. Final state: mongo2=PRIMARY, mongo1=SECONDARY, mongo3=SECONDARY

**Result**: Automatic failover works correctly!

## Resource Usage

- **mongo1 (Primary)**: ~800MB - 1GB RAM
- **mongo2 (Secondary)**: ~800MB - 1GB RAM
- **mongo3 (Secondary)**: ~800MB - 1GB RAM
- **mongo-init**: ~50MB RAM (exits after initialization)
- **test-client**: ~5MB RAM
- **Total**: ~2.5 - 3.5GB RAM

## Files Created

- `docker-compose.yml` - Service definitions
- `Dockerfile` - Custom image with baked-in keyFile
- `keyfile/keyfile` - Generated KeyFile for authentication
- `init-replica-set.sh` - Init script with: configurable env vars, idempotency check, node readiness with double-verification, retry on init failure, dynamic election wait
- `README.md` - Documentation with verification commands

## Key Learnings

1. **KeyFile permissions**: MongoDB is very strict about keyFile permissions (400/600). In Podman rootless, bind mounts don't work due to user namespace mapping. Use custom Docker images instead.

2. **Wait for all nodes**: Replica set initialization requires all members to be ready. Wait for each node individually before calling `rs.initiate()`.

3. **No depends_on for DBs**: Use explicit wait loops instead of `depends_on` for database readiness checks.

4. **Automatic failover**: MongoDB replica sets provide automatic failover in ~12 seconds, much faster than manual promotion in PostgreSQL/MariaDB.

5. **Oplog replication**: Data replication is asynchronous via oplog, with typical lag of milliseconds.

6. **Write concern**: By default, writes only need to be acknowledged by the primary. For stronger guarantees, use `w: "majority"` write concern.

7. **Init script idempotency**: Always check if a replica set is already initialized before attempting `rs.initiate()`. Use `rs.status()` output to detect existing configuration.

8. **mongosh script execution**: `mongosh -f <file>` enters interactive mode after loading a file. Use heredocs (`<<EOF`) to pipe JS code via stdin for non-interactive execution.

9. **Dynamic vs fixed waits**: Polling for a condition (election completion) is better than fixed `sleep` - it's faster when things go well and more robust when they don't.

10. **Retry logic for transient failures**: Wrapping initialization commands in retry loops handles timing edge cases without manual intervention.

11. **Double-verification for readiness**: A second ping after the first success avoids false positives during early startup phases.

### Init Script Improvements - Streamlining Setup

**Date**: April 18, 2026 (follow-up session)

**Goal**: Make the init script more robust, configurable, and idempotent.

**Improvements implemented**:

1. **Configurable via environment variables** - All credentials, replica set name, and member list are overridable via env vars with sensible defaults.

2. **Already-initialized detection** - Before attempting initialization, the script checks if the replica set is already configured (by looking for `"members"` in `rs.status()` output). If already initialized, it prints the current status and exits cleanly. This makes `podman compose down` + `podman compose up -d` (without `-v`) idempotent.

3. **Retry on rs.initiate() failure** - Wrapped `rs.initiate()` in a retry loop (3 attempts, 5s between retries). If the first attempt fails due to timing, the script automatically retries instead of exiting with an error.

4. **Dynamic election wait** - Replaced the fixed `sleep 15` with a polling loop that checks `rs.isMaster().ismaster` every 3 seconds until a primary is elected (up to 30 attempts = ~90s). This is faster when election completes quickly (~12s = 4 iterations) and more robust when it takes longer.

5. **Second verification ping** - After the first `db.adminCommand('ping')` succeeds, a second ping is performed to avoid false positives during MongoDB's early startup phase.

6. **--quiet on all mongosh calls** - Added `--quiet` flag to suppress mongosh banner and prompt output, making logs cleaner.

**Bug fixes during implementation**:

- **Bug 1: Init check logic broken** - The initial `try/catch` approach with `2>/dev/null | grep -q "INITIALIZED"` produced no output in the mongo-init container, causing false positives. Fixed by capturing `rs.status()` as JSON and checking for `"members"` key.

- **Bug 2: mongosh -f hangs** - Using `mongosh -f "$TEMP_JS"` to execute a temp file caused mongosh to enter interactive mode after loading the file, hanging the script. Fixed by using a heredoc (`<<JSEOF`) to pipe JS code via stdin instead.

- **Bug 3: Grep pattern mismatch** - The initial grep pattern `"ok" : 1` didn't match mongosh's output format `{ ok: 1 }` (without quotes). Fixed by using `grep -qE '(ok: 1|"ok" : 1)'` to match both formats.

**Verification results**:

- Fresh start: Replica set initialized on first attempt, election completed in ~12s (4 iterations)
- With preserved volumes: Script detected already-initialized set, printed status, and exited cleanly
- Replication: 3 documents inserted on primary, all replicated to both secondaries
- Failover: Stopped primary, mongo2 elected as new PRIMARY in ~12s, write succeeded on new primary
- Recovery: Restored old primary, it rejoined as SECONDARY

**Lesson**: The init script should be idempotent, resilient to timing issues, and provide clear output at each step. Using heredocs for JS code is more reliable than file-based approaches with mongosh.

## Comparison with PostgreSQL/MariaDB Replication

| Aspect | PostgreSQL/MariaDB | MongoDB Replica Set |
|--------|-------------------|---------------------|
| Failover | Manual (promote standby) | Automatic (~12s election) |
| Setup complexity | Moderate (WAL/binlog config) | Moderate (KeyFile + rs.initiate) |
| Read scaling | Standby is read-only | Secondaries can do reads (with config) |
| Data redundancy | 1 copy on standby | 2 copies (on 2 secondaries) |
| Write concern | N/A | Configurable (w: 1, majority, etc.) |
| RAM usage | ~30-50MB per node | ~800MB-1GB per node |

---

## Simplification Session - April 24, 2026

### Changes Applied

**Phase 1 - Trivial Cleanup:**
- Removed `version: '3.8'` line
- Pinned Alpine test-client from `3.19` to `3.21`

**Phase 3 - Secret Hygiene:**
- Created `.env` with `MONGO_ROOT_PASSWORD` (generated secure random password)
- Created `.env.example` with placeholder value and comments
- Replaced all hardcoded `mongo_root_pass_123` references in docker-compose.yml with `${MONGO_ROOT_PASSWORD}`
- Updated init script default to use `${MONGO_ROOT_PASSWORD}` env var
- Added `.env` to `.gitignore`
- Updated README to reference env var for credentials

**Phase 4 - Network Naming:**
- Renamed network key from `mongodb-replica-network` to `homelab-mongodb-replica-set`
- Removed redundant `name:` field from network definition
- Updated all service references

**Phase 5 - Volume Naming:**
- Renamed volumes to `mongodbreplicaset_mongo1_data`, `mongodbreplicaset_mongo2_data`, `mongodbreplicaset_mongo3_data`
- Updated all service references

**Phase 8 - README Consistency:**
- Added Services table with port mappings
- Updated all verification commands to use `$MONGO_ROOT_PASSWORD`
- Added note about loading `.env` before running commands

### Bug Found During Verification

**Issue:** `mongo-init` container failed to initialize the replica set (exit code 1).

**Root Cause:** The `mongo-init` service in docker-compose.yml did not have any environment variables defined. The init script uses `${MONGO_ROOT_PASSWORD}` as a fallback default, but since the env var wasn't passed to the container, it was empty. The script tried to connect to MongoDB with an empty password and failed silently.

**Fix:** Added environment variables to the `mongo-init` service:
```yaml
mongo-init:
  environment:
    - MONGO_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD}
    - MONGO_USER=admin
    - MONGO_AUTH_DB=admin
```

**Lesson:** When services share credentials (like the init script needing the same password as the mongo containers), the env vars must be explicitly passed to each service that needs them. Compose does not automatically inherit environment variables from other services.

### Verification Results

- All 3 mongo containers started and passed healthchecks
- `mongo-init` successfully initialized the replica set
- Election completed in ~12 seconds (mongo1 elected PRIMARY)
- Replication verified: write on primary, read on secondary succeeded
- Test client can resolve service names and ping containers
- Ports 27018, 27019, 27020 had no conflicts

### Files Changed

- `docker-compose.yml` - Removed version, updated alpine tag, env vars, network, volumes
- `init-replica-set.sh` - Updated default password to use env var
- `.env` - Created with secure password
- `.env.example` - Created with placeholder
- `.gitignore` - Added `.env` exclusion
- `README.md` - Added services table, updated password references
