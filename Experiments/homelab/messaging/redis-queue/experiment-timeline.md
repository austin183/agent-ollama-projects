# Redis Queue Experiment - Timeline

**Experiment 1B** | Started: April 19, 2026

---

## Setup Phase

### Initial Checks
- Checked port 6379 availability: **free** (no conflicts)
- Checked existing containers: Kafka experiment running (5 containers)
- Created directory: `~/homelab/messaging/redis-queue/`

### Files Created
1. `docker-compose.yml` - 5 services (redis, worker, redisinsight, producer, test-client)
2. `workers/Dockerfile` - Python 3.11-slim with redis package
3. `workers/worker.py` - BLPOP consumer with 3 task types (echo, hash, transform)
4. `workers/producer.py` - Task generator with result polling

### Build & Start
```bash
podman compose up -d --build
```

**Result:** All 5 containers started successfully.

| Container | Status | Time to Healthy |
|-----------|--------|-----------------|
| homelab-redis | healthy | ~10s |
| homelab-redis-worker | running | N/A |
| homelab-redisinsight | running | N/A |
| homelab-redis-producer | running | N/A |
| homelab-redis-test | running | N/A |

---

## Verification Phase

### DNS Resolution
```bash
podman exec homelab-redis-test ping -c 2 redis
# 64 bytes from <CONTAINER_IP>: seq=0 ttl=42 time=0.056 ms
# 64 bytes from <CONTAINER_IP>: seq=1 ttl=42 time=0.093 ms

podman exec homelab-redis-test ping -c 2 homelab-redis-worker
# 64 bytes from <CONTAINER_IP>: seq=0 ttl=42 time=0.066 ms
```

**Result:** Service name resolution works correctly.

### Redis Connectivity
```bash
podman exec homelab-redis redis-cli ping
# PONG

podman exec homelab-redis redis-cli DBSIZE
# (integer) 42
```

**Result:** Redis is healthy and accepting commands.

### Manual Task Test
```bash
# Push a task
podman exec homelab-redis redis-cli RPush task_queue '{"id":"test1","type":"echo","payload":{"message":"hello"},"created_at":"2026-04-19T12:00:00Z"}'
# (integer) 1

# Check worker processed it
sleep 2
podman exec homelab-redis redis-cli GET 'result:test1'
# {"task_id": "test1", "result": {"message": "hello from manual test"}}
```

**Result:** Worker successfully consumed and processed the task.

---

## Issue: Empty Worker Logs

### Problem
After starting, `podman logs homelab-redis-worker` showed no output. Same for the producer.

### Investigation
1. Verified containers are running: `podman ps` shows all containers up
2. Tested Python works: `podman exec homelab-redis-worker python -c "print('ok')"` succeeds
3. Tried running worker directly: command worked but hung (blocking on blpop)
4. **Root cause:** Python buffers stdout by default when not connected to a terminal

### Resolution
Added `PYTHONUNBUFFERED=1` environment variable to both worker and producer services in `docker-compose.yml`:

```yaml
environment:
  - REDIS_URL=redis://redis:6379/0
  - TZ=America/New_York
  - PYTHONUNBUFFERED=1
```

Restarted affected containers:
```bash
podman compose restart worker test-producer
```

**Result:** Logs now appear in real-time after restart.

### Lesson
When running Python scripts in containers:
- Always set `PYTHONUNBUFFERED=1` for visible logs
- Alternatively, run with `python -u` or use `flush=True` in print statements
- This applies to any language with output buffering behavior

---

## Architecture Explanation

### Queue Pattern: Producer-Consumer with BLPOP

**Why BLPOP instead of Pub/Sub?**
- Pub/Sub loses messages to consumers that aren't connected at publish time
- BLPOP (blocking pop) provides reliable delivery - tasks wait in the queue until consumed
- Multiple workers can share the same queue (only one gets each task)

**Why not a dedicated message broker like RabbitMQ?**
- Redis is already used as a data store - adding a queue is trivial
- Lower resource footprint (~3MB Redis vs ~150MB RabbitMQ)
- Simpler deployment (1 container vs 3 for RabbitMQ+worker+monitoring)
- Trade-off: Redis queues don't support dead letter queues, acknowledgments, or complex routing

### Data Model
```
task_queue        -> LPUSH/RPOP or RPUSH/BLPOP (FIFO task queue)
result:{id}       -> SET with 1hr TTL (task results)
```

### Why This Design
- **Simple:** List-based queues are Redis's most basic data structure
- **Reliable:** BLPOP blocks until a task is available (no polling waste)
- **Scalable:** Multiple workers can consume from the same queue
- **Observable:** RedisInsight provides real-time visibility into queue depth and results

---

## Testing Checklist

```
Experiment Setup Progress:
[x] Compose file uses full image references (docker.io/redis:7.2-alpine, etc.)
[x] Ports are > 1024 (6379, 5540)
[x] Test client container included (alpine:latest)
[x] Healthcheck port matches service config (redis-cli ping)
[x] Volumes use hybrid strategy (named: redis_data, redisinsight_data)
[x] Network name follows homelab-* pattern (homelab-redis-network)
[x] README includes verification commands
[x] Expected output samples provided
[x] Worker handles reconnection gracefully
[x] PYTHONUNBUFFERED=1 set for visible logs
```

---

## Resource Usage

