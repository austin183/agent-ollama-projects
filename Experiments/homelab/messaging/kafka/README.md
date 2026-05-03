# Kafka + Kafka-UI Log Aggregation Pipeline

**Experiment:** 1C - Phase 3: Messaging Domain  
**Date:** April 18-19, 2026  
**Status:** Complete

---

## Overview

This experiment demonstrates a complete Kafka log aggregation pipeline using:
- **Apache Kafka 3.9.0** in KRaft mode (no ZooKeeper dependency)
- **Kafka-UI** (provectuslabs) for web-based monitoring
- **Python worker** containers using `confluent-kafka` (librdkafka-based) for producing and consuming log events

### Architecture

```
                    ┌───────────────────────────────────────────┐
                    │              homelab-kafka              │
                    │                                           │
  ┌─────────┐       │  ┌───────────────────────────────────┐   │
  │producer │ ────▶ │  │              Kafka                │   │
  │(python) │       │  │             KRaft Mode            │   │
  │         │ ────▶ │  │                                   │   │
  └─────────┘       │  │  Topics:                          │   │
                    │  │  app.logs (1 partition)           │   │
                    │  │  app.errors (1 partition)         │   │
                    │  │  Retention: 168h (7 days)        │   │
                    │  └─────────────┬─────────────────────┘   │
                    │                │                         │
                    │  ┌─────────────┼─────────────┐           │
                    │  │             │             │           │
                    │  ▼             ▼             ▼           │
                    │  │ consumer  │ consumer  │ kafka-ui    │
                     │  │ group:app │group:analyst│ :28088    │
                    │  └───────────┘└───────────┘└───────────┘           │
                    └───────────────────────────────────────────┘
```

### Components

| Component | Image | Ports | Purpose |
|-----------|-------|-------|---------|
| kafka | `docker.io/apache/kafka:3.9.0` | 29092:9092, 29101:9101 | Kafka broker (KRaft mode) |
| kafka-ui | `docker.io/provectuslabs/kafka-ui:v0.7.2` | 28088:8080 | Web UI for monitoring |
| log-producer | custom (python:3.11-slim) | (internal) | Generates simulated log events |
| log-consumer | custom (python:3.11-slim) | (internal) | Processes/receives log events |
| test-client | `docker.io/alpine:3.21` | (internal) | Connectivity testing |

---

## Quick Start

### 1. Start the experiment

```bash
cd ~/homelab/messaging/kafka
podman compose up -d --build
```

### 2. Wait for Kafka to become healthy (~75 seconds)

```bash
podman ps --filter network=kafka_homelab-kafka
```

**Expected:** All 5 containers running, kafka status shows `(healthy)`

### 3. Verify the pipeline

```bash
# Check producer is delivering messages
podman logs homelab-kafka-producer | grep "delivered to"

# Check consumer is receiving messages
podman logs homelab-kafka-consumer | tail -10

# List topics
podman exec homelab-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list

# Access Kafka-UI
# Open http://localhost:28088 in browser
```

### 4. Stop the experiment

```bash
# Stop all services (keep data)
podman compose down

# Stop and remove volumes (WARNING: deletes Kafka data)
podman compose down -v
```

---

## How It Works

### Kafka Broker Setup

The official `apache/kafka` Docker image requires several patches to work reliably in a single-node container environment:

1. **Bypass the Docker wrapper** - The official image's wrapper script has Java-based validation that rejects `0.0.0.0` in listeners. We start `kafka-server-start.sh` directly via a custom entrypoint script.

2. **Patch `log.dirs`** - The `KAFKA_LOG_DIRS` environment variable is NOT honored by the `configure` script. We patch `server.properties` directly to write KRaft metadata to the Docker volume mount.

3. **Patch `advertised.listeners`** - The `KAFKA_ADVERTISED_LISTENERS` environment variable is also NOT honored. We patch `server.properties` to advertise `kafka:9092` (container hostname) instead of `localhost`.

The entrypoint script (`start-kafka.sh`) handles all of this automatically:

