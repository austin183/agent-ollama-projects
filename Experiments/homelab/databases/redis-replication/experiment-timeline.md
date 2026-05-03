# Redis Replication - Experiment Timeline

## Setup Phase

### April 18, 2026

#### Steps Taken

1. **Stopped existing Redis experiment**
   - Ran `podman compose down -v` in `~/homelab/databases/redis-experiment`
   - Containers stopped: homelab-redis-test, homelab-redisinsight, homelab-redis
   - Volumes removed: redis-experiment_redis_data, redis-experiment_redisinsight_data
   - Note: homelab-redis-test required SIGKILL after 10s timeout

2. **Verified ports 46379 and 46380 are free**
    - Ran `ss -tlnp | grep -E '46379|46380'` - no conflicts

3. **Created directory structure**
   - `~/homelab/databases/redis-replication/`
   - `~/homelab/databases/redis-replication/conf/`

4. **Created configuration files**
   - `conf/primary.conf` - Standard Redis master config with RDB + AOF persistence
    - `conf/replica.conf` - Same base config plus `replicaof redis-primary 6379` and `replica-read-only yes`

5. **Created docker-compose.yml**
   - 3 services: redis-primary, redis-replica, test-client
   - Hybrid volume strategy: named volumes for data, bind mounts for configs
   - Bridge network: homelab-redis-replication-network
   - Healthchecks on both Redis containers

#### Design Decisions

- **Redis 7.4-alpine**: Latest stable Alpine-based image, minimal footprint
- **Alpine 3.19 for test client**: Matches Redis base image family, includes redis-cli package
- **Named volumes for data**: Managed by Podman, survives container rebuilds
- **Bind mounts for configs**: Editable on host, version-controlled
- **Password authentication**: Added `requirepass` and `masterauth` for security; `protected-mode yes` enforces auth on all connections
- **RDB + AOF persistence**: Both nodes persist data for durability testing

#### Issues Encountered

- Port 6379 was occupied by previous redis-experiment (resolved by stopping it first)
- Replica could not connect to master: used service name `primary` in `replicaof` directive, but the compose service name is `redis-primary`. Fixed by changing `replicaof primary 6379` to `replicaof redis-primary 6379`

## Verification Phase

### Container Status

| Container | Status | Host Port |
|-----------|--------|-----------|
| homelab-redis-primary | healthy | 46379 |
| homelab-redis-replica | healthy | 46380 |
| homelab-redis-replication-test | running | N/A |

### Replication Status

- Primary connected replicas: 1
- Replica master link status: up
- Replication offset sync: confirmed working

### Test Results

| Test | Expected | Actual |
|------|----------|--------|
| Primary ping | PONG | PONG |
| Replica ping | PONG | PONG |
| Write on primary | OK | OK |
| Read on replica | replication-test | replication-test |
| Write on replica | READONLY error | READONLY You can't write against a read only replica. |
| Failover (SLAVEOF NO ONE) | Writable | OK - accepted write after SLAVEOF NO ONE |
| Write via test-client to primary | OK | OK |
| Read via test-client from replica | hello | hello |

## Architecture Explanation

### How Redis Replication Works

1. **Initial sync**: When replica starts with `replicaof` directive, it connects to the primary and performs a full synchronization (RDB transfer)
2. **Continuous sync**: After initial sync, replica receives commands from primary via the replication stream (AOF-based)
3. **Asynchronous**: Primary does not wait for replica acknowledgment before responding to client writes
4. **Single-master**: Only one primary accepts writes; replicas are read-only

### Key Redis Replication Concepts

- **Replication offset**: Each side tracks how much data it has received/sent; mismatch indicates lag
- **Partial resync**: If connection drops briefly, replica can resume from offset (not full resync)
- **Full resync**: Required after extended downtime or configuration changes
- **`replica-read-only`**: Enforced by Redis server, cannot be disabled at runtime
- **`SLAVEOF NO ONE`**: Breaks replication, makes replica an independent primary

### Network Flow

