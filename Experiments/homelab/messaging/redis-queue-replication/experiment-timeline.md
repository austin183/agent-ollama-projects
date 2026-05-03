# Redis Queue + Replication - Experiment Timeline

**Experiment 1C** | Started: April 19, 2026

---

## Setup Phase

### April 19, 2026

#### Steps Taken

1. **Checked for port conflicts**
   - Ports 6379, 6380, 5540 were in use by existing experiments (redis-queue, redis-replication)
   - Stopped `~/homelab/messaging/redis-queue` via `podman compose down`
   - Ports confirmed free before starting new experiment

2. **Created directory structure**
   - `~/homelab/messaging/redis-queue-replication/`
   - `~/homelab/messaging/redis-queue-replication/conf/`
   - `~/homelab/messaging/redis-queue-replication/workers/`

3. **Created configuration files**
   - `conf/primary.conf` - Standard Redis master with `maxmemory 256mb` and `allkeys-lru`
   - `conf/replica.conf` - Same base config plus `replicaof redis-primary 6379` and `replica-read-only yes`

4. **Created docker-compose.yml**
   - 6 services: redis-primary, redis-replica, worker, producer, redisinsight, test-client
   - Hybrid volume strategy: named volumes for data, bind mounts for configs
   - Network: `homelab-redis-qrep-network`

5. **Created worker/producer scripts**
   - `workers/worker.py` - Reads from primary (BLPOP), writes results to primary (SET)
   - `workers/producer.py` - Writes to primary (RPUSH), reads results from replica (GET)
   - `workers/Dockerfile` - Python 3.11-slim with redis package

#### Issues Encountered

**Issue 1: BLPOP fails on read-only replica**

- **Error:** `READONLY You can't write against a read only replica.`
- **Location:** Worker's `replica.blpop(QUEUE_NAME, timeout=5)` call
- **Root Cause:** BLPOP is a **write operation** in Redis - it removes items from the list. Read-only replicas reject all write operations, including BLPOP.
- **Resolution:** Changed worker to read from primary instead of replica. The worker connects to both nodes:
  - Reads tasks from **primary** (BLPOP requires write access)
  - Stores results on **primary** (SET, which replicates automatically)
  - Producer reads results from **replica** (GET is a read operation, works on replica)

- **Lesson:** Not all "read" commands are safe on replicas. Commands that modify data (BLPOP, SPOP, LTRIM, etc.) will fail on read-only replicas even though they're conceptually "reading" from the queue.

#### Design Decisions (Final)

- **Worker reads from primary** - BLPOP is a write operation, must use master
- **Producer reads from replica** - GET is a pure read, safe on replicas
- **Results stored on primary** - Only node that accepts writes; replicates back to replica
- **Ports 6379 (primary) and 6380 (replica)** - Consistent with redis-replication experiment

---

## Verification Phase

### Container Status

| Container | Status | Port |
|-----------|--------|------|
| homelab-redis-qrep-primary | healthy | 6379 |
| homelab-redis-qrep-replica | healthy | 6380 |
| homelab-redis-qrep-worker | running | N/A |
| homelab-redis-qrep-producer | running | N/A |
| homelab-redis-qrep-insight | running | 5540 |
| homelab-redis-qrep-test | running | N/A |

### Test Results

| Test | Expected | Actual |
|------|----------|--------|
| Primary ping | PONG | PONG |
| Replica ping | PONG | PONG |
| Primary connected_slaves | 1 | 1 |
| Replica master_link_status | up | up |
| Write on primary (SET) | OK | OK |
| Read on replica (GET) | replication-test | replication-test |
| Write on replica (SET) | READONLY error | READONLY You can't write against a read only replica. |
| Push task to primary queue | (integer) 1 | (integer) 1 |
| Worker processes task | Task processed | Task processed (echo, hash, transform all work) |
| Result on primary | Task result | `{"task_id": "final-test", "result": {"message": "queue+replication works"}}` |
| Result on replica (replicated) | Same as primary | Same as primary |
| Queue depth after processing | 0 on both | 0 on both |
| Producer reads from replica | Result available | Results successfully read from replica |

### Replication Status

```
Primary: role=master, connected_slaves=1, slave0=online
Replica: role=slave, master_link_status=up, slave_read_only=1
```

### Resource Usage

| Service | RAM | CPU |
|---------|-----|-----|
| Redis Primary | 3.1 MB | 0.86% |
| Redis Replica | 3.2 MB | 0.89% |
| Worker | 19.3 MB | 0.34% |
| Producer | 19.3 MB | 0.36% |
| RedisInsight | 88.0 MB | 9.74% |
| **Total** | **~133 MB** | **~12%** |

---

## Architecture Explanation

### Final Queue + Replication Pattern

```
[producer] --> RPUSH --> [redis-primary:6379] (MASTER - writes)
                                    |
                              replication stream
                                    v
[producer] <-- GET <-- [redis-replica:6379] (REPLICA - reads)
                          ^
                          |
              [worker] <-- BLPOP (reads from primary, not replica!)
                          |
                    (process task)
                          |
                    SET result --> [redis-primary] (results on primary)
```