```bash
#!/bin/bash
. /etc/kafka/docker/configureDefaults
. /etc/kafka/docker/configure

# Patch log.dirs
LOG_DIRS="${KAFKA_LOG_DIRS:-/var/lib/kafka/data}"
sed -i "s|^log.dirs=.*|log.dirs=${LOG_DIRS}|" /opt/kafka/config/kraft/server.properties

# Patch advertised.listeners
if [ -n "$KAFKA_ADVERTISED_LISTENERS" ]; then
    PLAINTEXT_ADVERTISED=$(echo "$KAFKA_ADVERTISED_LISTENERS" | tr ',' '\n' | grep '^PLAINTEXT://' | head -1)
    if [ -n "$PLAINTEXT_ADVERTISED" ]; then
        sed -i "s|^advertised.listeners=.*|advertised.listeners=${PLAINTEXT_ADVERTISED}|" /opt/kafka/config/kraft/server.properties
    fi
fi

# Format storage if empty
mkdir -p "${LOG_DIRS}"
if [ -z "$(ls -A ${LOG_DIRS} 2>/dev/null)" ]; then
  CLUSTER_ID=$(/opt/kafka/bin/kafka-storage.sh random-uuid)
  echo "Formatting storage at ${LOG_DIRS} with cluster ID: ${CLUSTER_ID}"
  /opt/kafka/bin/kafka-storage.sh format -t "$CLUSTER_ID" -c /opt/kafka/config/kraft/server.properties
fi

exec /opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/kraft/server.properties
```

### Python Workers

We use **`confluent-kafka`** (librdkafka-based) instead of `kafka-python-ng` because:

- `kafka-python-ng` has a known compatibility issue with Kafka 3.x KRaft mode
- Produce requests with `acks=1` or `acks=all` never complete in `kafka-python-ng`
- `confluent-kafka` has excellent Kafka 3.x support and reliable KRaft handling

#### Producer

The producer generates realistic log events in JSON format and publishes them to Kafka topics:

```python
from confluent_kafka import Producer

conf = {
    'bootstrap.servers': BOOTSTRAP,
    'acks': 1,
    'retries': 3,
}
producer = Producer(conf)

# Delivery callback
def delivery_report(err, msg):
    if err:
        print(f"Delivery failed: {err}")
    else:
        print(f"Delivered to {msg.topic()} partition={msg.partition()} offset={msg.offset()}")

# Produce message
producer.produce(topic, value=json.dumps(event).encode('utf-8'), on_delivery=delivery_report)
producer.flush(10)
```

#### Consumer

The consumer reads messages from the `app.logs` topic and prints them:

```python
from confluent_kafka import Consumer

conf = {
    'bootstrap.servers': BOOTSTRAP,
    'group.id': GROUP_ID,
    'auto.offset.reset': 'earliest',
    'enable.auto.commit': True,
}
consumer = Consumer(conf)
consumer.subscribe([TOPIC])

# Poll for messages
while True:
    msg = consumer.poll(timeout=1.0)
    if msg is None:
        continue
    if msg.error():
        continue
    value = json.loads(msg.value())
    print(f"[{value['level']}] {value['service']}: {value['message']}")
```

---

## Verification Commands

### Check all containers

```bash
podman ps --filter network=kafka_homelab-kafka
```

**Expected output:**
```
NAMES                   STATUS
homelab-kafka           Up 2 minutes (healthy)
homelab-kafka-ui        Up 2 minutes
homelab-kafka-producer  Up 2 minutes
homelab-kafka-consumer  Up 2 minutes
homelab-kafka-test      Up 2 minutes
```

### Verify Kafka health

```bash
podman exec homelab-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list
```

**Expected output:**
```
__consumer_offsets
app.logs
app.errors
```

### Check producer deliveries

```bash
podman logs homelab-kafka-producer | grep "delivered to" | tail -5
```

**Expected output:**
```
  -> delivered to app.logs partition=0 offset=10
[INFO ] auth-service         Request processed in 1234ms
  -> delivered to app.errors partition=0 offset=1
[ERROR] payment-service      Payment processing error: invalid card
```

### Check consumer messages

```bash
podman logs homelab-kafka-consumer | tail -10
```

**Expected output:**
```
[2026-04-19T12:55:01.025102+00:00] [DEBUG] payment-service: Connection pool: 4/10 active
[2026-04-19T12:55:06.027278+00:00] [DEBUG] auth-service: Cache hit for key user:2828
[2026-04-19T12:55:11.029274+00:00] [WARN ] payment-service: High memory usage: 71%
```

### Test container networking

```bash
podman exec homelab-kafka-test sh -c '
apk add --no-cache curl > /dev/null 2>&1
curl -s http://kafka-ui:8080/api/clusters | head -c 200
'
```

### Inspect topic details

```bash
podman exec homelab-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --describe --topic app.logs
```

**Expected output:**
```
Topic: app.logs	TopicId: xxx	PartitionCount: 1	ReplicationFactor: 1	Configs: segment.bytes=1073741824
	Topic: app.logs	Partition: 0	Leader: 1	Replicas: 1	Isr: 1
```

---

## Resource Usage

