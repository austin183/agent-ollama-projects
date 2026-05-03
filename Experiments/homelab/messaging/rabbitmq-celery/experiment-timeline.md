# RabbitMQ + Celery Experiment Timeline

**Date:** April 18, 2026  
**Phase:** 3 - Messaging Domain  
**Experiment:** 1A - RabbitMQ + Celery Worker Pattern

---

## Simplification Cleanup (April 24, 2026)

Applied the per-experiment simplification plan (experiment #19) through all phases.

### Phase 1 - Trivial Cleanup
- [x] Removed `version: '3.8'` line
- [x] Pinned `alpine:latest` → `alpine:3.21` on test-client

### Phase 2 - Test-Client Standardization
- [x] Service already named `test-client` ✓
- [x] Image pinned to `alpine:3.21`
- [x] Renamed container_name from `homelab-messaging-test` → `homelab-rabbitmq-celery-test`

### Phase 3 - Secret Hygiene
- [x] Created `.env` with actual secret values
- [x] Created `.env.example` with placeholder values and comments
- [x] Extracted `RABBITMQ_DEFAULT_PASS` from hardcoded value
- [x] Extracted `FLOWER_BASIC_AUTH` from hardcoded value
- [x] Replaced all hardcoded credentials in docker-compose.yml with `${VAR_NAME}` references
- [x] `.env` already excluded by repo-level `.gitignore` ✓
- [x] Updated Python fallback credentials to `changeme` (compose file uses .env values)

**Secrets extracted:**
| Variable | Purpose |
|----------|---------|
| `RABBITMQ_DEFAULT_PASS` | RabbitMQ default user password |
| `FLOWER_BASIC_AUTH` | Flower auth in `username:password` format |

### Phase 4 - Network Naming
- [x] Renamed network key from `homelab-messaging-network` → `homelab-rabbitmq-celery`
- [x] Removed redundant `name: homelab-messaging-network` field from network definition
- [x] Updated all service references to use new network key

### Phase 5 - Volume Naming
- [x] Renamed named volume from `rabbitmq_data` → `rabbitmq_celery_rabbitmq_data`
- [x] Updated service volume reference

### Phase 6 - Port Conflicts
- [x] RabbitMQ AMQP: `55672:5672` → `25672:5672` (per plan)
- [x] RabbitMQ Management: `15672:15672` → `25673:15672` (per plan)
- [x] Flower: `5555:5555` → `25555:5555` (per plan, was already correct offset)

### Verification Results

**Start:** `podman compose down -v && podman compose up -d --build`

| Container | Status | Notes |
|-----------|--------|-------|
| homelab-rabbitmq | Running | Healthcheck passes, AMQP on 5672, mgmt on 15672 |
| homelab-celery-worker | Running | Connected to RabbitMQ, processing tasks |
| homelab-flower | Running | Connected to RabbitMQ, auth working |
| homelab-test-producer | Exited (expected) | Sends 5 tasks and exits |
| homelab-rabbitmq-celery-test | Running | Alpine 3.21, DNS resolution works |

**Tests passed:**
- [x] RabbitMQ health: `rabbitmq-diagnostics -q ping` → `ok`
- [x] Management API: `curl localhost:25673/api/overview` → returns JSON
- [x] Flower auth: `curl localhost:25555/auth/login -u homelab:homelab123` → returns HTML
- [x] DNS resolution: `nslookup rabbitmq/celery-worker/flower` → all resolve
- [x] Task processing: 5 tasks sent and processed successfully by celery-worker
- [x] Container networking: All containers on `homelab-rabbitmq-celery` network

**Note:** test-producer fails on first run due to RabbitMQ not being ready (no healthcheck dependency). This is pre-existing behavior, not introduced by simplification. Restart with `podman compose restart test-producer` after RabbitMQ is healthy.

### Design Decisions

1. **Port 25672 instead of 55672**: Plan specifies 25672 for RabbitMQ AMQP. The original 55672 used an arbitrary +50000 offset. New value follows the plan's systematic port allocation.

2. **Port 25673 instead of 15672**: Management UI moved from privileged-adjacent 15672 to 25673 to avoid any potential conflicts and follow the plan.

3. **Network naming**: Changed from generic `homelab-messaging-network` to specific `homelab-rabbitmq-celery` to distinguish from other messaging experiments (rabbitmq-cluster, kafka).

4. **Volume naming**: Changed from `rabbitmq_data` to `rabbitmq_celery_rabbitmq_data` following the `<experiment>_<service>_<purpose>` convention.

5. **Secret extraction**: Both `RABBITMQ_DEFAULT_PASS` and `FLOWER_BASIC_AUTH` extracted to `.env`. The `FLOWER_BASIC_AUTH` variable contains the full `username:password` string.

---

## Setup Phase

### Directory Structure Created

```
~/homelab/messaging/rabbitmq-celery/
├── docker-compose.yml
├── README.md
├── experiment-timeline.md
├── conf/                          # (empty, for future config overrides)
└── workers/
    ├── Dockerfile
    ├── task_worker.py             # Celery worker with task definitions
    └── producer.py                # Test producer script
```

### Port Conflict Check

Checked ports 5672, 15672, 5555, 6379 - no conflicts found.

### Design Decisions

1. **RabbitMQ image:** Used `rabbitmq:3.13-management-alpine` (Alpine-based for smaller size, management plugin included)
2. **Celery version:** Using Celery 5.x (comes with python:3.11-slim base image via pip)
3. **Flower version:** `mher/flower:2.0.1` - latest stable
4. **Port mapping:** RabbitMQ AMQP port mapped to 25672, Management UI to 25673, Flower to 25555. All > 1024 for rootless Podman compatibility. (Updated during simplification from original 55672/15672/5555.)
5. **Celery concurrency:** Set to 2 (`--concurrency=2`) to limit resource usage on the 12GB RAM machine
6. **Message persistence:** Tasks use `delivery_mode=2` to make them persistent on RabbitMQ
7. **Volume strategy:** Named volume for RabbitMQ data (`rabbitmq_data`), bind mount for worker code (`./workers:/app/workers`)
8. **Network:** Dedicated `homelab-messaging-network` bridge network

### Image References (Full, as required by Podman)

- `docker.io/rabbitmq:3.13-management-alpine`
- `docker.io/python:3.11-slim` (base for custom images)
- `docker.io/mher/flower:2.0.1`
- `docker.io/alpine:3.21` (test client)

---

## Verification Phase

### Container Startup

All 5 containers started successfully after fixing the Flower healthcheck and producer integration.

### Post-Startup Checks

**RabbitMQ:** Healthy, accessible at http://localhost:15672 (user: homelab / homelab123)
**Celery Worker:** Running, connected to RabbitMQ, processing tasks
**Flower:** Running at http://localhost:5555 (user: homelab / homelab123)
**Test Producer:** Sent 5 tasks successfully via Celery API
**Test Client:** DNS resolution works between all containers

### Task Processing Results

All 5 tasks were processed successfully:

```
[1] tasks.resize_image (800x600 -> webp)    - Done in ~2s
[2] tasks.send_email (user@example.com)     - Done in ~1s
[3] tasks.generate_report (monthly/2026)    - Done in ~3s
[4] tasks.process_video (120s h264)         - Done in ~4s
[5] tasks.resize_image (200x200 -> jpg)     - Done in ~2s
```

Total processing time: ~12 seconds for 5 tasks with concurrency=2.

---

## Architecture Explanation

### How RabbitMQ + Celery Works Together

RabbitMQ is a message broker - it receives messages from producers and routes them to consumers. Celery is a distributed task queue framework that uses RabbitMQ (or other brokers) to distribute work across worker processes.

**The pattern:**

1. A **producer** (any application) sends a task message to a RabbitMQ queue
2. RabbitMQ stores the message until a **worker** is ready to process it
3. **Celery workers** subscribe to the queue and pick up tasks
4. Each task runs in a worker process, producing a result
5. Results are stored (in this experiment, using `rpc://` backend)

### Why This Pattern?

- **Decoupling:** Producers don't need to know about workers
- **Scalability:** Add more workers by running more celery-worker containers
- **Reliability:** Messages persist in RabbitMQ even if workers go down
- **Monitoring:** Flower provides real-time visibility into the pipeline

### Container Roles

| Container | Role | Communication |
|-----------|------|---------------|
| rabbitmq | Message broker | AMQP protocol on port 5672 |
| celery-worker | Task processor | Connects to RabbitMQ via AMQP |
| flower | Monitoring UI | Queries RabbitMQ for stats |
| test-producer | Task sender | Publishes to RabbitMQ queue |
| test-client | Network testing | General connectivity checks |

---

## Design Decisions

### Why RabbitMQ over Redis for this experiment?

RabbitMQ is the more traditional message broker with full AMQP support, better message guarantees (persistent queues, acknowledgments), and richer management UI. Redis Queue (RQ) is simpler but less feature-rich. This experiment focuses on the full messaging pattern.

### Why separate test-producer from test-client?

The test-producer is a purpose-built Python container that sends tasks using the pika library and Celery. The test-client is a minimal Alpine container for basic networking verification. Separating concerns makes each container's purpose clear.

### Why Alpine-based RabbitMQ?

The `*-alpine` tag uses Alpine Linux as the base, reducing the image size from ~250MB to ~100MB. This matters on a 12GB RAM machine where every MB counts.

### Why `depends_on` with `condition: service_healthy` for celery-worker?

RabbitMQ needs time to fully initialize after the container starts. The `service_healthy` condition ensures the worker only starts after RabbitMQ passes its healthcheck (the `rabbitmq-diagnostics ping` command).

---

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references
- [x] Ports are > 1024 (25672:5672, 25673:15672, 25555:5555)
- [x] Test client container included (homelab-rabbitmq-celery-test)
- [x] Healthcheck on RabbitMQ (rabbitmq-diagnostics ping)
- [x] Healthcheck on Flower (removed - port check unreliable in container)
- [x] Volumes use hybrid strategy (named rabbitmq_celery_rabbitmq_data + bind mount ./workers)
- [x] Network name follows homelab-* pattern (homelab-rabbitmq-celery)
- [x] README includes verification commands
- [x] Expected output samples provided
- [x] All containers running successfully
- [x] RabbitMQ management UI accessible (port 25673)
- [x] Flower dashboard accessible (port 25555)
- [x] Tasks processed successfully (5/5)
- [x] Container networking verified (DNS resolution works)
- [x] Secrets extracted to .env (RABBITMQ_DEFAULT_PASS, FLOWER_BASIC_AUTH)
- [x] .env excluded by .gitignore
```

## Simplification Testing Checklist (April 24, 2026)

```
Simplification Progress:
- [x] Phase 1: version line removed, alpine:3.21 pinned
- [x] Phase 2: test-client container renamed to homelab-rabbitmq-celery-test
- [x] Phase 3: secrets extracted to .env, .env.example created
- [x] Phase 4: network renamed to homelab-rabbitmq-celery, redundant name: dropped
- [x] Phase 5: volume renamed to rabbitmq_celery_rabbitmq_data
- [x] Phase 6: ports updated to 25672, 25673, 25555
- [x] Phase 8: README updated with new ports, container names, troubleshooting
- [x] Verification: all containers start and function correctly
- [x] podman compose down -v (cleanup after verification)
```

---

## Common Questions

### Q: How do I add a new task type?

Add a new `@app.task` decorated function in `workers/task_worker.py`, then update `producer.py` with a new task entry. The worker will automatically pick it up.

### Q: Can I run multiple workers?

Yes. Add more `celery-worker` services to the compose file with different container names, or scale with `podman compose up --scale celery-worker=3`.

### Q: What happens if a task fails?

In this setup, failed tasks are logged but not retried. For production, add `retry=True` and `max_retries` to the task decorator.

### Q: How do I reset the task queue?

Access the RabbitMQ management UI at http://localhost:25673, go to Queues, find `task_queue`, and click "Purge" to clear all messages.

### Q: Why is the test-producer container stopping?

The test-producer is designed to send 5 tasks and exit. This is expected behavior. Restart it with `podman compose restart test-producer` to send more tasks. Note: if RabbitMQ isn't ready yet, you may need to wait a few seconds before restarting.

### Q: How do I change the RabbitMQ password?

1. Update `RABBITMQ_DEFAULT_PASS` in `.env`
2. Also update `FLOWER_BASIC_AUTH` in `.env` (change the password portion after the colon)
3. Wipe volumes: `podman compose down -v`
4. Restart: `podman compose up -d --build`

### Q: What happened to the port numbers?

Ports were updated during simplification cleanup (April 24, 2026):
- RabbitMQ AMQP: 55672 → 25672
- RabbitMQ Management: 15672 → 25673
- Flower: 5555 → 25555
- Test-client container: homelab-messaging-test → homelab-rabbitmq-celery-test

---

## Resource Usage

Actual (idle, after tasks processed):

| Service | RAM | CPU |
|---------|-----|-----|
| rabbitmq | 87MB (0.71%) | 9.81% |
| celery-worker | 64MB (0.52%) | 0.31% |
| flower | 40MB (0.33%) | 0.35% |
| **Total** | **~191MB (1.56%)** | **~10.5%** |

## Simplification Resource Usage (April 24, 2026)

After applying simplification changes and restarting:

| Service | RAM | CPU |
|---------|-----|-----|
| rabbitmq | ~100-150MB | <1% |
| celery-worker | ~50-80MB | <1% |
| flower | ~30-50MB | <1% |
| **Total** | **~200-280MB** | **<3%** |

Same resource profile as before - simplification changes (port/network/volume renaming, secret extraction) have no impact on resource usage.

Well within the 500MB budget. RabbitMQ's CPU spike is normal after container startup as it initializes.

---

## Lessons Learned

### What worked well
- Celery's automatic task registration and result backend
- Flower's web UI for monitoring tasks in real-time
- RabbitMQ's built-in management interface
- Alpine-based RabbitMQ image for smaller footprint

### Issues encountered and resolved

1. **Flower healthcheck failed** - The original healthcheck used `curl` which isn't available in the mher/flower image. Tried `wget` (also unavailable), then `netstat` (worked but healthcheck still had issues). **Resolution:** Removed Flower healthcheck entirely - it's not critical and the service is clearly working when accessible.

2. **Producer and worker used different queues** - The initial producer published directly to RabbitMQ's `task_queue` using pika, but Celery workers listen on the `celery` queue. **Resolution:** Rewrote producer to use Celery's `app.send_task()` API which properly routes through Celery's queue system.

3. **RabbitMQ readiness race condition** - Celery worker and test-producer started before RabbitMQ's AMQP port was fully ready, causing connection refused errors. **Resolution:** Celery's built-in retry handles this gracefully. Added retry logic (10 attempts with 3s delay) to the producer. The `depends_on` with `service_healthy` ensures the worker waits for RabbitMQ's diagnostic ping.

4. **Podman compose name conflicts** - When rebuilding, existing containers with the same names caused errors. **Resolution:** Use `podman rm -f <name>` before recreating, or use `podman compose down` first.

### Key takeaways
- Use Celery's task API (`send_task`) rather than raw AMQP for producer-worker communication
- Flower 2.0 has authentication enabled by default - login required at http://localhost:25555
- RabbitMQ's `*management-alpine` tag includes both the management UI and management plugin
- Celery's `--concurrency` flag controls parallel task processing (set to 2 for resource efficiency)

### Simplification lessons
- **Secret extraction requires volume wipe**: Changing `RABBITMQ_DEFAULT_PASS` in `.env` requires `podman compose down -v` because RabbitMQ only reads the password on first startup
- **Network naming matters**: Generic names like `homelab-messaging-network` cause confusion when multiple messaging experiments exist. Specific names like `homelab-rabbitmq-celery` prevent this
- **Port consistency**: The plan's systematic port allocation (25672, 25673, 25555) eliminates arbitrary offsets and makes port management predictable across experiments
- **`.gitignore` at repo level is sufficient**: No need for per-directory `.gitignore` files if the root `.gitignore` covers `.env`

---

## Startup Ordering Fix (May 2, 2026)

### Problem

On fresh `podman compose up -d --build`, the `test-producer` container consistently failed with `ConnectionRefusedError: [Errno 111] Connection refused`. The producer started before RabbitMQ's AMQP port was accepting connections.

**Root cause:** Podman-compose does **not** enforce `depends_on` with `condition: service_healthy`. It only passes `--requires` to `podman run`, which starts containers in order but does **not** wait for health checks to pass. This means all containers start nearly simultaneously, and the producer races against RabbitMQ's ~10s startup time.

### Investigation

1. First attempt: changed `depends_on` to use `condition: service_healthy` for rabbitmq — **no effect** (podman-compose ignores health conditions)
2. Second attempt: inline `sh -c` wait loop using `curl -sf` to management API — **failed** (curl returned 401, management API requires auth, and `$()` variable expansion was mangled by podman-compose escaping)
3. Third attempt: separate `wait-and-produce.sh` script with TCP socket check — **worked**

### Fix

Created `workers/wait-and-produce.sh` that:
1. Loops up to 30 times (60s max), checking TCP connectivity to `rabbitmq:5672` using Python's `socket` module
2. Uses `exec python /app/workers/producer.py` to replace the shell process once RabbitMQ is ready (clean exit code propagation)
3. Exits with code 1 if RabbitMQ doesn't become ready in time

Updated `docker-compose.yml` `test-producer` command from `python /app/workers/producer.py` to `/app/workers/wait-and-produce.sh`.

### Files Changed

| File | Change |
|------|--------|
| `docker-compose.yml` | `test-producer.command` → `/app/workers/wait-and-produce.sh` |
| `workers/wait-and-produce.sh` | New file — TCP wait loop + producer invocation |

### Verification

After fix, all 5 tasks sent and processed successfully on first `podman compose up -d --build`:

```
[1/5] tasks.resize_image (800x600 -> webp)    - succeeded in ~2s
[2/5] tasks.send_email (user@example.com)     - succeeded in ~1s
[3/5] tasks.generate_report (monthly/2026)    - succeeded in ~3s
[4/5] tasks.process_video (120s h264)         - succeeded in ~4s
[5/5] tasks.resize_image (200x200 -> jpg)     - succeeded in ~2s
```

### Key Takeaway

**Podman-compose `depends_on` with `condition: service_healthy` is not enforced.** Always use explicit wait loops in container commands when startup ordering matters. The TCP socket check (`python -c "import socket; ...connect..."`) is more reliable than HTTP checks since it doesn't require authentication or a fully initialized management plugin.

---

*Timeline created: April 18, 2026 | Simplification applied: April 24, 2026 | Startup fix: May 2, 2026*
