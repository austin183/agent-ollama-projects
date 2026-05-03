# Prometheus + Grafana Experiment Timeline

**Date:** April 17, 2026  
**Experiment:** Domain 3A - Observability & Monitoring Stack  
**Status:** ✅ Complete and Running

---

## Simplification Cleanup (April 24, 2026)

Applied per-experiment simplification plan phases 1-8 and 3 (secret hygiene).

### Changes Made

| Phase | Change | Before | After |
|-------|--------|--------|-------|
| 1 | Removed `version: '3.8'` line | Present | Removed |
| 1 | Pinned Alpine test-client tag | `alpine:latest` | `alpine:3.21` |
| 2 | Test-client container name | `homelab-test-client` | `homelab-prometheus-grafana-test` |
| 3 | Extracted Grafana admin password | Hardcoded `changeme123` | `${GF_SECURITY_ADMIN_PASSWORD}` in `.env` |
| 3 | Created `.env` file | N/A | `GF_SECURITY_ADMIN_PASSWORD=urCdxjVvlRR3RbUKT/RSYV6IokkeUpX5` |
| 3 | Created `.env.example` file | N/A | Placeholder with comments |
| 4 | Renamed network key | `homelab-observability-network` | `homelab-prometheus-grafana` |
| 4 | Dropped redundant `name:` field | `name: homelab-observability-network` | Removed |
| 5 | Renamed Prometheus volume | `prometheus_data` | `prometheus_grafana_prometheus_data` |
| 5 | Renamed Grafana volume | `grafana_data` | `prometheus_grafana_grafana_data` |
| 6 | Fixed Grafana host port | `3001:3000/tcp` | `3000:3000/tcp` |
| 8 | Updated README | Missing Overview, Testing, Troubleshooting, Cleanup | Added all sections per template |

### Verification Results

```bash
# All containers started successfully
podman ps --filter label=io.podman.compose.project=prometheus-grafana

# Prometheus health check passed
podman exec homelab-prometheus-grafana-test wget -q -O- http://prometheus:9090/-/healthy
# Output: "Prometheus Server is Healthy."

# Grafana health check passed
podman exec homelab-prometheus-grafana-test wget -q -O- http://grafana:3000/api/health
# Output: {"database":"ok","version":"11.1.0"}

# Node Exporter metrics accessible
podman exec homelab-prometheus-grafana-test wget -q -O- http://node_exporter:9100/metrics | head -5
# Output: Prometheus-style metrics

# Grafana accessible from host on port 3000
curl http://localhost:3000/api/health
# Output: {"database":"ok","version":"11.1.0"}
```

### No Issues Encountered

All changes applied cleanly. No port conflicts (port 3000 was free). The `podman compose down -v` cleaned up old volumes before creating new ones with renamed paths.

---

## Setup Phase

### 1. Initial Attempt (Port Conflict)

**Action:** Created `docker-compose.yml` with Grafana on port 3000

**Error:**
```
Error: rootlessport listen tcp 0.0.0.0:3000: bind: address already in use
```

**Root Cause:** Port 3000 was already in use by another rootlessport process (PID 54346)

**Resolution:** Changed Grafana host port to 3001
```yaml
ports:
  - "3001:3000/tcp"  # Host:Container mapping
```

### 2. Restart Services

```bash
podman compose down && podman compose up -d
```

**Result:** All 4 containers started successfully
- ✅ homelab-prometheus (healthy)
- ✅ homelab-grafana (healthy)
- ✅ homelab-node-exporter (running)
- ✅ homelab-test-client (running)

---

## Verification Phase

### Connectivity Tests

**From test-client container:**
```bash
podman exec homelab-test-client wget -q -O- http://prometheus:9090/-/healthy
# Output: "Prometheus Server is Healthy."

podman exec homelab-test-client wget -q -O- http://grafana:3000/api/health
# Output: {"commit":"...","database":"ok","version":"11.1.0"}
```

**From host:**
```bash
curl http://localhost:9090/api/v1/query?query=node_load1
# Output: {"status":"success","data":{"resultType":"vector","result":[{"metric":{"__name__":"node_load1","instance":"node_exporter:9100","job":"node_exporter"},"value":[1776471813.032,"0.91"]}]}}
```

