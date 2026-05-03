# RabbitMQ + Celery Worker Pattern

**Phase 3 - Messaging Domain** | Experiment 1A

---

## How It Works

This experiment demonstrates the producer-consumer pattern using RabbitMQ as the message broker and Celery as the distributed task queue.

### Architecture

```
┌──────────────┐     amqp      ┌──────────────┐
│ test-producer│ ─────────────▶│   rabbitmq   │
│  (alpine)    │               │  :5672       │
└──────────────┘               │  queues:     │
                               │  task_queue  │
                               └──────┬───────┘
                                      │
                          ┌───────────┼───────────┐
                          │           │           │
                          ▼           ▼           ▼
                   ┌──────────┐ ┌──────────┐ ┌──────────┐
                   │  flower  │ │ celery-  │ │  test-   │
                   │  :5555   │ │ worker   │ │ producer │
                   │(monitor) │ │ (python) │ │ (alpine) │
                   └──────────┘ └──────────┘ └──────────┘
```

### Data Flow

1. **test-producer** sends JSON tasks to the `task_queue` on RabbitMQ
2. **celery-worker** subscribes to the queue and picks up tasks
3. Each task type (resize_image, send_email, etc.) is processed asynchronously
4. **flower** provides a web UI to monitor tasks, workers, and queue status
5. **test-client** can be used to verify container networking

### Task Types

| Task | Description | Processing Time |
|------|-------------|-----------------|
| `resize_image` | Simulates image resizing to dimensions | ~2s |
| `send_email` | Simulates sending an email | ~1s |
| `generate_report` | Simulates report generation | ~3s |
| `process_video` | Simulates video encoding | ~4s |
| `echo` | Simple echo task for testing | instant |

---

## Services

| Service | Image | Ports | Purpose |
|---------|-------|-------|---------|
| rabbitmq | `rabbitmq:3.13-management-alpine` | 25672:5672, 25673:15672 | Message broker + management UI |
| celery-worker | custom (python:3.11-slim) | (internal) | Processes queued tasks |
| flower | `mher/flower:2.0.1` | 25555:5555 | Celery monitoring dashboard |
| test-producer | custom (python:3.11-slim) | (internal) | Sends test tasks to queue |
| test-client | `alpine:3.21` | (internal) | Connectivity testing |

---

## Quick Start

### Start the experiment

```bash
cd ~/homelab/messaging/rabbitmq-celery
cp .env.example .env
podman compose up -d --build
```

### Access the services

- **RabbitMQ Management UI:** http://localhost:25673 (user: `homelab`, pass: `RABBITMQ_DEFAULT_PASS` from `.env`)
- **Flower Dashboard:** http://localhost:25555 (user: `homelab`, pass: password from `FLOWER_BASIC_AUTH` in `.env`)

### View logs

```bash
# All services
podman compose logs -f

# Individual services
podman logs -f homelab-rabbitmq
podman logs -f homelab-celery-worker
podman logs -f homelab-flower
podman logs -f homelab-test-producer
```

---

## Verification

### 1. Check all containers are running

```bash
podman ps --filter network=homelab-rabbitmq-celery
```

**Expected output:**

```
CONTAINER ID  IMAGE                              COMMAND         STATUS
abc123        docker.io/rabbitmq:3.13...         "docker-entryp..."  Up ...
def456        homelab-rabbitmq-celery_worker     "celery -A..."  Up ...
ghi789        docker.io/mher/flower:2.0.1        "/app/run_flower..."  Up ...
jkl012        docker.io/alpine:latest            "sleep 3600"  Up ...
```

### 2. Verify RabbitMQ is healthy

```bash
podman exec homelab-rabbitmq rabbitmq-diagnostics -q ping
```

**Expected output:**

```
ok
```

### 3. Check RabbitMQ management UI

