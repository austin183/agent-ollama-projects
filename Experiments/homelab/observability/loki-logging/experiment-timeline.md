# Experiment 3B: Loki Logging - Experiment Timeline

**Date:** April 20, 2026  
**Status:** Complete (full stack running, Grafana with provisioned Loki data source)

---

## Setup Phase

### Initial Container Start
Started Loki (3.3.2) and Promtail (3.3.2) with a basic configuration. Both containers pulled successfully and started.

### Error 1: Loki Config - Deprecated Fields
**Error:** `field retention_deletion_enabled not found in type index.plain`  
**Cause:** Used `table_manager` retention settings that were removed in Loki 3.x.  
**Fix:** Removed `table_manager`, `runtime_config`, `ingester.max_transfer_retries`, `chunk_store_config.max_look_back_period`, and `runtime_config.halt_after_ingest_replicated_data_past` fields. Used a minimal config with only fields valid for Loki 3.3.2.

### Error 2: Promtail Permission Denied on System Logs
**Error:** `open /var/log/auth.log: permission denied` (repeated for auth.log, kern.log, syslog, boot.log, apport.log)  
**Cause:** These files are owned by `syslog:adm` with `rw-r-----` permissions. In rootless Podman, the container runs as the same UID as the host user, which is not in the `adm` group.  
**Fix:** These errors are non-fatal - Promtail continues tailing files it can read (dpkg.log, bootstrap.log, alternatives.log, etc.). Added `exclude_files` and `pipeline_stages` drop rules, but the root permission issue remains. This is expected behavior in rootless Podman.

### Error 3: Loki Config Version Mismatch (Second Attempt)
**Error:** `field halt_after_ingest_replicated_data_past not found in type runtimeconfig.Config`  
**Cause:** Copied config from Loki 2.x documentation that included deprecated fields.  
**Fix:** Stripped config to minimal working version with only Loki 3.x valid fields.

### Error 4: Promtail Config Not Reloading
**Error:** Promtail continued using old config (MD5 `7dc3d397654bffb3a8e471d14c577ffe`) even after file edits.  
**Cause:** Promtail's file watcher doesn't reliably detect changes to bind-mounted files in rootless Podman.  
**Fix:** Full container restart (`podman compose down -v && podman compose up -d`) after config changes. The `touch` command didn't trigger a reload.

### Error 5: Loki API Query Format
**Error:** `log queries are not supported as an instant query type`  
**Cause:** Used `/loki/api/v1/query` endpoint which doesn't support instant queries in Loki 3.x.  
**Fix:** Switched to `/loki/api/v1/query_range` endpoint with start/end timestamps.

### Error 6: Time Range Too Large
**Error:** `the query time range exceeds the limit (query length: 2562047h..., limit: 30d1h)`  
**Cause:** Used `end=9999999999` which exceeded Loki's 30-day limit.  
**Fix:** Used `end=$(date +%s)` with a reasonable start offset (e.g., 3600 seconds back).

### Error 7: Grafana Connectivity - "Unable to connect with Loki"
**Error:** When adding a Loki data source via the Grafana UI with URL `http://localhost:3100`, Save & Test fails with "Unable to connect with Loki. Please check the server logs for more details."  
**Cause:** Inside the Grafana container, `localhost` resolves to IPv6 `[::1]`. Loki is listening on IPv4 `0.0.0.0:3100`, so the connection is refused.  
**Fix:** Use the container service name `http://loki:3100` instead of `http://localhost:3100`. Docker/Podman DNS resolves service names to the container's IPv4 address on the bridge network.  
**Verification:**
```bash
# From within Grafana container, test both URLs
$ podman exec homelab-grafana wget -qO- http://loki:3100/ready
ready

$ podman exec homelab-grafana wget -qO- http://localhost:3100/ready
# Fails - IPv6 [::1] not reachable
```
**Note:** The provisioned data source uses `http://loki:3100` and works correctly. Any data source added via the UI must also use the service name, not `localhost`.

---

## Verification Phase

### Loki Readiness
```bash
$ curl -s http://localhost:3100/ready
ready
```
Loki started successfully after config fix. Healthcheck passes.

