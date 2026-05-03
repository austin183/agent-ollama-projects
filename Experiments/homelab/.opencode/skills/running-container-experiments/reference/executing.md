# Executing Container Experiments

Run, verify, debug, and document experiments — whether building new ones or reproducing existing results.

## Execution Workflow

Follow this sequence for every experiment run:

### 1. Pre-flight Checks

```bash
# Check running containers for conflicts
podman ps

# Check specific ports
ss -tlnp | grep <port>

# Check resource availability
free -h
df -h /

# Check GPU device nodes (if applicable)
ls -la /dev/dri

# Check for stale containers from previous runs
podman ps -a --filter name=homelab-<experiment>
```

### 2. Clean Launch

```bash
# Navigate to experiment directory
cd ~/homelab/path/to/experiment

# Clean start (removes stale volumes, containers, networks)
podman compose down -v

# Start experiment
podman compose up -d

# If compose uses custom builds
podman compose up -d --build
```

**Always `cd` into the experiment directory first.** Running `podman compose` from a parent directory fails with "no compose.yaml found".

### 3. Initial Log Inspection

Wait 10-30 seconds for startup, then check logs:

```bash
# Tail recent logs
podman logs --tail 50 homelab-<service>

# Watch logs in real-time
podman logs -f homelab-<service>

# Look for startup confirmation
podman logs homelab-<service> | grep -i "listening\|started\|ready"
```

Key things to look for:
- Service listening on expected port
- Database initialized
- GPU detected (if applicable)
- Connection errors to other services
- Missing config files or environment variables

### 4. Container Status Verification

```bash
# All containers running
podman ps --filter name=homelab-<experiment>

# Health status
podman inspect homelab-<service> --format '{{.State.Health.Status}}'
# Expected: healthy

# Resource usage
podman stats --no-stream --filter name=homelab-<experiment>
```

### 5. Connectivity Tests (from test client)

```bash
# DNS resolution
podman exec homelab-<experiment>-test nslookup <service-name>

# HTTP connectivity
podman exec homelab-<experiment>-test wget --spider -q http://<service>:<port>/ && echo "OK"
# Or with curl if wget not available
podman exec homelab-<experiment>-test curl -sf http://<service>:<port>/ && echo "OK"

# Ping
podman exec homelab-<experiment>-test ping -c 2 <service-name>
```

### 6. Service-Specific Verification

Run the verification commands from the experiment's README. Common patterns:

**Web services:**
```bash
curl http://localhost:<host-port>/api/health
```

**Databases:**
```bash
podman exec homelab-<db> psql -U <user> -d <db> -c "SELECT 1;"
podman exec homelab-<db> mongosh --eval "db.runCommand({ping:1})"
```

**Message brokers:**
```bash
podman exec homelab-rabbitmq rabbitmq-diagnostics -q ping
```

**GPU services:**
```bash
podman logs homelab-<service> | grep -i "gpu\|opencl\|sycl\|cuda"
```

### 7. Document Results

Update the experiment timeline iteratively as you go. Once the experiment is verified and working, proceed to [reference/documenting.md](reference/documenting.md) for full documentation guidance including README structure and cleanup of generated artifacts.

## Debug Loop

When verification fails, follow this cycle:

```
Check logs -> Identify error -> Determine root cause -> Fix -> Restart -> Re-verify
```

### Common Failure Modes

#### Port already in use

```
Error: rootlessport listen tcp 0.0.0.0:XXXX: bind: address already in use
```

**Fix:** Find conflicting process, choose different host port.

```bash
# Find what's using the port
ss -tlnp | grep <port>

# Change host port in compose
ports:
  - "<new-port>:<container-port>/tcp"
```

#### Healthcheck tool missing

```
/bin/sh: 1: wget: not found
```

**Fix:** Check available tools, switch to `curl`:

```bash
podman exec <container> which curl wget
```

```yaml
# Replace wget with curl
healthcheck:
  test: ["CMD-SHELL", "curl -sf http://localhost:PORT/ || exit 1"]
```

#### Health endpoint returns 404

```
<!DOCTYPE html>...Page not found!...
```

**Fix:** The service doesn't have a `/health` endpoint. Check logs for actual endpoints:

```bash
podman logs <container> | grep -i "endpoint\|route\|listening"
```

Common alternatives:
- Root path `/` returns HTML (HTTP 200)
- `/api/health`, `/status`, `/-/healthy`
- Service-specific: Grafana `/api/health`, Prometheus `/-/healthy`

#### Privileged port binding

```
rootlessport cannot expose privileged port XX, you can add 'net.ipv4.ip_unprivileged_port_start=XX' to /etc/sysctl.conf
```

**Fix:** Use host port >= 1024:

```yaml
ports:
  - "1024+:<container-port>/tcp"
```

#### Database not ready for connections

```
FATAL: the database system is starting up
connection refused
```

**Fix:** Wait for database readiness. Use explicit wait loops, not `depends_on`:

```bash
# Check if database is ready
podman exec <db-container> pg_isready -U <user>
# Or wait manually
sleep 15 && podman exec <db-container> pg_isready
```

For services that depend on databases, add wait loops to the compose `command`.

#### Init script fails with stale volumes

**Symptoms:** Init scripts don't run, old config persists, silent failures.

**Fix:** Always clean volumes when changing init scripts:

```bash
podman compose down -v
podman compose up -d
```

#### File permissions in rootless Podman

```
Read security file failed: permissions on /path/file are too open
```

**Fix:** User namespace mapping breaks bind mount permissions. Bake files into custom images:

```dockerfile
FROM <base-image>
COPY <file> /path/file
RUN chown <user>:<group> /path/file && chmod <mode> /path/file
```

#### Variable expansion in compose commands

`$$` in compose YAML becomes `$` at runtime. But single-quoted heredocs in shell commands don't expand variables.

**Fix:** Use multiple `echo` statements instead of heredocs.

#### Container exited unexpectedly

```bash
# Check exit code
podman inspect <container> --format '{{.State.ExitCode}}'

# Check logs for crash reason
podman logs --tail 100 <container>

# Check if it's supposed to exit (e.g., test-producer, init containers)
```

#### GPU not detected

```bash
# Check device nodes in container
podman exec <container> ls -la /dev/dri

# Check logs for GPU detection
podman logs <container> | grep -i "gpu\|opencl\|sycl\|cuda\|dri"

# Check host GPU availability
ls -la /dev/dri
lsmod | grep -i "i915\|nvidia"
```

## Iterative Debugging Pattern

From observed experiment timelines, the typical pattern is:

1. **Trial 1:** Launch, something fails, check logs
2. **Trial 2:** Fix obvious issue, `down -v && up -d`, something else fails
3. **Trial 3:** Fix second issue, maybe need to understand container internals
4. **Trial N:** Everything works, verify, document

**Key principles:**
- Each iteration narrows down the problem
- Always clean volumes (`down -v`) between iterations when config changed
- Log output is your primary diagnostic tool
- Check what tools are available inside containers before writing healthchecks
- Service-specific commands may differ from documentation (check actual versions)

## Resource Monitoring

```bash
# One-time snapshot
podman stats --no-stream --filter name=homelab-<experiment>

# Continuous monitoring (Ctrl+C to stop)
podman stats --filter name=homelab-<experiment>

# Check against budget
free -h      # RAM
df -h /      # Disk
```

Compare actual usage against the budget documented in `ideas/experiments.md`.

## Reproducing an Existing Experiment

When the goal is to reproduce results from a known-working experiment:

1. **Read the existing timeline first** — it documents errors, workarounds, and the actual journey
2. **Read the README** — it has the verification commands and expected output
3. **Check for machine differences** — ASUS TUF vs Dell Inspiron have different hardware
4. **Follow the execution workflow above** — same process, but you know what to expect
5. **Note any differences** — document in timeline what worked differently on current hardware
6. **Update the timeline** — append results with date stamp

### Machine-Specific Considerations (ASUS TUF)

- **CPU:** AMD Ryzen 7 3750H (vs Intel i5-1135G7 on Dell)
- **RAM:** 15GB total, ~8.5GB available (vs 12GB on Dell)
- **GPU:** NVIDIA GTX 1660 Ti (vs Intel Iris Xe on Dell)
  - NVENC: H.264, HEVC
  - CUVID: H.264, HEVC, VP8, VP9, AV1
  - Use NVIDIA container toolkit, not Intel SYCL/OpenCL
- **Network:** Ethernet available (vs Wi-Fi 6 only on Dell)
- **Swap:** 19GB available

## Post-Execution Checklist

```
Experiment Execution Results:
- [ ] All containers running and healthy
- [ ] DNS resolution works between containers
- [ ] Service endpoints respond correctly
- [ ] Resource usage within budget
- [ ] Verification commands produce expected output
- [ ] Timeline updated with results
- [ ] README verification commands match actual behavior
- [ ] Known issues documented
```

## Cleanup

### Container and Volume Cleanup

```bash
# Stop containers (preserve data)
podman compose down

# Stop and remove data
podman compose down -v

# Remove images
podman compose down --rmi local

# Check for orphaned resources
podman ps -a --filter name=homelab-<experiment>
podman volume ls --filter name=homelab-<experiment>
podman network ls --filter name=homelab-<experiment>
```

### Filesystem Cleanup

Generated files from a run can cause a fresh start to fail. Clean up experiment-generated bind mount contents:

```bash
# Remove generated bind mount directories (check README/Cleanup for which dirs are generated)
rm -rf work/ conf/ data/
```

Common artifacts to clean:
- **Wizard-generated configs** — e.g., `conf/AdGuardHome.yaml`
- **Initialized database data** — bind-mounted DB directories that prevent re-initialization
- **Runtime-generated directories** — any directories created during wizard/setup flows

The README's Cleanup section should document which directories are generated so a reproducer knows what to clean.