```
Client --> localhost:46379 --> redis-primary:6379 (writable master)
                                        |
                                internal network replication
                                        v
Client --> localhost:46380 <-- redis-replica:6379 (read-only slave)
```

## Simplification Cleanup - April 24, 2026

Applied all 8 simplification phases to standardize this experiment.

### Changes Made

**Phase 1 - Trivial Cleanup:**
- Removed `version: '3.8'` line
- Pinned Alpine test-client from `alpine:3.19` to `alpine:3.21`

**Phase 3 - Secret Hygiene:**
- Created `.env` with `REDIS_PASSWORD=redis-repl-secret-2026`
- Created `.env.example` with placeholder `CHANGE_ME`
- Added `requirepass` to both `primary.conf` and `replica.conf`
- Added `masterauth` to `replica.conf` for replica-to-primary authentication
- Changed `protected-mode` from `no` to `yes` for security
- Updated healthchecks to use `-a ${REDIS_PASSWORD}` flag

**Critical Issue - Config Variable Expansion:**
- `${REDIS_PASSWORD}` in bind-mounted config files is NOT expanded by Redis (Redis configs don't support shell variable expansion)
- **Solution:** Used `sed` in the compose `command` field to substitute the password at container startup:
  - Primary: `sed 's|requirepass .*|requirepass ${REDIS_PASSWORD}|' config > /tmp/redis.conf && redis-server /tmp/redis.conf`
  - Replica: Same plus `masterauth` substitution
- The `>` YAML block scalar with double quotes allows `${REDIS_PASSWORD}` to expand at compose parse time (when podman-compose reads the file)
- Verified: `podman ps` shows the expanded password in the running container's command

**Phase 4 - Network Naming:**
- Renamed network key from `replication-network` to `homelab-redis-replication`
- Removed redundant `name: homelab-redis-replication-network` field

**Phase 5 - Volume Naming:**
- Renamed `primary_data` to `homelab_redis_replication_primary_data`
- Renamed `replica_data` to `homelab_redis_replication_replica_data`

**Phase 6 - Port Conflicts:**
- Updated primary host port from `6379` to `46379` (per plan Appendix C)
- Updated replica host port from `6380` to `46380` (per plan Appendix C)
- Container ports remain `6379` (internal)

**Phase 8 - README:**
- Added Overview section
- Added Services table with host ports
- Added Setup section explaining .env configuration
- Updated all test commands with `-a` password flag
- Added host port testing section
- Updated Troubleshooting section with auth-related issues

### Verification Results

| Test | Expected | Actual |
|------|----------|--------|
| Primary ping (with auth) | PONG | PONG |
| Replica ping (with auth) | PONG | PONG |
| Primary role | master | master |
| Connected replicas | 1 | 1 |
| Replica master_link_status | up | up |
| Write on primary | OK | OK |
| Read on replica | replication-test | replication-test |
| Write on replica | READONLY error | READONLY You can't write against a read only replica. |
| Write via test-client to primary | OK | OK |
| Read via test-client from replica | hello | hello |

### Lessons Learned

- **Redis configs don't support shell variable expansion** — use `sed` or wrapper scripts for runtime substitution
- **`protected-mode yes` requires authentication** — all connections (including healthchecks) need `-a password`
- **Healthcheck `${REDIS_PASSWORD}` expands at compose parse time** — the password is baked into the healthcheck command, not re-evaluated each run
- **Alpine 3.21** is the current standard test-client version (was 3.19)

## Lessons Learned

- Redis replicas need primary to be healthy on first start, but auto-reconnect handles subsequent failures
- Replica data directory must be empty on first start (Redis refuses to replicate into non-empty dir)
- `depends_on` in compose doesn't guarantee service readiness - Redis auto-reconnect handles timing
- Both RDB and AOF enabled on replicas means replica persists its own copy of replicated data
- **Service name in `replicaof` must match the compose service name**, not a shortened version. The compose service name `redis-primary` resolves on the network, but `primary` does not
