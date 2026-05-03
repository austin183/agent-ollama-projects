# Redis Experiment - Timeline

**Date:** April 18, 2026  
**Experiment:** 1B - Redis Queue + Workers  
**Domain:** Message Queues & Workers

## Setup Phase

### Initial Planning

Chose Redis 7.4 Alpine for minimal footprint. RedisInsight 2 for the UI layer. Followed patterns from existing database experiments (mongodb-pgadmin, postgresql-pgadmin) which pair a database with a management UI.

### Container Startup

```bash
cd ~/homelab/databases/redis-experiment
podman compose up -d
```

**Result:** All three containers started successfully.

### Image Verification

- `redis:7.4-alpine` - pulled from docker.io/library, Alpine-based (~30MB)
- `redis/redisinsight:2.52` - pulled from docker.io/redis, includes full UI (~200MB)
- `alpine:3.21` - pulled from docker.io/alpine, for test client

### Image Tag Issue

The RedisInsight image tag `2` does not resolve. Must use specific version tags like `2.52` or `2.52.0`. Found available tags via:

```bash
podman search --list-tags redis/redisinsight | head -20
```

Fixed by updating compose file: `image: docker.io/redis/redisinsight:2.52`

## Verification Phase

### Redis Health Check

```bash
podman exec homelab-redis redis-cli ping
```

**Output:** `PONG` - Redis responding correctly.

### RedisInsight Health Check

```bash
podman exec homelab-redisinsight wget -q -O - http://localhost:8001/api/healthcheck
```

**Output:** `{"status":"ok"}` - RedisInsight API responding.

### Inter-Service Connectivity

```bash
podman exec homelab-redis-test sh -c "apk add --no-cache redis && redis-cli -h redis ping"
```

**Output:** `PONG` - Test client can resolve `redis` service name and connect.

### Persistence Files

```bash
podman exec homelab-redis ls -la /data/
```

**Output:**
```
drwxr-xr-x    3 redis    redis         4096 Apr 18 20:54 .
dr-xr-xr-x    1 root     root          4096 Apr 18 20:54 ..
drwx------    2 redis    redis         4096 Apr 18 20:53 appendonlydir
-rw-------    1 redis    redis           88 Apr 18 20:54 dump.rdb
```

**Note:** Redis 7.x changed AOF storage from flat files (`appendonly.aof`) to a directory structure (`appendonlydir/`). This is a breaking change from Redis 6.x.

## Configuration Phase

### RedisInsight Setup Wizard

1. Opened `http://localhost:8001` in browser
2. First-launch wizard appeared automatically
3. Clicked "Create New Database"
4. Entered connection details:
   - **Name:** Homelab Redis
   - **Host:** `redis` (Docker service name)
   - **Port:** `6379`
    - **Authentication:** None (protected-mode disabled for lab use)
5. Connected successfully - RedisInsight dashboard loaded

**Note:** Using service name `redis` as the host is critical. Using `localhost` or `127.0.0.1` would fail because RedisInsight runs in its own container.

### Redis Configuration

Created `conf/redis.conf` with:
- RDB snapshot intervals: 900s/1key, 300s/10keys, 60s/10000keys
- AOF enabled with `everysec` fsync policy
- No password (lab use only)

## Architecture

### Network Diagram

```
+-------------------+     port 16379     +-------------------+
|   Host Machine    | ---------------->  |  homelab-redis    |
|   (localhost:16379)|                    |  redis:7.4-alpine |
+-------------------+                    +-------------------+
                                               |
                                               | internal DNS
                                               | (redis-network)
                                               v
+-------------------+     port 15540     +-------------------+
|   Host Machine    | ---------------->  | homelab-redisinsight|
|   (localhost:15540)|                    |  redisinsight:2   |
+-------------------+                    +-------------------+
                                               |
                                               | resolves "redis" via service DNS
                                               v
+-------------------+
| homelab-redis-test|
|  alpine:3.19      |
+-------------------+
```

### Key Concepts

**Redis Persistence Models:**
- **RDB (Redis Database):** Point-in-time snapshots. Fast recovery, but data between snapshots is lost.
- **AOF (Append Only File):** Log of every write operation. Safer but larger.
- **Hybrid (both enabled):** Redis 4.0+ combines both - uses AOF for recovery, RDB for compacting.

**Service Discovery:**
- Containers on the same Docker network resolve each other by service name
- `redis-cli -h redis` works because `redis` is the service name in docker-compose.yml
- This is provided by Docker's embedded DNS server at 127.0.0.11

## Design Decisions

### Why Redis 7.4 Alpine?
- Alpine Linux base is ~30MB vs ~120MB for Debian-based images
- Redis 7.4 is the latest stable with all modern features
- Performance difference is negligible for lab use

