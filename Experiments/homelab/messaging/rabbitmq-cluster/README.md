# RabbitMQ Cluster with Quorum Queues

## Overview

3-node clustered RabbitMQ with Celery workers, Flower monitoring, and end-to-end message verification. Demonstrates automatic cluster formation, quorum queues, and distributed task processing.

## Quick Start

```bash
cd ~/homelab/messaging/rabbitmq-cluster
cp .env.example .env
# Edit .env — replace CHANGE_ME values with your credentials
podman compose up -d
```

## Services

| Service | Host Port | Container Port | Purpose |
|---------|-----------|----------------|---------|
| rabbitmq1 | 35672 | 5672 | AMQP broker (node 1) |
| rabbitmq1 | 35673 | 15672 | Management UI (node 1) |
| rabbitmq1 | 35674 | 25672 | Cluster port (node 1) |
| rabbitmq2 | 35676 | 15672 | Management UI (node 2) |
| rabbitmq2 | 35677 | 25672 | Cluster port (node 2) |
| rabbitmq3 | 35679 | 15672 | Management UI (node 3) |
| rabbitmq3 | 35680 | 25672 | Cluster port (node 3) |
| flower | 35556 | 5555 | Celery monitoring dashboard |
| test-client | — | — | Alpine shell for testing |

## How It Works

This experiment demonstrates a 3-node RabbitMQ cluster with a complete message processing pipeline:

1. **rabbitmq1** (`homelab-rabbitmq1`, host ports 35672, 35673, 35674) is the first node to start
2. **rabbitmq2** (`homelab-rabbitmq2`, host ports 35676, 35677) auto-discovers and joins the cluster on startup
3. **rabbitmq3** (`homelab-rabbitmq3`, host ports 35679, 35680) auto-discovers and joins the cluster on startup
4. **cluster-init** (`homelab-rabbitmq-init`) verifies cluster formation, then exits
5. **celery-worker** (`homelab-celery-worker`) processes tasks from RabbitMQ using Celery
6. **flower** (`homelab-flower`, host port 35556) monitoring dashboard with Basic Auth
7. **test-producer** (`homelab-test-producer`) sends 5 sample tasks and exits
8. **test-client** (`homelab-rabbitmq-cluster-test`) provides an Alpine shell for connectivity testing

```
Host (localhost:35672)   --> homelab-rabbitmq1 (node1, AMQP broker)
Host (localhost:35673)   --> homelab-rabbitmq1 (management UI)
Host (localhost:35676)   --> homelab-rabbitmq2 (management UI)
Host (localhost:35679)   --> homelab-rabbitmq3 (management UI)
Host (localhost:35556)   --> homelab-flower (Celery monitoring)

Message flow:
  test-producer --> rabbitmq1 (AMQP) --> celery-worker (processes tasks) --> Flower (monitors)

rabbitmq1 <==> rabbitmq2 <==> rabbitmq3  (auto-discovery via rabbitmq.conf)

cluster-init  -->  verifies cluster formation, then exits
test-client   -->  Alpine shell for DNS/AMQP connectivity testing
```

### Cluster Formation

The official RabbitMQ Docker image handles clustering automatically via `rabbitmq.conf`:

- `cluster_formation.peer_discovery_backend = rabbit_peer_discovery_classic_config` tells RabbitMQ to use static node list discovery
- `cluster_formation.classic_config.nodes.*` lists all 3 nodes — each node reads the same config and auto-discovers the others
- `RABBITMQ_ERLANG_COOKIE` env var ensures all nodes share the same Erlang cookie for authentication
- `RABBITMQ_NODENAME` env var gives each node a unique identity (`rabbit@rabbitmq1`, etc.)
- `default_queue_type = quorum` ensures all new queues use the Raft-based quorum type (no data loss on failover)

### Celery Integration

- **Broker:** `amqp://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@rabbitmq1:5672//` (connects to rabbitmq1; all nodes serve the same queues)
- **Result backend:** `rpc://` (results stored in RabbitMQ queues)
- **Concurrency:** 2 workers (resource-efficient for 12GB RAM)
- **Task types:** resize_image, send_email, generate_report, process_video, echo

## Verification