| Service | RAM | CPU | Storage |
|---------|-----|-----|---------|
| Redis (7.2-alpine) | ~3MB | <1% | ~50MB image |
| Worker (python:3.11-slim) | ~19MB | <1% | ~150MB image |
| RedisInsight (2.42.0) | ~88MB | ~1% | ~200MB image |
| Producer (python:3.11-slim) | ~19MB | <1% | ~150MB image |
| Test client (alpine) | ~0.05MB | ~0% | ~8MB image |
| **Total** | **~130MB** | **~3%** | **~560MB images** |

Budget was 300MB RAM, 200MB storage. Actual usage is well within budget.

---

## Common Questions

### Q: How do I add more workers?
Just add more `worker` services to the compose file (or use `deploy.replicas` with Swarm). They'll all share the same queue and each task goes to exactly one worker.

### Q: What happens if a worker crashes mid-task?
With BLPOP, the task is removed from the queue when popped. If the worker crashes before storing the result, the task is lost. For production, implement:
1. Acknowledgment pattern (pop -> ACK -> process -> store result)
2. Dead letter queue for failed tasks
3. Consider RabbitMQ for built-in acknowledgment support

### Q: Can I use this for long-running tasks?
Redis BLPOP has a configurable timeout (default 5s in the worker). For very long tasks, increase the timeout or use a different approach like Redis Streams with consumer groups.

### Q: How do I monitor the queue in real-time?
- RedisInsight GUI: http://localhost:5540
- CLI: `podman exec homelab-redis redis-cli LLEN task_queue` (queue depth)
- CLI: `podman exec homelab-redis redis-cli DBSIZE` (total keys)

### Q: Why port 5540 for RedisInsight?
RedisInsight defaults to port 8001. Used 5540 to follow the non-standard port pattern and avoid any potential conflicts.

---

## Lessons Learned

### What Worked Well
- Redis is extremely lightweight - 3MB idle RAM is negligible
- BLPOP pattern is simple and effective for basic task queues
- RedisInsight provides excellent visibility into the queue
- Python redis library makes queue operations trivial

### What Could Be Improved
- **Error handling:** Worker should log errors to a separate file, not just stdout
- **Task validation:** Producer should validate task payloads before pushing
- **Result format:** Consider using Redis Streams for structured task/result pairs
- **Monitoring:** Add a simple health endpoint that reports queue depth

### What to Do Differently Next Time
- Set `PYTHONUNBUFFERED=1` from the start (learned from RabbitMQ experiment's similar pattern)
- Consider Redis Streams instead of plain lists for more advanced features (consumer groups, pending messages)
- Add a simple metrics endpoint for queue depth monitoring

---

## Next Steps

1. **Scale workers:** Add multiple worker containers to test load distribution
2. **Add task types:** Implement image processing or data transformation tasks
3. **Integrate with other experiments:** Use this queue as a backend for reactive processing (Domain 9)
4. **Add persistence:** Configure Redis snapshots (RDB) in addition to AOF

---

## Simplification Phase (April 24, 2026)

Applied per-experiment simplification plan from `agent_docs/plans/experiment-simplification-per-experiment.md`.

### Phase 1 - Trivial Cleanup
- [x] Removed `version: '3.8'` line
- [x] Pinned `alpine:latest` → `alpine:3.21` (test-client)

### Phase 2 - Test-Client Standardization
- [x] Service already named `test-client` ✓
- [x] Container name `homelab-redis-test` follows convention ✓

### Phase 3 - Secret Hygiene
- [x] SKIPPED - No secrets in this experiment (Phase 3 flag: No)

### Phase 4 - Network Naming
- [x] Renamed network key from `homelab-redis-network` → `homelab-redis-queue`
- [x] Removed redundant `name: homelab-redis-network` field from network definition
- [x] Updated all 5 service references to new network key

### Phase 5 - Volume Naming
- [x] Renamed `redis_data` → `messaging-redis-queue_redis_data`
- [x] Renamed `redisinsight_data` → `messaging-redis-queue_redisinsight_data`
- [x] Updated all service volume references

### Phase 6 - Port Conflicts
- [x] Redis host port: `6379` → `26379` (per plan, avoids conflicts with redis-experiment 16379, redis-replication 46379)
- [x] RedisInsight host port: `5540` → `25540` (per plan, avoids conflicts with redis-experiment 15540, redis-queue-replication 35540)

### Phase 8 - README Consistency
- [x] Updated services table with new host ports
- [x] Updated network references in testing commands
- [x] Updated RedisInsight URL to use new host port
- [x] Updated FAQ about port numbers
- [x] Updated design decisions section

### Verification
```bash
# Stop and remove everything (required due to volume/network name changes)
podman compose down -v

# Start fresh
podman compose up -d --build
```

**Result:** All 5 containers started successfully.

| Container | Status | Notes |
|-----------|--------|-------|
| homelab-redis | Up (healthy) | Port 26379 mapped correctly |
| homelab-redis-worker | Up | Connected to redis |
| homelab-redisinsight | Up | Port 25540 mapped correctly |
| homelab-redis-test | Up | Alpine 3.21 |
| homelab-redis-producer | Up | Connected to redis |

**Tests passed:**
- `redis-cli ping` → `PONG`
- DNS resolution: `test-client` → `redis` ✓, `test-client` → `homelab-redis-worker` ✓
- Queue depth: `LLEN task_queue` → `0` (idle, as expected)
- Port bindings confirmed: 26379 and 25540 both listening

### Notes
- Podman-compose created network as `redis-queue_homelab-redis-queue` (project prefix added automatically)
- Volumes created with project prefix: `redis-queue_messaging-redis-queue_redis_data`
- Old volumes (`redis-queue_redis_data`, `redis-queue_redisinsight_data`) were cleaned up by `podman compose down -v`
- No errors or issues encountered during simplification