### Why RedisInsight 2?
- Official Redis UI maintained by Redis Inc
- Version 2 is a complete rewrite with better performance
- Visualizes all Redis data structures, supports Lua scripting, Pub/Sub viewer
- Alternative: `redis-commander` or `lazy-redis` (lighter but less featured)

### Why Named Volumes Over Bind Mounts?
- Redis data files have specific ownership (uid/gid 999 in Alpine image)
- Named volumes let Podman manage ownership automatically
- Easier to backup/restore with `podman volume export`
- No permission issues when Redis runs as non-root user

### Why No Password?
- Lab environment, not exposed to external networks
- RedisInsight setup is simpler without auth configuration
- Easy to add `requirepass` to redis.conf later

### Port 16379 (mapped to container 6379)
- Host port 16379 avoids conflicts with other Redis experiments
- Container port 6379 is standard Redis port
- > 1024 so rootless Podman binds it without special config
- Consistent with port allocation plan in experiments.md

## Resource Usage

Actual usage measured during verification:

```
$ podman stats homelab-redis homelab-redisinsight homelab-redis-test --no-stream

ID            NAME                  MEM USAGE / LIMIT  MEM %    NET IO           BLOCK IO   PIDS
74abf1ca436d  homelab-redis         2.99MB / 12.25GB   0.02%    1.298kB / 949B   0B / 0B    6
33caefc3f4b5  homelab-redisinsight  101.5MB / 12.25GB  0.83%    915.1kB / 59kB   0B / 0B    11
47d71db54038  homelab-redis-test    53.25kB / 12.25GB  0.00%    6.002MB / 18kB   0B / 0B    1
```

| Resource | Redis | RedisInsight | Test Client | Total | Budget |
|----------|-------|-------------|-------------|-------|--------|
| RAM | ~3MB | ~102MB | ~53KB | ~105MB | ~300MB |
| Storage | ~88KB (data) | ~200MB (UI) | minimal | ~200MB | ~200MB |

Redis is extremely lightweight (~3MB RAM). RedisInsight uses ~102MB at startup (settles lower). Total well within budget.

## Lessons Learned

### What Worked
- Alpine-based Redis image is very lightweight
- RedisInsight 2 UI is responsive and functional
- Service name DNS resolution works perfectly for inter-container communication
- Healthchecks are accurate (redis-cli ping is fast and reliable)

### What Could Be Improved
- RedisInsight takes ~30s to start (healthcheck start_period=30s is appropriate)
- Consider adding a `.env` file for any passwords if auth is enabled later
- Could add a Python worker container to demonstrate actual queue patterns

### Unexpected Findings

#### Protected Mode Blocked Inter-Container Communication
**Problem:** Test client could not connect to Redis via service name `redis`. Error: "Redis is running in protected mode because protected mode is enabled and no password is set."

**Root cause:** Redis 7.x enables `protected-mode yes` by default. With no password set, it only accepts connections from loopback interface (127.0.0.1).

**Resolution:** Set `protected-mode no` in `conf/redis.conf`. This is safe because containers are on an isolated Docker network (`homelab-redis-network`) not exposed to the internet.

#### Redis 7.x AOF Directory Structure Change
Redis 7.x changed AOF storage from individual files (`appendonly.aof`) to a directory (`appendonlydir/`). This was not documented in the initial plan.

#### RedisInsight Image Tag Resolution
The tag `2` does not exist for `redis/redisinsight`. Must use specific version tags like `2.52`.

#### RedisInsight Internal Port Mismatch
RedisInsight listens on port **5540** internally, not 8001. The compose file must map `8001:5540/tcp`, not `8001:8001/tcp`.

#### Healthcheck Required IPv4 Explicitly
`wget` inside the container resolves `localhost` to IPv6 `::1`, which RedisInsight doesn't bind to. Must use `127.0.0.1` explicitly. Standard wget healthcheck fails; used Node.js HTTP module as workaround since it correctly uses IPv4.

Final healthcheck: `node -e "const h=require('http');h.get('http://127.0.0.1:5540/api/healthcheck',r=>{process.exit(r.statusCode===200?0:1)}).on('error',()=>process.exit(1))"`

## Common Questions

**Q: Can I access Redis from the host?**  
A: Yes, via `redis-cli -h 127.0.0.1 -p 6379` (port 6379 is mapped to host).

**Q: How do I backup Redis data?**  
A: The named volume persists data. Use `podman volume export redis_experiment_redis_data -o redis-backup.tar` to backup.

**Q: Can I connect RedisInsight from another machine?**  
A: Yes, map port 8001 and access via `http://<host-ip>:8001`. RedisInsight would need to connect to Redis using the host IP instead of service name `redis`.

**Q: How much data can Redis hold?**  
A: As an in-memory store, it's limited by RAM. For this 12GB system, Redis can hold ~8GB of data comfortably (leaving headroom for other services).