Open http://localhost:25673 in your browser:
- Login: `homelab` / password from `.env` (`RABBITMQ_DEFAULT_PASS`)
- Navigate to **Queues** tab - should see `task_queue`
- Navigate to **Channels** tab - should show celery-worker connected

### 4. Check Flower dashboard

Open http://localhost:25555 in your browser:
- Login: `homelab` / password from `.env` (`FLOWER_BASIC_AUTH`)
- Should show the celery-worker as "alive"
- Tasks tab shows processed task history

### 5. Send a test task manually

```bash
podman exec homelab-test-client sh -c '
apk add --no-cache curl > /dev/null 2>&1
curl -s -X POST http://rabbitmq:5672/api/exchanges/%2F/amqp.default/publish \
  -u homelab:homelab123 \
  -H "content-type: application/json" \
  -d "{\"properties\":{},\"routing_key\":\"task_queue\",\"payload\":{\"vhost\":\"/\",\"exchange\":\"amqp.default\",\"routing_key\":\"task_queue\",\"args\":[],\"timestamp\":0,\"payload\":\"\\\"{\\\\\\\"task_type\\\\\\\":\\\\\\\"echo\\\\\\\",\\\\\\\"args\\\\\\\":[\\\\\\\"hello from test-client\\\\\\\"]}\\\"\",\"payload_encoding\":\"string\"}}"
'
```

Or use the test-producer container:

```bash
# Restart test-producer to send 5 sample tasks
podman compose restart test-producer
podman logs homelab-test-producer
```

**Expected producer output:**

```
Celery Producer - sending tasks via Celery...
Broker: amqp://homelab:homelab123@rabbitmq:5672//

[1/5] Sending tasks.resize_image...
      Task ID: 8525277c-73f1-4658-ade4-72c793fdd6e4
[2/5] Sending tasks.send_email...
      Task ID: 864bd218-4231-451f-bcc1-0755b170abca
[3/5] Sending tasks.generate_report...
      Task ID: 71a8955c-a45f-4836-9fd4-345803ab2df9
[4/5] Sending tasks.process_video...
      Task ID: e086189c-961d-4b72-98e5-ebd5775b1d62
[5/5] Sending tasks.resize_image...
      Task ID: 4ea2fff0-b36b-4f7d-8137-c65bbbdf909c

Done! 5 tasks sent to Celery.
Check the celery-worker logs to see tasks being processed.
Check Flower at http://localhost:25555 to monitor task status.
```

### 6. Check worker processed tasks

```bash
podman logs homelab-celery-worker | grep -E "\[resize_image\]|\[send_email\]|\[generate_report\]|\[process_video\]|\[echo\]"
```

**Expected output:**

```
[2026-04-18 19:01:35,290: INFO/ForkPoolWorker-2] [resize_image] Processing: 800x600 -> webp
[2026-04-18 19:01:36,294: INFO/ForkPoolWorker-1] [send_email] Sending to user@example.com: Hello from Celery
[2026-04-18 19:01:37,291: INFO/ForkPoolWorker-2] [resize_image] Done: {'original': '800x600', ...}
[2026-04-18 19:01:37,306: INFO/ForkPoolWorker-2] [generate_report] Generating monthly report for 2026
[2026-04-18 19:01:40,307: INFO/ForkPoolWorker-1] [process_video] Done: {'duration': 120, ...}
[2026-04-18 19:01:42,308: INFO/ForkPoolWorker-2] [resize_image] Done: {'original': '200x200', ...}
```

### 7. Test container networking

```bash
# DNS resolution between containers
podman exec homelab-rabbitmq-celery-test nslookup rabbitmq
podman exec homelab-rabbitmq-celery-test nslookup celery-worker
podman exec homelab-rabbitmq-celery-test nslookup flower
```

**Expected output:**

```
Server:    127.0.0.11
Address:   127.0.0.11:53

Name:      rabbitmq
Address:  172.x.x.x
```

---

## RabbitMQ Management UI Guide

After logging in at http://localhost:15672:

1. **Overview** - General stats on connections, channels, queues
2. **Connections** - Active connections (celery-worker, flower, test-producer)
3. **Queues** - See `task_queue` with message rates (ready/unacknowledged/delivered)
4. **Exchanges** - Default `amqp.default` exchange used by Celery
5. **Admin** - Manage users, vhosts, permissions

### Key metrics to watch

- **Ready messages**: Tasks waiting to be processed
- **Delivered messages**: Tasks being processed by workers
- **Publish rate**: How fast tasks are being submitted
- **Ack rate**: How fast tasks are being completed

---

## Flower Dashboard Guide

Access at http://localhost:25555:

1. **Overview** - Worker status, active tasks, succeeded/failed counts
2. **Tasks** - History of all tasks with results
3. **Inspect** - Live worker info (currently active tasks, concurrency)
4. **Monitor** - Real-time task rate graphs
5. **Auth** - Login required (homelab/homelab123)

---

## Common Pitfalls

### RabbitMQ management UI not accessible

The management plugin is included in the `*management*` tagged images. Make sure you're using `rabbitmq:3.13-management-alpine` not just `rabbitmq:3.13`.

### Celery worker can't connect to RabbitMQ

- Check that RabbitMQ healthcheck passes first: `podman exec homelab-rabbitmq rabbitmq-diagnostics -q ping`
- Verify credentials match in both RabbitMQ config and Celery BROKER_URL
- The `depends_on` with `condition: service_healthy` ensures RabbitMQ is ready

### Flower shows "No nodes responding"

- Flower needs the celery-worker to be registered. Check worker logs: `podman logs homelab-celery-worker`
- The worker registers with Flower via the broker, so both need RabbitMQ connectivity

### Port conflict on 25673

If 25673 is already in use, change the host port mapping:

```yaml
ports:
  - "25674:15672/tcp"
```

Then access http://localhost:25674 instead.

---

## Troubleshooting

### After changing secrets in .env, containers won't start

RabbitMQ only reads `RABBITMQ_DEFAULT_PASS` on first startup. If you changed the password in `.env`, you must wipe the volume:

```bash
podman compose down -v
podman compose up -d --build
```

### Flower shows "Authentication required" after changing FLOWER_BASIC_AUTH

Flower reads `FLOWER_BASIC_AUTH` on startup. If you changed it in `.env`, restart Flower:

```bash
podman compose restart flower
```

### Celery worker can't connect after password change

The `CELERY_BROKER_URL` in the compose file uses `${RABBITMQ_DEFAULT_PASS}`. If you changed the password:

1. Update `RABBITMQ_DEFAULT_PASS` in `.env`
2. Wipe volumes: `podman compose down -v`
3. Restart: `podman compose up -d --build`

### Cannot reach RabbitMQ Management UI

- Default URL: **http://localhost:25673** (host port 25673 → container port 15672)
- Login: `homelab` / password from `.env` (`RABBITMQ_DEFAULT_PASS`)
- Check container is running: `podman ps --filter network=homelab-rabbitmq-celery`
- Check logs: `podman logs homelab-rabbitmq | grep -i "management"`

## Resource Usage

Expected idle usage (all containers running, no tasks):

| Service | RAM | CPU |
|---------|-----|-----|
| rabbitmq | ~100-150MB | <1% |
| celery-worker | ~50-80MB | <1% |
| flower | ~30-50MB | <1% |
| **Total** | **~200-280MB** | **<3%** |

---

## Stop the experiment

```bash
# Stop all services (keep data)
podman compose down

# Stop and remove volumes (WARNING: deletes RabbitMQ data)
podman compose down -v
```

---

## Next Steps

- Try adding more task types in `task_worker.py`
- Experiment with Celery concurrency settings (`--concurrency=N`)
- Use Flower's "Inspect" tab to see live worker state
- Add a second celery-worker container for horizontal scaling
- Integrate with Prometheus for monitoring (Domain 3)