| Service | RAM | CPU | Storage |
|---------|-----|-----|---------|
| kafka (KRaft) | ~400-500MB | 10-20% | ~200MB |
| kafka-ui | ~80-120MB | 5% | ~100MB |
| log-producer | ~50-80MB | <5% | minimal |
| log-consumer | ~40-60MB | <5% | minimal |
| **Total** | **~600-800MB** | **~30-40%** | **~350MB** |

Well within the 12GB RAM budget.

---

## Common Pitfalls

### KRaft metadata corruption

If Kafka fails to start with metadata errors, do a clean restart:

```bash
podman compose down -v
podman compose up -d --build
```

### Consumer group ID collision

Use different `KAFKA_CONSUMER_GROUP` values across experiments to avoid offset conflicts.

### Kafka-UI can't connect to Kafka

Kafka-UI connects via `kafka:9092` (internal network), not `localhost:29092` (external). Verify Kafka healthcheck passes first:

```bash
podman exec homelab-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list
```

### `advertised.listeners` not applied

Always verify the broker's advertised listeners after starting:

```bash
podman exec homelab-kafka /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka:9092 2>&1 | head -1
```

**Expected:** `kafka:9092 (id: 1 rack: null) -> (`

If you see `localhost:9092`, the `start-kafka.sh` script didn't patch the config correctly.

### `log.dirs` not honored

The `KAFKA_LOG_DIRS` env var is ignored by the Kafka Docker image's `configure` script. Always patch `server.properties` directly (handled by `start-kafka.sh`).

### Port conflicts

- Port 29092: External listener (mapped from container 9092)
- Port 28088: Kafka-UI (mapped from container 8080)
- Port 29101: JMX metrics

Check for conflicts before starting:

```bash
ss -tlnp | grep -E '29092|28088|29101'
```

---

## Experiment Scenarios

### Scenario 1: Observe the Pipeline

Let producer and consumer run for 10-15 minutes. Watch:
- Producer emitting log events every 5 seconds
- Consumer processing messages in real-time
- Kafka-UI showing live message rate charts
- Consumer group lag staying near zero

### Scenario 2: Consumer Restart & Replay

```bash
# Stop consumer
podman compose stop log-consumer

# Wait 30s (producer keeps running)

# Restart - consumer picks up where it left off (auto-commit)
podman compose start log-consumer

# To replay all messages, change auto_offset_reset to "earliest" in consumer.py
# and restart
```

### Scenario 3: Multiple Consumer Groups

```bash
# Start a second consumer with a different group
podman run --rm \
  --network homelab-kafka \
  -e KAFKA_BOOTSTRAP_SERVERS=kafka:9092 \
  docker.io/apache/kafka:3.9.0 \
  /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 \
    --topic app.logs --group debug-group --from-beginning --max-messages 5
```

Both groups receive the same messages independently (different offset tracking).

### Scenario 4: Produce Messages Manually

```bash
podman exec homelab-kafka /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka:9092 \
  --topic app.logs
# Type JSON messages manually (one per line)
```

---

## Files

```
messaging/kafka/
├── docker-compose.yml      # Service definitions
├── start-kafka.sh          # Custom entrypoint (patches config, formats storage)
├── workers/
│   ├── Dockerfile          # Worker image (Python + Java + confluent-kafka)
│   ├── producer.py         # Log event producer
│   └── consumer.py         # Log event consumer
├── experiment-timeline.md  # Detailed error log and debugging history
└── README.md               # This file
```

---

## Lessons Learned

1. **Use `confluent-kafka` for Kafka 3.x** - librdkafka has excellent KRaft support; `kafka-python-ng` has produce path failures
2. **Patch `advertised.listeners` in `server.properties`** - Environment variables are NOT honored for this setting
3. **Patch `log.dirs` in `server.properties`** - Environment variables are NOT honored for this setting either
4. **Bypass the Docker wrapper** for single-node KRaft - Use `start-kafka.sh` to format and start directly
5. **Always verify `advertised.listeners`** with `kafka-broker-api-versions.sh` after starting
6. **Clean `podman compose down -v`** is required when changing KRaft config
7. **`depends_on` is unreliable** in Podman Compose - always manually verify Kafka health before starting workers
8. **Full image references required** - Podman needs `docker.io/` prefix for images

---

## Next Steps

- Add a second Kafka broker for high-availability (requires cluster re-initialization)
- Implement dead-letter topic pattern for failed messages
- Integrate with Prometheus for Kafka metrics monitoring (Domain 3)
- Add schema validation with Confluent Schema Registry
- Compare throughput: RabbitMQ vs Kafka for the same workload

---

*Based on experiment 1C - Phase 3: Messaging Domain*  
*Created: April 19, 2026*