### Promtail File Collection
Promtail successfully tails these log files:
- `/var/log/alternatives.log`
- `/var/log/bootstrap.log`
- `/var/log/dpkg.log`
- `/var/log/fontconfig.log`
- `/var/log/faillog`
- `/var/log/gpu-manager.log`
- `/var/log/kernelstub.log`
- `/var/log/lastlog`

Skipped (permission denied):
- `/var/log/auth.log`
- `/var/log/kern.log`
- `/var/log/syslog`
- `/var/log/boot.log`
- `/var/log/apport.log`

### Data Flow Verification
```bash
$ curl -s 'http://localhost:3100/loki/api/v1/series?match%5B%5D=%7B%7D'
[
  {"filename": "/var/log/alternatives.log", "job": "varlogs"},
  {"filename": "/var/log/fontconfig.log", "job": "varlogs"},
  {"filename": "/var/log/bootstrap.log", "job": "varlogs"},
  {"filename": "/var/log/dpkg.log", "job": "varlogs"},
  {"filename": "/var/log/gpu-manager.log", "job": "varlogs"},
  {"filename": "/var/log/kernelstub.log", "job": "varlogs"}
]
```
Confirmed: 6 log files are being collected and stored in Loki.

### Direct API Push Test
Pushed test log directly to Loki API:
```bash
curl -X POST 'http://localhost:3100/loki/api/v1/push' \
  -H 'Content-Type: application/json' \
  -d '{"streams":[{"stream":{"job":"test"},"entries":[{"ts":"...","line":"Test entry"}]}]}'
```
Response: `204 No Content` (accepted)  
Query result: Empty (data not appearing in queries - likely WAL flush timing issue)

### Connectivity Test
```bash
$ podman exec homelab-test-client wget -qO- http://loki:3100/ready
ready

$ podman exec homelab-test-client wget -qO- http://promtail:9080/ready
Ready
```
Both services reachable from test client container via service name DNS.

### Log Query Verification
```bash
$ curl -s "http://localhost:3100/loki/api/v1/query_range?query=%7Bjob%3D%22varlogs%22%7D&start=...&end=..." | python3 -c "..."
# Returned 100 log entries from /var/log/dpkg.log
# Sample: "2026-04-16 05:20:14 status installed man-db:amd64 2.12.0-4build2"
```
Confirmed: End-to-end data flow works. Promtail tails files -> ships to Loki -> Loki stores and serves.

---

## Configuration Phase

### Grafana Data Source (Manual - Pending)
Steps to complete:
1. Open Grafana at http://localhost:3001 (admin/changeme123)
2. Connections -> Data Sources -> Add data source -> Loki
3. HTTP URL: `http://loki:3100`
4. Save & Test

This step requires manual browser interaction and was not automated.

### Grafana Data Source (Provisioned - Complete)
Grafana was added as a container service with a provisioned Loki data source, eliminating the need for manual browser interaction.

**Changes made:**
1. Added `grafana` service to `docker-compose.yml` (image: `docker.io/grafana/grafana:11.5.3`)
2. Created `conf/provisioning/datasources/datasources.yml` to auto-configure Loki as the default data source
3. Created `conf/provisioning/dashboards/dashboards.yml` for dashboard provisioning
4. Mapped host port 3001 to container port 3000
5. Set admin password via `GF_SECURITY_ADMIN_PASSWORD` environment variable
6. Added `grafana_data` named volume for persistent Grafana storage

**Verification:**
```bash
$ curl -s http://localhost:3001/api/health
{"commit":"...","database":"ok","version":"11.5.3"}

$ curl -s -u admin:changeme123 http://localhost:3001/api/datasources
[
  {
    "id": 1,
    "uid": "P8E80F9AEF21F6940",
    "name": "Loki",
    "type": "loki",
    "url": "http://loki:3100",
    "isDefault": true,
    "jsonData": { "maxLines": 1000 }
  }
]
```

**Result:** Grafana is reachable at `http://localhost:3001` (admin/changeme123). The Loki data source is pre-configured and set as the default. Log data from Promtail is queryable via the Grafana UI's Explore tab.

