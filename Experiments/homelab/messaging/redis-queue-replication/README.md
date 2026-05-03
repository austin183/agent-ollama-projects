# Redis Queue + Replication Experiment

**Experiment 1C** - Message Queues with Read Replication  
**Status:** Running  
**Date:** April 19, 2026

---

## Overview

This experiment combines Redis message queuing with master-replica replication. Tasks are published to the primary (write path) and results are read from the replica (read path), demonstrating how replication can serve read-heavy workloads while the primary handles writes.

## Quick Start

```bash
cd ~/homelab/messaging/redis-queue-replication
podman compose up -d --build
```

The `--build` flag is required on first run to build the custom worker and producer images. Subsequent runs after code changes also need `--build`.

Verify it's running:

```bash
podman exec homelab-redis-qrep-primary redis-cli ping
# PONG
```

## Services

| Service | Host Port | Container Port | Purpose |
|---------|-----------|----------------|---------|
| redis-primary | 36379 | 6379 | Redis master (write node) |
| redis-replica | 36380 | 6379 | Redis replica (read node) |
| redisinsight | 35540 | 5540 | Redis GUI viewer |

## How It Works

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

**Architecture:**
- **redis-primary** - Master node accepting writes (queue pushes, result storage)
- **redis-replica** - Read-only replica serving result reads
- **Worker** - Consumes tasks from primary's queue via BLPOP (BLPOP is a write operation, must use master)
- **Producer** - Pushes tasks to primary, reads results from replica (mixed path)
- **RedisInsight** - GUI connected to primary for monitoring

**Data Flow:**
1. Producer pushes task to `task_queue` on **primary** (RPUSH)
2. Replica asynchronously replicates the RPUSH command
3. Worker blocks on `blpop(task_queue)` on **primary** (BLPOP is a write operation)
4. Worker processes task and stores result at `result:{id}` on **primary** (SET)
5. Producer reads result from **replica** (GET result:{id})

**Key Design:** BLPOP is a write operation in Redis (it removes items from the list), so workers must read from the primary. Results are stored on primary and replicated to the replica, where the producer reads them.

## Container Details

| Container | Image | Port | Purpose |
|-----------|-------|------|---------|
| homelab-redis-qrep-primary | redis:7.4-alpine | 36379 | Redis master (write node) |
| homelab-redis-qrep-replica | redis:7.4-alpine | 36380 | Redis replica (read node) |
| homelab-redis-qrep-worker | custom (python:3.11-slim) | - | Task consumer (reads from primary) |
| homelab-redis-qrep-producer | custom (python:3.11-slim) | - | Task generator (writes to primary) |
| homelab-redis-qrep-insight | redis/redisinsight:2.42.0 | 35540 | Redis GUI viewer |
| homelab-redis-qrep-test | alpine:3.21 | - | Connectivity test client |

## Task Types

| Type | Description | Example |
|------|-------------|---------|
| `echo` | Returns payload unchanged | `{"message": "hello"}` |
| `hash` | SHA256 hash of input string | `{"input": "data"}` |
| `transform` | Uppercase strings, double numbers | `{"items": ["a", "b"]}` |

## Testing

```bash
podman exec homelab-redis-qrep-test sh -c 'apk add --no-cache redis > /dev/null 2>&1 && redis-cli -h redis-primary ping && redis-cli -h redis-replica ping'
```

Expected: `PONG` from both primary and replica.

## Verification Commands

### Check container health
```bash
podman ps --filter 'name=homelab-redis-qrep'
```

Expected: 6 containers running (primary, replica, worker, producer, insight, test)

### Test Redis connectivity
```bash
# Primary
podman exec homelab-redis-qrep-primary redis-cli ping
# Expected: PONG

# Replica
podman exec homelab-redis-qrep-replica redis-cli ping
# Expected: PONG
```

### Check replication status
```bash
podman exec homelab-redis-qrep-primary redis-cli INFO replication
```
Expected to see: `connected_slaves:1`

```bash
podman exec homelab-redis-qrep-replica redis-cli INFO replication
```
Expected to see: `master_link_status:up`

### Test write on primary
```bash
podman exec homelab-redis-qrep-primary redis-cli SET test:key "hello"
# Expected: OK
```

### Test read on replica (should replicate)
```bash
podman exec homelab-redis-qrep-replica redis-cli GET test:key
# Expected: hello (after brief replication delay)
```

### Test replica is read-only
```bash
podman exec homelab-redis-qrep-replica redis-cli SET test:readonly "should-fail"
# Expected: READONLY You can't write against a read only replica.
```

### Push a manual task to primary
```bash
podman exec homelab-redis-qrep-primary redis-cli RPush task_queue '{"id":"manual1","type":"echo","payload":{"message":"from manual test"},"created_at":"2026-04-19T00:00:00Z"}'
# Expected: (integer) 1
```

