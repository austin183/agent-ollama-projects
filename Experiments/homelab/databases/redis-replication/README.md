# Redis Replication

Master-slave Redis replication setup demonstrating asynchronous single-master replication with password authentication.

## Overview

This experiment deploys a Redis primary (master) and replica (slave) to demonstrate how Redis replication works — asynchronous data propagation from a writable primary to read-only replicas.

## Quick Start

```bash
cd ~/homelab/databases/redis-replication
cp .env.example .env
podman compose up -d
```

## Services

| Service | Host Port | Purpose |
|---------|-----------|---------|
| redis-primary | 46379 | Redis master (writable) |
| redis-replica | 46380 | Redis replica (read-only) |
| test-client | — | Alpine container for testing connectivity |

## Setup

1. Copy `.env.example` to `.env` and set `REDIS_PASSWORD`:
   ```bash
   cp .env.example .env
   # Edit .env with your chosen password
   ```

2. Start the experiment:
   ```bash
   podman compose up -d
   ```

## Testing

```bash
# Source the password from .env
REDIS_PASSWORD=$(grep ^REDIS_PASSWORD .env | cut -d= -f2)
```

### Check health

```bash
# Primary should respond with PONG
REDIS_PASSWORD=$(grep ^REDIS_PASSWORD .env | cut -d= -f2)
podman exec homelab-redis-primary redis-cli -a "$REDIS_PASSWORD" ping

# Replica should also respond
podman exec homelab-redis-replica redis-cli -a "$REDIS_PASSWORD" ping
```

### Check replication status

```bash
# Primary should show 1 connected replica
REDIS_PASSWORD=$(grep ^REDIS_PASSWORD .env | cut -d= -f2)
podman exec homelab-redis-primary redis-cli -a "$REDIS_PASSWORD" INFO replication

# Replica should show connected to primary
podman exec homelab-redis-replica redis-cli -a "$REDIS_PASSWORD" INFO replication
```

### Test replication

```bash
# Write on primary
REDIS_PASSWORD=$(grep ^REDIS_PASSWORD .env | cut -d= -f2)
podman exec homelab-redis-primary redis-cli -a "$REDIS_PASSWORD" SET test:key "replication-test"

# Read from replica (should return after brief sync)
podman exec homelab-redis-replica redis-cli -a "$REDIS_PASSWORD" GET test:key
```

### Test replica is read-only

```bash
# Should fail with READONLY error
REDIS_PASSWORD=$(grep ^REDIS_PASSWORD .env | cut -d= -f2)
podman exec homelab-redis-replica redis-cli -a "$REDIS_PASSWORD" SET test:readonly "should-fail"
```

### Test from test-client

```bash
# Write on primary via test client
REDIS_PASSWORD=$(grep ^REDIS_PASSWORD .env | cut -d= -f2)
podman exec homelab-redis-replication-test redis-cli -h redis-primary -p 6379 -a "$REDIS_PASSWORD" SET from-test "hello"

# Read from replica via test client
podman exec homelab-redis-replication-test redis-cli -h redis-replica -p 6379 -a "$REDIS_PASSWORD" GET from-test
```

### Manual failover

```bash
# On replica: break replication and become writable
REDIS_PASSWORD=$(grep ^REDIS_PASSWORD .env | cut -d= -f2)
podman exec homelab-redis-replica redis-cli -a "$REDIS_PASSWORD" SLAVEOF NO ONE

# Now replica accepts writes
podman exec homelab-redis-replica redis-cli -a "$REDIS_PASSWORD" SET promoted "yes"
```

## Key Concepts

- **Asynchronous replication**: Writes on primary are not instantly propagated to replicas
- **Single-master**: Only the primary accepts writes
- **Read-only replicas**: Replicas reject writes by default (`READONLY` error)
- **Service name DNS**: Containers resolve each other by service name on the same network
- **Auto-reconnect**: If primary goes down, replica will attempt to reconnect
- **Password authentication**: `requirepass` enforces auth on all connections; `masterauth` allows replica to authenticate to primary

## Resource Usage

Redis is extremely lightweight — two instances total approximately 6MB RAM.

## Troubleshooting

### Replica can't connect to primary

If `master_link_status:down` after starting, check the replica config uses the correct service name:

```bash
grep replicaof ~/homelab/databases/redis-replication/conf/replica.conf
```

The `replicaof` directive must match the compose service name exactly: `replicaof redis-primary 6379` (not `primary`).

Fix it and restart:

```bash
podman compose down -v && podman compose up -d
```

### Primary shows 0 connected_slaves

Same root cause as above — verify the `replicaof` directive. Also check replica logs:

```bash
podman logs homelab-redis-replica | grep MASTER
```

### Authentication errors

If you see `WRONGPASS` errors, verify the password in `.env` matches between:
- `requirepass` in both `conf/primary.conf` and `conf/replica.conf` (via `${REDIS_PASSWORD}`)
- `masterauth` in `conf/replica.conf` (via `${REDIS_PASSWORD}`)

After changing the password, always run `podman compose down -v && podman compose up -d` to ensure configs are reloaded.

### Replica data directory not empty

Redis refuses to replicate into a non-empty data directory. If you see startup errors:

```bash
podman compose down -v && podman compose up -d
```

The `-v` flag ensures clean data directories for fresh replication sync.

## Cleanup

```bash
podman compose down
```

### Stop and Remove Data

```bash
podman compose down -v
```
