# Redis Queue Experiment

**Experiment 1B** - Message Queues & Workers  
**Status:** Running  
**Date:** April 19, 2026

---

## Overview

This experiment demonstrates a lightweight message queue pattern using Redis as both a data store and task broker. A Python worker consumes tasks from a Redis list queue, processes them, and stores results back in Redis.

## Quick Start

```bash
cd ~/homelab/messaging/redis-queue
podman compose up -d --build
```

The `--build` flag is required on first run to build the custom worker and producer images. Subsequent runs after code changes also need `--build`.

Verify it's running:

```bash
podman exec homelab-redis redis-cli ping
# PONG
```

## How It Works

```
[producer] --> (RPUSH task_queue) --> [Redis] <-- (BLPOP task_queue) <-- [worker]
                                                        |
                                                  (process task)
                                                        |
                                                  (SET result:ID) --> [Redis]
                                                        |
[producer] <-- (GET result:ID) <-- [producer checks]
```

**Architecture:**
- **Redis** - Task broker (BLPOP for consumers, RPUSH for producers) with append-only persistence
- **Worker** - Python consumer using `blpop()` for blocking queue reads
- **Producer** - Python task generator that pushes tasks and polls for results
- **RedisInsight** - GUI for inspecting Redis data (host port 25540)

**Data Flow:**
1. Producer creates a task with a unique ID and pushes it to `task_queue`
2. Worker blocks on `blpop(task_queue)`, wakes when a task arrives
3. Worker processes the task and stores the result at `result:{task_id}` with 1-hour TTL
4. Producer polls for the result after a short delay

## Containers

| Container | Image | Port | Purpose |
|-----------|-------|------|---------|
| homelab-redis | redis:7.2-alpine | 26379 (host) → 6379 (container) | Redis server with AOF persistence |
| homelab-redis-worker | custom (python:3.11-slim) | - | Background task processor |
| homelab-redisinsight | redis/redisinsight:2.42.0 | 25540 (host) → 5540 (container) | Redis GUI viewer |
| homelab-redis-producer | custom (python:3.11-slim) | - | Task generator + result poller |
| homelab-redis-test | alpine:3.21 | - | Connectivity test client |

## Task Types

The worker supports three task types:

| Type | Description | Example |
|------|-------------|---------|
| `echo` | Returns payload unchanged | `{"message": "hello"}` |
| `hash` | SHA256 hash of input string | `{"input": "data"}` |
| `transform` | Uppercase strings, double numbers | `{"items": ["a", "b"]}` |

## Verification Commands

### Check container health
```bash
podman ps --filter 'name=homelab-redis'
```

Expected output:
```
CONTAINER ID  IMAGE                                    STATUS
85fd6d0bee41  docker.io/library/redis:7.2-alpine       Up (healthy)
ab17650a99e4  localhost/redis-queue_worker:latest      Up
e5120fa3b028  docker.io/redis/redisinsight:2.42.0      Up
3c7a86496554  docker.io/library/alpine:3.21            Up
8d0101b17b72  localhost/redis-queue_test-producer:latest  Up
```

### Test Redis connectivity
```bash
podman exec homelab-redis redis-cli ping
```
Expected: `PONG`

### Check queue depth
```bash
podman exec homelab-redis redis-cli LLEN task_queue
```
Expected: `0` when idle (tasks are consumed immediately)

### View worker logs
```bash
podman logs homelab-redis-worker
```

### Push a manual task
```bash
podman exec homelab-redis redis-cli RPush task_queue '{"id":"manual1","type":"echo","payload":{"message":"test"},"created_at":"2026-04-19T00:00:00Z"}'
```

### Check result
```bash
podman exec homelab-redis redis-cli GET result:manual1
```

### View resource usage
```bash
podman stats --no-stream --filter 'name=homelab-redis*'
```

### Test DNS resolution
```bash
podman exec homelab-redis-test ping -c 2 redis
podman exec homelab-redis-test ping -c 2 homelab-redis-worker
```

### RedisInsight GUI
Open http://localhost:25540 in a browser. Connect to `redis://redis:6379` (use container name `redis` as host inside the network).

## Stopping the Experiment

```bash
# Stop all services (preserves data in volumes)
podman compose down

# Stop and remove all data (named volumes are destroyed)
podman compose down -v
```

Two named volumes persist after `down` without `-v`:
- `messaging-redis-queue_redis_data` — Redis AOF persistence
- `messaging-redis-queue_redisinsight_data` — RedisInsight database

Use `down -v` when you want a fresh start or before changing compose configuration.

## Resource Usage

| Service | RAM | CPU |
|---------|-----|-----|
| Redis | ~3MB | <1% |
| Worker | ~19MB | <1% |
| RedisInsight | ~88MB | ~1% |
| Producer | ~19MB | <1% |
| **Total** | **~130MB** | **~3%** |

Well within the 300MB RAM budget and ~200MB storage estimate.

## Common Pitfalls

- **Python output buffering** - Use `PYTHONUNBUFFERED=1` environment variable or `flush=True` in prints
- **Task TTL** - Results are stored with 1-hour TTL (`SETEX`); old results expire automatically
- **Worker reconnection** - Worker handles Redis disconnections gracefully with 3-second retry
- **Port conflicts** - Redis uses host port 26379 (not privileged, works in rootless mode)
- **Network alias** - Containers resolve by service name (`redis`, `worker`) on the shared network

## Design Decisions

- **Redis 7.2 Alpine** - Lightweight image (~50MB), stable LTS version
- **Host port 26379** - Avoids conflicts with other Redis experiments (redis-experiment uses 16379, redis-replication uses 46379)
- **BLPOP vs Pub/Sub** - BLPOP provides reliable task delivery; pub/sub loses messages to unsubscribed consumers
- **List-based queue** - Simple, ordered, supports multiple consumers with race-free distribution
- **Result polling** - Producer polls for results rather than using a separate result queue (simpler for single-producer setup)
- **256MB maxmemory** - Prevents Redis from consuming too much RAM on the host
- **allkeys-lru eviction** - Evicts least recently used keys when memory limit is reached