### Wait for worker to process, then check result on replica
```bash
sleep 3
podman exec homelab-redis-qrep-replica redis-cli GET result:manual1
# Expected: {"task_id": "manual1", "result": {"message": "from manual test"}}
```

### Check queue depth on replica
```bash
podman exec homelab-redis-qrep-replica redis-cli LLEN task_queue
# Expected: 0 when idle (worker consumed the task)
```

### Test via test-client container
```bash
# Write via test-client to primary
podman exec homelab-redis-qrep-test redis-cli -h homelab-redis-qrep-primary SET from-test "ok"

# Read via test-client from replica
podman exec homelab-redis-qrep-test redis-cli -h homelab-redis-qrep-replica GET from-test
```

### RedisInsight GUI
Open http://localhost:35540 in a browser. Connect to `redis://redis-primary:6379`.

## Stopping the Experiment

```bash
cd ~/homelab/messaging/redis-queue-replication
podman compose down
podman compose down -v    # Stop and remove volumes (data loss)
```

## Resource Usage

| Service | RAM | CPU |
|---------|-----|-----|
| Redis Primary | ~3MB | <1% |
| Redis Replica | ~3MB | <1% |
| Worker | ~19MB | <1% |
| Producer | ~19MB | <1% |
| RedisInsight | ~88MB | ~1% |
| **Total** | **~132MB** | **~3%** |

---

## Troubleshooting

- **Containers won't start after volume changes**: Run `podman compose down -v` then `podman compose up -d`. Old volumes with different configs cause silent failures.
- **Replica shows `master_link_status:down`**: Wait 15-30 seconds for initial sync. Check primary is healthy first with `redis-cli -p 36379 ping`.
- **Worker can't connect to Redis**: Verify `redis-primary` service is up. Worker retries every 3 seconds on connection failure.
- **RedisInsight won't connect**: Ensure host port is `35540` (not `5540`). Connect to `redis://redis-primary:6379` inside the container network.
- **Port already in use**: Check with `ss -tlnp | grep -E '36379|36380|35540'`. Stop conflicting experiments first.

## Cleanup

```bash
cd ~/homelab/messaging/redis-queue-replication
podman compose down
podman compose down -v    # Stop and remove volumes (data loss)
```

---

## How It Works: Queue + Replication Pattern

### Why BLPOP Must Run on Primary

In production, read replicas distribute read load away from the primary. However, **BLPOP is a write operation** in Redis - it removes items from a list. This means:
- **Writes go to primary only** (RPUSH, SET, BLPOP)
- **Reads go to replica** (GET)
- **Results stored on primary** propagate to replica via replication

### Replication of Queue Operations

| Operation | Node | Replicated? |
|-----------|------|-------------|
| RPUSH (producer) | Primary | Yes - replica gets the item |
| BLPOP (worker) | Primary | No - modifies list locally |
| SET result (worker) | Primary | Yes - replica gets the result |
| GET result (producer) | Replica | Reads replicated data |

### When Would You Use This Pattern?

- **High read throughput for results** - Results stored on primary, read from replicas
- **Read-heavy workloads** - Primary handles writes, replicas serve reads
- **Disaster recovery** - Replica can be promoted if primary fails

### Alternative: Redis Streams

For more advanced queue patterns with replication, consider Redis Streams with consumer groups. Streams support consumer group semantics where each message is delivered to exactly one consumer in the group, and the stream itself is replicated across master-replica pairs.

---

## Common Pitfalls

- **Python output buffering** - Use `PYTHONUNBUFFERED=1` environment variable
- **Task TTL** - Results are stored with 1-hour TTL (`SETEX`)
- **Replica read-only** - Writes to replica fail with `READONLY` error (expected)
- **Replication lag** - Small delay between primary writes and replica reads
- **BLPOP is a write operation** - Cannot run BLPOP on read-only replicas; workers must read from primary
- **Port conflicts** - Primary uses 36379, replica uses 36380, RedisInsight uses 35540

## Design Decisions

- **Redis 7.4 Alpine** - Latest stable, lightweight image
- **Worker reads from primary** - BLPOP is a write operation, cannot run on read-only replicas
- **Producer reads from replica** - GET is a pure read, safe on replicas (demonstrates read-offloading)
- **Write to primary** - Only primary accepts writes (single-master model)
- **256MB maxmemory per node** - Prevents Redis from consuming too much RAM
- **allkeys-lru eviction** - Evicts least recently used keys when memory limit reached
- **Hybrid volume strategy** - Named volumes for data, bind mounts for configs

## Next Steps

1. Add a second worker to test load distribution on the primary
2. Test failover: promote replica to primary with `REPLICAOF NO ONE`
3. Measure replication lag under load
4. Replace lists with Redis Streams for consumer group semantics
5. Test with Redis Sentinel for automatic failover