```bash
# Check all containers are running (7 services)
podman ps --filter "name=rabbitmq" --filter "name=rabbitmq-cluster-test" --filter "name=celery" --filter "name=flower" --filter "name=test-producer"

# Verify cluster membership (should show 3 nodes)
podman exec homelab-rabbitmq1 rabbitmqctl cluster_status

# Check each node can ping the cluster
podman exec homelab-rabbitmq1 rabbitmq-diagnostics -q ping
podman exec homelab-rabbitmq2 rabbitmq-diagnostics -q ping
podman exec homelab-rabbitmq3 rabbitmq-diagnostics -q ping

# Verify DNS resolution from test-client
podman exec homelab-rabbitmq-cluster-test nslookup rabbitmq1
podman exec homelab-rabbitmq-cluster-test nslookup rabbitmq2
podman exec homelab-rabbitmq-cluster-test nslookup rabbitmq3

# Check user was created (should show homelab as administrator)
podman exec homelab-rabbitmq1 rabbitmqctl list_users

# Check management API
curl -s -u homelab:homelab123 http://localhost:35673/api/overview | python3 -m json.tool

# Re-run the test producer
podman compose up -d test-producer

# Check worker processed tasks
podman logs homelab-celery-worker | grep -E "Processing|Done|succeeded"

# Check Flower monitoring (with Basic Auth)
ENCODED=$(echo -n "homelab:homelab123" | base64)
podman exec homelab-rabbitmq-cluster-test wget -qO- --header="Authorization: Basic $ENCODED" http://flower:5555/ | head -5
```

### Expected Output

**Cluster status** (excerpt):
```
Running Nodes
  rabbit@rabbitmq1
  rabbit@rabbitmq2
  rabbit@rabbitmq3

Versions
  rabbit@rabbitmq1: RabbitMQ 3.13.7 on Erlang 26.2.5.16
  rabbit@rabbitmq2: RabbitMQ 3.13.7 on Erlang 26.2.5.16
  rabbit@rabbitmq3: RabbitMQ 3.13.7 on Erlang 26.2.5.16
```

**DNS resolution**:
```
$ podman exec homelab-rabbitmq-cluster-test nslookup rabbitmq1
Name: rabbitmq1.dns.podman
Address: <CONTAINER_IP>
```

**Celery worker task processing** (all 5 tasks succeed):
```
Task tasks.resize_image[3d187660...] received
[resize_image] Processing: 800x600 -> webp
Task tasks.send_email[3301b783...] received
[send_email] Sending to user@example.com: Hello from Celery
Task tasks.resize_image[3d187660...] succeeded in 2.01s
Task tasks.send_email[3301b783...] succeeded in 1.01s
Task tasks.generate_report[90e88245...] succeeded in 3.00s
Task tasks.process_video[4a99d963...] succeeded in 4.00s
Task tasks.resize_image[29be6f60...] succeeded in 2.00s
```

**Flower monitoring** (returns HTML with auth):
```html
<!doctype html>
<html lang="en">
<head>
<title>Flower</title>
```

**Resource usage** (typical):
| Container | Memory |
|-----------|--------|
| homelab-rabbitmq1 | ~87MB |
| homelab-rabbitmq2 | ~82MB |
| homelab-rabbitmq3 | ~81MB |
| homelab-celery-worker | ~64MB |
| homelab-flower | ~40MB |
| homelab-rabbitmq-cluster-test | ~2MB |
| **Total** | **~356MB** |

## Common Pitfalls