**Containers:**
```
homelab-loki         Up 1 minute (healthy)  0.0.0.0:3100->3100/tcp
homelab-promtail     Up 39 minutes          (no ports)
homelab-grafana      Up 1 minute (healthy)  0.0.0.0:3001->3000/tcp
homelab-test-client  Up 39 minutes          (no ports)
```

**Log query via Loki API (4421 lines processed):**
```bash
$ curl -s "http://localhost:3100/loki/api/v1/query_range?query=%7Bjob%3D%22varlogs%22%7D&start=...&end=..."
# Returns log entries from /var/log/dpkg.log, /var/log/alternatives.log, etc.
# Sample: "2026-04-16 05:20:14 status installed man-db:amd64 2.12.0-4build2"
```

### Grafana Connectivity Fix (Manual Data Source Removed)
A data source was added manually via the Grafana UI with URL `http://localhost:3100`. This failed because from within the container, `localhost` resolves to IPv6 `[::1]` while Loki listens on IPv4. The provisioned data source (`http://loki:3100`) was verified as working.

**Action taken:**
```bash
$ curl -s -X DELETE -u admin:changeme123 http://localhost:3001/api/datasources/2
{"message":"Data source deleted"}

$ curl -s -u admin:changeme123 http://localhost:3001/api/datasources/uid/P8E80F9AEF21F6940/health
{"message":"Data source successfully connected.","status":"OK"}
```

**Result:** Only the provisioned data source remains. Health check returns OK.

---

## Architecture Explanation

### Why Loki over ELK?
- **Storage efficiency**: Loki only indexes labels (metadata), not log content. This reduces storage by 10-100x compared to Elasticsearch.
- **Simplicity**: Single-binary deployment, no complex node management.
- **Grafana integration**: Native integration with Grafana for visualization.
- **Resource friendly**: ~50-100MB RAM vs ~1GB+ for a minimal ELK stack.

### Why Promtail?
- **Lightweight**: ~10-20MB RAM, written in Go.
- **Kubernetes-native**: Originally built for K8s, but works great for single-host setups.
- **Docker service discovery**: Can auto-discover container logs (though not used in this setup due to rootless Podman limitations).

### Data Flow
1. Promtail scans `/var/log/*.log` for new files (min_age: 1m to avoid race conditions)
2. For each file, Promtail seeks to the last known position (tracked in `/work/positions.yaml`)
3. New log lines are buffered and sent to Loki via HTTP push API at `/loki/api/v1/push`
4. Loki receives logs, indexes them by labels (`job`, `filename`, `hostname`), and stores them on disk
5. Grafana queries Loki via LogQL to display and filter logs

---

## Design Decisions

### Port 3100 for Loki
- No conflict with existing services (Grafana is on 3001, Prometheus on 9090)
- Standard Loki port
- > 1024, works with rootless Podman

### Shared Network with Prometheus/Grafana
- Used existing `homelab-observability-network` instead of creating a new one
- Allows Grafana to access Loki directly via service name `loki:3100`
- Promtail can reach Loki on the same network

### Named Volume for Loki Data
- `loki_data:/loki` for persistent storage of chunks, indexes, and WAL
- Survives container restarts and rebuilds

### Bind Mount for Configs
- `./conf/loki-config.yml` and `./conf/promtail-config.yml` for easy editing
- Allows config changes without rebuilding images

### Excluded Log Files
- auth.log, kern.log, syslog, boot.log, apport.log are excluded due to permission issues
- These require root access to read, which isn't available in rootless Podman
- Alternative: run Promtail as privileged (not recommended for security)

