# Redis Experiment

**Domain:** Message Queues & Workers (Exp 1B)  
**Phase:** Phase 3 (Messaging)  
**Date:** April 18, 2026

## How It Works

This experiment runs a Redis 7.4 server with RedisInsight 2 UI for visual exploration. Redis is an in-memory data store used for caching, pub/sub messaging, and lightweight job queues.

### Architecture

```
[Host] --port 16379--> [Redis Container] <--persist--> [redis_experiment_redis_data volume]
                          |
                          |-- RDB snapshots (save 900 1, etc.)
                          |-- AOF log (appendonly yes)
                          |
[Host] --port 15540--> [RedisInsight UI] <--connects to--> [Redis:6379]
```

### Services

| Service | Image | Ports | Purpose |
|---------|-------|-------|---------|
| redis | redis:7.4-alpine | 16379 | In-memory data store |
| redisinsight | redis/redisinsight:2.52 | 15540 (maps to 5540) | Web UI for Redis |
| test-client | alpine:3.21 | - | Connectivity testing |

### Persistence Strategy

- **RDB snapshots:** Full data snapshots at configurable intervals (900s/1key, 300s/10keys, 60s/10000keys)
- **AOF (Append Only File):** Every write operation logged, synced every second
- **Hybrid volumes:** Named volume `redis_experiment_redis_data` for both RDB and AOF files

## Setup

### Start the experiment

```bash
cd ~/homelab/databases/redis-experiment
podman compose up -d
```

### Access RedisInsight UI

1. Open browser to `http://localhost:15540`
2. First launch shows setup wizard - click "Create New Database"
3. Enter connection details:
   - **Name:** Homelab Redis
   - **Host:** redis (service name on internal network)
   - **Port:** 6379
   - **No password** (disabled for lab use)
4. Click "Continue" to connect

### Quick Data Operations

```bash
# Connect to Redis CLI from test container
podman exec -it homelab-redis-test sh
redis-cli -h redis

# From inside redis-cli:
SET mykey "Hello Redis"
GET mykey
KEYS *
DBSIZE
```

## Verification Commands

### Check Redis is running and responding

```bash
podman exec homelab-redis redis-cli ping
```

**Expected output:**
```
PONG
```

### Check RedisInsight is running

```bash
podman exec homelab-redisinsight wget -q -O - http://127.0.0.1:5540/api/healthcheck
```

**Expected output:**
```json
{"status":"ok"}
```

### Test connectivity from test client

```bash
podman exec homelab-redis-test redis-cli -h redis ping
```

**Expected output:**
```
PONG
```

### Verify persistence files exist

```bash
podman exec homelab-redis ls -la /data/
```

**Expected output:**
```
appendonlydir/
dump.rdb
```
**Note:** Redis 7.x uses `appendonlydir/` directory for AOF (changed from flat `appendonly.aof` file in Redis 6.x).

If you do not see the dump.rdb file, it means the RDB Snapshot has not been set yet.  You can trigger it manually with this command:

```bash
podman exec homelab-redis redis-cli BGSAVE
```

### Check resource usage

```bash
podman stats homelab-redis homelab-redisinsight --no-stream
```

## Common Pitfalls

### RedisInsight needs setup wizard
- RedisInsight does not auto-connect to Redis
- You must manually create a database connection in the UI
- Use service name `redis` as the host (not localhost or 127.0.0.1)

### Port 16379 (mapped to container 6379)
- Host port 16379 > 1024 so rootless Podman handles it fine
- No special capabilities needed

### Data persistence across restarts
- Named volume `redis_experiment_redis_data` persists data automatically
- Both RDB and AOF files are stored in the volume
- Use `podman compose down -v` to remove data (careful!)

### RedisInsight data
- RedisInsight stores its own config in `redis_experiment_redisinsight_data` volume
- Database connections persist across restarts
- To reset RedisInsight config: `podman compose down -v` and restart

## Testing Checklist

```
Redis Experiment Setup Progress:
- [x] Compose file uses full image references (redis:7.4-alpine, redis/redisinsight:2.52)
- [x] Ports are > 1024 (16379, 15540)
- [x] Test client container included
- [x] Healthcheck matches configured ports
- [x] Volumes use named strategy for data persistence
- [x] Network name follows homelab-* pattern (homelab-redis-network)
- [x] README includes wizard steps for RedisInsight
- [x] Verification commands documented
```

## Resource Usage

| Resource | Redis | RedisInsight | Total | Budget |
|----------|-------|-------------|-------|--------|
| RAM | ~10-50MB | ~200-400MB | ~250MB | ~300MB |
| Storage | ~1-5MB | ~50-100MB | ~100MB | ~200MB |

## Next Steps

- Try Pub/Sub messaging with `redis-cli -h redis SUBSCRIBE testchannel`
- Connect a Python worker script to demonstrate queue patterns
- Explore Redis data structures (lists, sets, hashes, sorted sets)
- Set up replication with a second Redis instance