- **`RABBITMQ_CLUSTER_COOKIE` vs `RABBITMQ_ERLANG_COOKIE`**: The `.env` file can use any variable name, but the Docker image expects `RABBITMQ_ERLANG_COOKIE` as the environment variable. Map correctly in compose.
- **Config key naming**: RabbitMQ 3.13 uses underscores (`cluster_formation`), not camelCase (`clusterformation`). The config error messages suggest the correct name.
- **`set_policy` for quorum queues is deprecated**: Quorum queues are the default since RabbitMQ 3.9. Use `default_queue_type = quorum` in config instead.
- **`rabbitmqctl` without `--node`**: When running from cluster-init (a separate container), always specify `--node rabbit@rabbitmq1` to target the correct node.
- **Stale data**: Always run `podman compose down -v` before rebuilding after config changes. Old Mnesia data can cause cluster formation failures.
- **`cluster-init` exits after verification**: It's a one-shot container that checks cluster health then stops. Recreate with `podman compose up -d --force-recreate cluster-init` if you need to re-verify.
- **Healthcheck on all nodes**: Podman-compose doesn't inherit healthchecks from images. Each RabbitMQ node needs its own healthcheck block in the compose file.
- **Producer timing**: The test-producer needs a startup delay (`sleep 15`) because the celery-worker also takes time to connect to RabbitMQ. `depends_on` with `service_healthy` only checks the RabbitMQ node, not the worker's connection state.
- **Broker URL must match service name**: In the cluster, the service is `rabbitmq1` not `rabbitmq`. Update `CELERY_BROKER_URL` accordingly.
- **Flower requires Basic Auth header**: The Alpine test-client uses BusyBox wget which doesn't support `--http-user`. Use `--header="Authorization: Basic $(echo -n 'user:pass' | base64)"` instead.
- **Celery uses classic queues by default**: The `default_queue_type = quorum` in rabbitmq.conf only applies to queues created via the management UI/API. Celery auto-creates queues via AMQP which uses classic queues. Use `queue_arguments={'x-queue-type': 'quorum'}` in Celery queue definitions for quorum queues.

## Accessing the Management UI

```bash
# RabbitMQ Management UI
# Browser -> http://localhost:35673
# Username: homelab
# Password: homelab123

# Each node has its own management port:
# rabbitmq1: http://localhost:35673
# rabbitmq2: http://localhost:35676
# rabbitmq3: http://localhost:35679
```

## Flower Dashboard

```bash
# Browser -> http://localhost:35556
# Username: homelab
# Password: homelab123

# API endpoints (from test-client):
ENCODED=$(echo -n "homelab:homelab123" | base64)
podman exec homelab-rabbitmq-cluster-test wget -qO- --header="Authorization: Basic $ENCODED" http://flower:5555/api/worker/celery-worker
```

The Flower dashboard shows:
- **Overview:** Broker connection status, worker status, task rates
- **Tasks:** History of all processed tasks with success/failure status
- **Inspect:** Active tasks, reserved tasks, registered tasks
- **Monitor:** Real-time task rate and execution time graphs

## Connecting via AMQP

```bash
# From test-client
podman exec -it homelab-rabbitmq-cluster-test sh

# Install amqp-tools for basic testing
apk add --no-cache amqp-tools

# Publish a test message
amqp-publish -u amqp://homelab:homelab123@rabbitmq1:5672/ -r test_queue -b "Hello RabbitMQ!"

# Consume from the queue
amqp-consume -u amqp://homelab:homelab123@rabbitmq1:5672/ -q test_queue sleep 1
```

## Troubleshooting

- **Cluster not forming**: Check that all nodes share the same `RABBITMQ_CLUSTER_COOKIE` in `.env`. Run `podman compose down -v` to clear stale Mnesia data, then `podman compose up -d`.
- **Can't connect to management UI**: Verify host ports are correct (35673, 35676, 35679). Rootless Podman cannot bind ports < 1024.
- **Celery worker can't connect**: Ensure `CELERY_BROKER_URL` uses the service name `rabbitmq1` (not `localhost`). The broker URL credentials must match `.env` values.
- **Flower returns 401**: Use the `FLOWER_BASIC_AUTH` value from `.env` (format: `username:password`). Encode with base64 for the Authorization header.
- **Port conflicts**: Check with `ss -tlnp | grep -E '3567[2-4]|3567[5-7]|3567[8-0]|3555[0-9]'` before starting.

## Cleanup

```bash
podman compose down          # Stop containers, keep data
podman compose down -v       # Stop containers and remove volumes (data loss)
```

## Current Status

**Phase 8 Complete** — All simplification phases applied and verified:
- 3-node RabbitMQ cluster with automatic formation
- Celery worker processing tasks successfully
- Flower monitoring dashboard with authentication
- Test producer sending and verifying 5 task types
- All tasks processed with success (no failures)