**Interpretation:**
- Host load average is 0.91 (under 1.0 = good, CPU has capacity)
- Node exporter is successfully scraping host metrics
- Prometheus is storing and serving the data

---

## Configuration Phase

### Grafana Data Source Setup

**Steps Taken:**
1. Opened http://localhost:3001
2. Logged in with `admin` / `changeme123`
3. Navigated to **Connections** → **Data sources** → **Add data source**
4. Selected **Prometheus**
5. Entered URL: `http://prometheus:9090` (service name, works inside container network)
6. Clicked **Save & test** → **Success**

**Why `prometheus:9090` not `localhost:9090`:**
- Grafana runs in its own container
- Service names resolve via Docker network DNS
- `prometheus` = service name in `docker-compose.yml`
- `localhost` from Grafana's perspective = Grafana container itself

### Dashboard Import

**Action:** Imported pre-built Node Exporter Full dashboard

1. **Dashboards** → **Import**
2. Entered ID: `1860`
3. Selected **Prometheus** as data source
4. Clicked **Import**

**What Dashboard 1860 Shows:**
- CPU usage per core (user, system, idle, iowait)
- Memory usage (used, free, cached, buffers)
- Swap usage
- Disk I/O (reads/writes per second, bytes)
- Disk space usage by mount point
- Network traffic (bytes in/out per interface)
- System load average (1m, 5m, 15m)
- Temperature sensors (if available on hardware)
- Uptime

---

## Architecture Explanation

### How It Works

```
┌─────────────────┐
│  Host System    │
│  (Dell 5502)    │
│  /proc, /sys    │
└────────┬────────┘
         │ (read-only mounts)
         ▼
┌─────────────────┐
│ node_exporter   │◄─── Exposes /metrics endpoint
│ :9100           │     with host metrics
└────────┬────────┘
         │ (scraped every 15s)
         ▼
┌─────────────────┐
│  prometheus     │◄─── Stores time-series data
│  :9090          │     Configured in prometheus.yml
└────────┬────────┘
         │ (queries)
         ▼
┌─────────────────┐
│  grafana        │◄─── Visualizes data from Prometheus
│  :3001          │     Dashboards, alerts, queries
└─────────────────┘
         │
         ▼
    Your Browser
```

### Key Concepts

**1. Scraping Model**
- Prometheus **pulls** metrics (not pushed)
- Every 15 seconds, queries configured targets
- Stores each metric with timestamp and labels

**2. Service Discovery**
- In compose file: `targets: ['node_exporter:9100']`
- Docker DNS resolves `node_exporter` to container IP
- No hardcoded IPs needed

**3. Time-Series Data**
- Each metric is a series of (timestamp, value) pairs
- Labels add dimensions: `{job="node_exporter", instance="node_exporter:9100"}`
- Queries can filter by labels: `node_cpu_seconds_total{mode="idle"}`

**4. Volume Persistence**
- `prometheus_data:/prometheus` - metrics survive container restarts
- `grafana_data:/var/lib/grafana` - dashboards, users, settings persist
- Managed by Podman, typically in `~/.local/share/containers/storage/volumes/`

---

## Design Decisions

### Why Port 3001 Instead of 3000?
- Port 3000 was already in use on host
- Grafana's internal port stays 3000, host mapping changed to 3001
- Pattern: `"host_port:container_port"`

### Why Hybrid Volume Strategy?
- **Named volumes** for database internals (Prometheus TSDB, Grafana data)
  - Managed by Podman
  - Optimized for the application
- **Bind mounts** for configs (`./prometheus.yml`)
  - Editable on host
  - Version controlled

### Why Test Client Container?
- Provides isolated network testing environment
- Can query services by name (DNS resolution test)
- Useful for debugging connectivity issues
- **Decision:** Remove after setup (not needed for production)

### Why 15-Second Scrape Interval?
- Balance between freshness and storage
- Fast enough to see trends in real-time
- Slow enough to avoid overwhelming disk I/O
- Adjustable in `prometheus.yml` if needed

---

## Testing Checklist

