# Loki Logging Stack

Centralized log aggregation using Grafana Loki and Promtail.

## Services

| Service | Port | Purpose |
|---------|------|---------|
| Loki | 3100 | Log ingestion, storage, and querying |
| Promtail | — | Log shipper (tails /var/log/*.log) |
| Grafana | 3001 | Web UI for log exploration |

## How It Works

```
[Host /var/log/*.log] --> [Promtail container] --> [Loki container] --> [Grafana]
                              |                        |
                              v                        v
                         Ships logs              Stores & indexes
                         to Loki API              logs on disk
```

**Loki** is a log aggregation system designed to work with Grafana. Unlike ELK, Loki doesn't index the full log content - instead it only indexes labels (metadata), making it much more storage-efficient.

**Promtail** is the log shipper that runs on each host, tailing log files and sending them to Loki.

**Grafana** provides the UI for querying and visualizing logs via LogQL.

### Architecture

- **Loki** (port 3100): Receives, stores, and serves log data. Uses filesystem storage with WAL for durability.
- **Promtail** (port 9080 internal): Tails log files from `/var/log/*.log` and pushes to Loki via HTTP push API.
- **Grafana** (port 3001): Web UI for log exploration. Loki data source is pre-provisioned.

### Network

All services run on an isolated `homelab-observability-network` bridge network. This experiment is self-contained and does not depend on any other experiment.

## Quick Start

Start the logging stack:

```bash
cd ~/homelab/observability/loki-logging

# Create .env from template and set a strong password
cp .env.example .env
sed -i 's/changeme/your-strong-password/' .env
```

Edit `.env` to replace `your-strong-password` with an actual password.

```bash
podman compose up -d
```

Wait ~30 seconds for containers to become healthy:

```bash
# All services should show "healthy" or "Up"
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Then open **http://localhost:3001** (admin / password you set in `.env`). The Loki data source is already configured.

## Verification

### Check services are running

Expected output (from `podman ps`):
```
homelab-loki         Up (healthy)   0.0.0.0:3100->3100/tcp
homelab-promtail     Up
homelab-grafana      Up (healthy)   0.0.0.0:3001->3000/tcp
homelab-loki-logging-test  Up
```

### Verify Loki is ready
```bash
curl -s http://localhost:3100/ready
```
Expected: `ready`

### Verify Grafana is ready
```bash
curl -s http://localhost:3001/api/health
```
Expected: `{"commit":"...","database":"ok","version":"..."}`

### Verify Loki data source is configured

```bash
GF_SECURITY_ADMIN_PASSWORD=$(grep ^GF_SECURITY_ADMIN_PASSWORD .env | cut -d= -f2)
curl -s -u admin:$GF_SECURITY_ADMIN_PASSWORD http://localhost:3001/api/datasources | python3 -m json.tool
```
Expected: A Loki data source with URL `http://loki:3100`

### Verify Loki data source health

```bash
GF_SECURITY_ADMIN_PASSWORD=$(grep ^GF_SECURITY_ADMIN_PASSWORD .env | cut -d= -f2)
curl -s -u admin:$GF_SECURITY_ADMIN_PASSWORD http://localhost:3001/api/datasources/uid/P8E80F9AEF21F6940/health
```
Expected: `{"message":"Data source successfully connected.","status":"OK"}`

### Verify Promtail is collecting logs
```bash
curl -s http://localhost:3100/loki/api/v1/series?match%5B%5D=%7B%7D | python3 -m json.tool
```
Expected: List of log files (dpkg.log, bootstrap.log, alternatives.log, etc.)

### Query logs via API
```bash
# Query varlogs from the last hour
END=$(date +%s) && START=$((END - 3600))
curl -s "http://localhost:3100/loki/api/v1/query_range?query=%7Bjob%3D%22varlogs%22%7D&start=${START}000000000&end=${END}000000000" | python3 -m json.tool
```

### Test connectivity from test client
```bash
podman exec homelab-loki-logging-test wget -qO- http://loki:3100/ready
podman exec homelab-loki-logging-test wget -qO- http://promtail:9080/ready
```
Expected: Both return `ready`

### View container logs
```bash
podman logs homelab-loki
podman logs homelab-promtail
podman logs homelab-grafana
```

## Grafana

- **URL:** http://localhost:3001
- **Credentials:** admin / set in `.env` as `GF_SECURITY_ADMIN_PASSWORD`
- **Loki data source:** Pre-configured and set as default
- **To query logs:** Go to **Explore** → select **Loki** as data source → enter a LogQL query

### Log Query Examples (LogQL)

```
# All varlogs
{job="varlogs"}

# Specific log file
{filename="/var/log/dpkg.log"}

# Filter by content
{job="varlogs"} |= "error"

# Filter by content with regex
{job="varlogs"} |~ "status (installed|removed) .+"
```

## Resource Usage

- **Loki**: ~50-100MB RAM
- **Promtail**: ~10-20MB RAM
- **Grafana**: ~100-200MB RAM
- **Storage**: ~1-3GB/week (logs + Grafana data)

## Stopping the Experiment

```bash
cd ~/homelab/observability/loki-logging
podman compose down       # Stop containers, keep data
podman compose down -v    # Stop and remove data volumes
```

## Common Pitfalls

1. **Permission denied errors in Promtail**: Some system log files (auth.log, syslog, kern.log) are owned by root:syslog and not readable by the container user in rootless Podman. Promtail skips these files gracefully.

2. **Promtail config not reloading**: Promtail's file watcher may not detect config changes via bind mounts in rootless Podman. Restart the container after config changes: `podman compose restart promtail`

3. **Loki config version mismatches**: Loki 3.x removed several config fields from older versions. Use only fields documented for your version.

4. **Time range limits**: Loki queries have a 30-day time range limit by default. Use appropriate start/end timestamps.

5. **Grafana data source URL must use service name**: From within the Grafana container, `localhost` resolves to IPv6 `[::1]` which doesn't reach Loki. Always use the container service name: `http://loki:3100` (not `http://localhost:3100`).

6. **Adding data sources via the UI**: If you add a Loki data source through the Grafana UI, ensure the URL is `http://loki:3100` (service name). Using `localhost` will fail with "Unable to connect".