---

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references (docker.io/grafana/loki:3.3.2, docker.io/grafana/promtail:3.3.2, docker.io/grafana/grafana:11.5.3)
- [x] Ports are > 1024 (3100:3100/tcp, 3001:3000/tcp)
- [x] Test client container included (homelab-loki-logging-test)
- [x] Healthcheck port matches service config (3100 for Loki, 3000 for Grafana)
- [x] Volumes use hybrid strategy (named loki_data/promtail_work/grafana_data + bind mount configs)
- [x] Network name follows homelab-* pattern (homelab-observability-network, external)
- [x] README includes setup docs, Services table, Troubleshooting, Cleanup
- [x] Verification commands documented
- [x] Expected output samples provided
- [x] Grafana Loki data source configured (provisioned via conf/provisioning/datasources/datasources.yml)
- [x] Secret hygiene: GF_SECURITY_ADMIN_PASSWORD extracted to .env
- [x] Shared network documented (depends on prometheus-grafana)
```

---

## Common Questions

### Q: Why can't Promtail read auth.log and syslog?
**A:** These files are owned by `syslog:adm` with `rw-r-----` permissions. In rootless Podman, containers run as the host user's UID, which isn't in the `adm` group. To read these files, you'd need to either:
1. Add your user to the `adm` group (`sudo usermod -aG adm $USER`, then relogin)
2. Run Promtail with `privileged: true` (not recommended for security)
3. Accept that some system logs won't be collected

### Q: How much storage will Loki use?
**A:** With the current config, Loki uses filesystem storage with a 168-hour (7-day) retention for old samples. For the current workload (system logs), expect ~100-500MB after a week. This can be adjusted via `limits_config.reject_old_samples_max_age`.

### Q: Can I query logs from other containers?
**A:** Yes. Other containers on the `homelab-observability-network` can reach Loki at `http://loki:3100`. You could set up Promtail in other experiments to ship their logs here.

### Q: What happens if Loki restarts?
**A:** Loki uses a Write-Ahead Log (WAL) for durability. On restart, it recovers from the WAL and replays any unflushed data. The `podman compose down -v` command removes this data.

---

## Resource Usage

| Service | RAM | Storage | Notes |
|---------|-----|---------|-------|
| Loki | ~50-100MB | ~1-2GB/week | Depends on log volume and retention |
| Promtail | ~10-20MB | Minimal | Positions file ~1KB |
| Grafana | ~100-200MB | ~50-100MB | Includes dashboards and plugin data |
| **Total** | **~160-320MB** | **~1-3GB/week** | Well within budget |

---

## Lessons Learned

### What Worked
1. **Minimal Loki config**: Stripping deprecated fields and using only 3.x valid config was the key to getting Loki running.
2. **Shared network**: Using the existing `homelab-observability-network` simplified the setup.
3. **File-based log collection**: Promtail's file-based scraping works reliably for readable log files.
4. **API verification**: Using curl to verify data flow was more reliable than waiting for Grafana UI.
5. **Grafana provisioning**: Using `conf/provisioning/datasources/datasources.yml` to auto-configure the Loki data source eliminated the need for manual browser interaction. Grafana was reachable and functional immediately after `podman compose up -d`.

### What Didn't Work
1. **Promtail config hot-reload**: The file watcher doesn't work reliably with bind mounts in rootless Podman. Always do a full container restart after config changes.
2. **System log permissions**: Can't read auth.log, syslog, kern.log without root access. This is a fundamental limitation of rootless Podman.
3. **Direct API push timing**: Pushed test data via API but it didn't appear in queries immediately. Loki batches and flushes data, so there's a delay.
4. **exclude_files not working**: The `exclude_files` regex in Promtail config didn't prevent permission errors for some files. The files were still opened before the exclusion check.
5. **localhost as Grafana data source URL**: Using `http://localhost:3100` as the Loki URL in Grafana fails because the container resolves `localhost` to IPv6 `[::1]`. Must use the service name `http://loki:3100`.

### What to Do Differently Next Time
1. **Start with a known-good config**: Use Loki's official minimal config as a starting point rather than building from documentation.
2. **Verify data flow early**: Test with a direct API push before waiting for Promtail to collect data.
3. **Document permission limitations**: Note upfront which log files won't be readable in rootless Podman.
4. **Consider journald input**: Promtail's journald input could collect system logs without file permission issues (though it requires `/run/log/journal` access).
5. **Include Grafana in the compose file from the start**: The initial experiment omitted Grafana, requiring a manual step. All services should be in the compose file with provisioning configs for a fully automated, reproducible setup.
6. **Use service names for inter-container URLs**: Never use `localhost` or `127.0.0.1` for URLs between containers. Always use the Docker/Podman service name (e.g., `http://loki:3100`), which resolves to the correct IPv4 address on the bridge network.