- [x] Compose file uses full image references (`docker.io/prom/prometheus:v2.52.0`)
- [x] Ports are > 1024 (9090, 3000, 9100)
- [x] Test client container included with correct naming (`homelab-prometheus-grafana-test`)
- [x] Healthcheck port matches service config
- [x] Volumes use hybrid strategy (named + bind)
- [x] Network name follows `homelab-*` pattern (`homelab-prometheus-grafana`)
- [x] Secrets extracted to `.env` file
- [x] `.env.example` created with placeholder values
- [x] Verification commands documented
- [x] Expected output samples provided
- [x] README follows template (Overview, Quick Start, Services, Testing, Troubleshooting, Cleanup)

---

## Common Questions Answered

### Q: Why does Grafana need a data source configured?
**A:** Grafana is just a visualization layer. It needs to know where to get data from. Prometheus is the data source that stores the metrics.

### Q: Why can't I see metrics immediately?
**A:** Prometheus needs to scrape at least once (15s interval). Wait 15-30 seconds after startup, then check.

### Q: What if a target shows as DOWN?
**A:** Check:
1. Container is running: `podman ps`
2. Network connectivity: `podman exec homelab-test-client wget -q -O- http://node_exporter:9100/metrics`
3. Logs: `podman logs homelab-node-exporter`

### Q: Can I monitor other containers?
**A:** Yes, by:
1. Adding exporters to those containers (e.g., `postgres_exporter`)
2. Updating `prometheus.yml` with new scrape jobs
3. Adding containers to `homelab-observability-network`

### Q: How much disk space does this use?
**A:** 
- Initial: ~600MB (images)
- Runtime: ~2GB (15 days metrics retention)
- Grafana data: ~50MB (dashboards, users)

### Q: What's the difference between Prometheus and Grafana?
**A:** 
- **Prometheus** = Database that stores metrics
- **Grafana** = UI that queries and visualizes metrics
- Grafana can connect to many data sources (Prometheus, PostgreSQL, InfluxDB, etc.)

---

## Resource Usage

| Container | RAM (typical) | CPU | Storage |
|-----------|---------------|-----|---------|
| prometheus | 400-500 MB | 1-5% | 1-2 GB (grows with retention) |
| grafana | 200-300 MB | 1-3% | 50-100 MB |
| node_exporter | 10-20 MB | <1% | Negligible |
| **Total** | **~600-800 MB** | **~5-10%** | **~2 GB** |

**Within budget:** ✅ (budget was 800MB RAM, 2GB storage)

---

## Next Steps

1. **Change Grafana password** - Edit `docker-compose.yml` or use UI
2. **Add more dashboards** - Import IDs 16124 (Prometheus metrics), 11720 (Container metrics)
3. **Configure alerts** - Set up notifications for disk >80%, RAM >90%
4. **Monitor other experiments** - Add exporters to RabbitMQ, PostgreSQL, etc.
5. **Extend retention** - Adjust `--storage.tsdb.retention.time` if needed

---

## Lessons Learned

1. **Port conflicts happen** - Always check if port is in use before starting
2. **Service names are DNS** - Containers resolve each other by service name, not IP
3. **Health checks matter** - They tell you if services are actually ready
4. **Test clients are temporary** - Useful for setup, not needed in production
5. **Documentation should explain** - Not just what, but why (this timeline!)

---

## Commands Reference

```bash
# View all containers
podman ps --filter label=io.podman.compose.project=prometheus-grafana

# View logs
podman logs -f homelab-prometheus
podman logs -f homelab-grafana

# Check resource usage
podman stats --filter label=io.podman.compose.project=prometheus-grafana

# Test from host
curl http://localhost:9090/api/v1/query?query=node_cpu_seconds_total
curl http://localhost:3001/api/health

# Query Prometheus directly
curl "http://localhost:9090/api/v1/query?query=node_memory_MemTotal_bytes"

# View volume locations
podman volume inspect prometheus-grafana_prometheus_data

# Stop everything
podman compose down

# Stop and delete data (WARNING!)
podman compose down -v
```

---

**End of Experiment Timeline**  
**Next Experiment:** TBD based on learning goals