**Key concept:** The producer pushes tasks to the primary's queue. Replication copies the RPUSH to the replica. The worker reads from the **primary** (BLPOP is a write operation, cannot run on replica). After processing, the worker stores results on the primary, which replicates back to the replica. The producer reads results from the **replica** (GET is a pure read operation).

### Why BLPOP Cannot Run on Replicas

BLPOP removes items from a list, which is a write operation at the Redis protocol level. Even though it's conceptually "reading from a queue," Redis treats it as a mutation and rejects it on read-only replicas.

### Replication of Queue Operations

| Operation | Node | Replicated? | Why |
|-----------|------|-------------|-----|
| RPUSH (producer) | Primary | Yes | Write to master |
| BLPOP (worker) | Primary | N/A | Modifies list locally |
| SET result (worker) | Primary | Yes | Write to master |
| GET result (producer) | Replica | N/A | Read from replica |

---

## Lessons Learned

### What Worked Well
- Combining queue and replication in one experiment shows real-world patterns
- Redis replication is lightweight and fast (sub-millisecond for small writes)
- Python worker scripts handle reconnection gracefully
- Producer successfully reads replicated results from replica

### What Didn't Work (and Why)
- **Initial design: worker reads from replica** - BLPOP is a write operation, fails on read-only replicas
- This is a fundamental Redis limitation, not a configuration issue

### What to Do Differently Next Time
- Know which Redis commands are "write" operations even when they seem like reads (BLPOP, SPOP, LTRIM, RPOPLPUSH, etc.)
- Consider Redis Streams with consumer groups for more advanced queue patterns with replication
- Add a second worker to test load distribution
- Test failover scenario (promote replica to primary with `REPLICAOF NO ONE`)
- Measure replication lag explicitly under load

### Common Questions
**Q: Why not just use the primary for everything?**
A: In production, read replicas distribute read load. This experiment shows that pattern - the producer reads results from the replica, demonstrating that reads can be offloaded.

**Q: What if the primary goes down?**
A: The worker would lose the ability to process tasks. A replica could be promoted with `REPLICAOF NO ONE`, but that requires manual intervention (or Redis Sentinel/Auto-failover).

**Q: Can workers read from a replica if we make it writable?**
A: Yes, but then you'd have two writable nodes and risk data conflicts. Redis replication is single-master by design.

---

## Simplification Cleanup - April 24, 2026

Applied per-experiment simplification plan phases 1-8:

### Phase 1 - Trivial Cleanup
- [x] Removed `version: '3.8'` line
- [x] Pinned `alpine:latest` → `alpine:3.21` on test-client

### Phase 4 - Network Naming
- [x] Renamed internal network key: `qrep-network` → `homelab-redis-queue-replication`
- [x] Removed redundant `name:` field from network definition
- [x] Updated all 6 service references to use new network key

### Phase 5 - Volume Naming
- [x] Renamed `primary_data` → `redis_queue_replication_primary_data`
- [x] Renamed `replica_data` → `redis_queue_replication_replica_data`
- [x] Renamed `redisinsight_data` → `redis_queue_replication_redisinsight_data`

### Phase 6 - Port Conflicts
- [x] Primary: `6379:6379` → `36379:6379` (unique host port)
- [x] Replica: `6380:6379` → `36380:6379` (unique host port)
- [x] RedisInsight: `5540:5540` → `35540:5540` (unique host port)

### Phase 8 - README Consistency
- [x] Updated Services table with new host ports
- [x] Updated RedisInsight URL (localhost:35540)
- [x] Updated Common Pitfalls port references
- [x] Added Troubleshooting section
- [x] Added Cleanup section

### Verification
- [x] `podman compose down -v` (cleanup old data)
- [x] `podman compose up -d` (all 6 containers started)
- [x] Primary ping: PONG
- [x] Replica ping: PONG
- [x] Primary `connected_slaves:1` (replication active)
- [x] Replica `master_link_status:up` (replication connected)
- [x] Write on primary (SET): OK
- [x] Read on replica (GET): hello (replication confirmed)
- [x] Write on replica (SET): READONLY error (expected)
- [x] Test-client DNS resolution: PONG to both primary and replica
- [x] `podman compose down -v` (cleanup after verification)

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references
- [x] Ports are > 1024 (36379, 36380, 35540)
- [x] Test client container included
- [x] Healthcheck port matches service config
- [x] Volumes use hybrid strategy (named + bind)
- [x] Network name follows homelab-* pattern (homelab-redis-queue-replication)
- [x] README includes verification commands
- [x] Verification commands documented
- [x] Expected output samples provided
- [x] Phase 1: version line removed, alpine pinned
- [x] Phase 4: network renamed, redundant name: removed
- [x] Phase 5: volumes renamed to redis_queue_replication_* convention
- [x] Phase 6: ports updated to unique values (36379, 36380, 35540)
- [x] Phase 8: README updated with ports, Troubleshooting, Cleanup
```