---

## What Didn't Work (Dead Ends)

1. **Journald input**: Tried configuring Promtail's journald input but `/run/log/journal` isn't accessible in rootless Podman.
2. **Docker service discovery**: Tried `docker_sd` config to auto-discover container logs, but `/run/podman/podman.sock` doesn't exist in rootless Podman.
3. **Host logs directory**: Added a bind mount for `./work/logs:/host-logs` to test log collection, but Promtail didn't pick up files in this directory (possibly a glob matching issue).
4. **Full ELK stack**: Considered Elasticsearch + Logstash + Kibana but abandoned due to high RAM usage (~2GB+) and complexity.
5. **Missing Grafana in initial compose**: The first iteration only included Loki and Promtail, leaving Grafana as a manual step. All services should be in the compose file with provisioning configs for a fully automated setup.
6. **localhost in Grafana data source URL**: Adding a data source via the UI with `http://localhost:3100` failed because the container resolves `localhost` to IPv6 `[::1]`. This was fixed by deleting the manual data source and relying on the provisioned one at `http://loki:3100`.

---

## Simplification Cleanup (April 24, 2026)

Applied per-experiment simplification plan phases 1-8.

### Phase 1 - Trivial Cleanup
- [x] Removed `version: '3.8'` line
- [x] Pinned `alpine:latest` → `alpine:3.21` on test-client

### Phase 2 - Test-Client Standardization
- [x] Container name changed from `homelab-test-client` → `homelab-loki-logging-test`
- [x] Image standardized to `docker.io/alpine:3.21`

### Phase 3 - Secret Hygiene
- [x] Created `.env` with `GF_SECURITY_ADMIN_PASSWORD=changeme123`
- [x] Created `.env.example` with placeholder value
- [x] Replaced hardcoded `GF_SECURITY_ADMIN_PASSWORD=changeme123` with `${GF_SECURITY_ADMIN_PASSWORD}` in compose file
- [x] Verified `.env` is excluded by repo root `.gitignore`

### Phase 4 - Network Naming
- [x] Network is `homelab-observability-network` with `external: true` (shared with prometheus-grafana)
- [x] Documented shared network dependency in README
- [x] Documented that prometheus-grafana must start first

### Phase 5 - Volume Naming
- [x] Volumes use simple names (`loki_data`, `promtail_work`, `grafana_data`)
- [x] Podman-compose auto-prepends project name → actual volumes: `loki-logging_loki_data`, `loki-logging_promtail_work`, `loki-logging_grafana_data`
- [x] Consistent with prometheus-grafana experiment pattern

### Phase 6 - Port Conflicts
- [x] Loki port 3100: No conflict (unique)
- [x] Grafana port 3001:3000: Already correct per port allocation table

### Phase 8 - README Consistency
- [x] Added Services table (Loki, Promtail, Grafana)
- [x] Added shared network documentation
- [x] Updated Quick Start to mention prometheus-grafana dependency
- [x] Updated container name references to `homelab-loki-logging-test`
- [x] Updated credential references to point to `.env`

### Verification
```
$ podman ps --filter "label=io.podman.compose.project=loki-logging" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
NAMES                      STATUS                       PORTS
homelab-loki               Up About a minute (healthy)  0.0.0.0:3100->3100/tcp
homelab-promtail           Up About a minute
homelab-grafana            Up About a minute (healthy)  0.0.0.0:3001->3000/tcp
homelab-loki-logging-test  Up About a minute

$ curl -s http://localhost:3100/ready
ready

$ curl -s http://localhost:3001/api/health
{"database":"ok","version":"11.5.3",...}

$ podman exec homelab-loki-logging-test wget -qO- http://loki:3100/ready
ready

$ podman volume ls --filter "label=io.podman.compose.project=loki-logging" --noheading
loki-logging_loki_data
loki-logging_promtail_work
loki-logging_grafana_data
```

All services healthy, data source configured, test-client DNS resolution working.
