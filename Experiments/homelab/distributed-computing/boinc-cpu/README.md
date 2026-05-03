# BOINC CPU-Only (Experiment 10B)

Distributed scientific computing using CPU-only work units. This is the CPU-only variant of the BOINC experiment, complementary to the GPU-enabled setup at `../boinc/`.

## How It Works

```
┌─────────────────────────────────────────────┐
│         Host System (Dell Inspiron)          │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │  homelab-boinc-cpu (Podman)          │    │
│  │                                      │    │
│  │  BOINC Client (CPU-only image)       │    │
│  │    ├─ GUI RPC (localhost)            │    │
│  │    └─ /var/lib/boinc (volume)        │    │
│  └──────────────────────────────────────┘    │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │  homelab-boinc-cpu-test (Alpine)     │    │
│  │  (test client - sleep 3600)          │    │
│  └──────────────────────────────────────┘    │
│                                              │
│  Network: homelab-boinc-cpu (bridge)         │
└─────────────────────────────────────────────┘
          │
          ▼ (network)
┌─────────────────────────────────────────────┐
│        BOINC Project Server                  │
│  (Folding@home, Einstein@Home, etc.)         │
│                                              │
│  Sends: Work units (CPU tasks only)          │
│  Receives: Computed results                  │
└─────────────────────────────────────────────┘
```

## Quick Start

### Start the Container

```bash
cd ~/homelab/distributed-computing/boinc-cpu
cp .env.example .env
podman compose up -d
```

### Check Status

```bash
# Container status
podman ps --filter name=homelab-boinc-cpu

# View logs
podman logs -f homelab-boinc-cpu

# Check BOINC host info (CPU detection)
podman exec homelab-boinc-cpu sh -c 'boinccmd --get_host_info'

# Check compute status
podman exec homelab-boinc-cpu sh -c 'boinccmd --get_cc_status'

# Resource usage
podman stats homelab-boinc-cpu --no-stream
```

### Verify Connectivity

```bash
# DNS resolution from test client
podman exec homelab-boinc-cpu-test nslookup boinc-cpu

# Ping the main service
podman exec homelab-boinc-cpu-test ping -c 3 boinc-cpu
```

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and customize:

```bash
cp .env.example .env
```

| Variable | Default | Description |
|----------|---------|-------------|
| `BOINC_GUI_RPC_PASSWORD` | `boinc-cpu-2026` | Password for local GUI RPC access |
| `TZ` | `America/New_York` | Timezone for logs |

### Adding a BOINC Project

1. Create an account at a BOINC project (e.g., [Folding@home](https://foldingathome.org/), [Einstein@Home](https://einsteinathome.org/), [World Community Grid](https://www.worldcommunitygrid.org/))
2. Get your account auth string from the project
3. Attach the project:

```bash
podman exec homelab-boinc-cpu sh -c 'boinccmd --project_attach https://project-url.org YOUR_AUTH_STRING'
```

4. Wait for work unit assignment (can take hours)

### BOINC Manager (Remote GUI)

1. Install BOINC Manager on any computer: https://boinc.berkeley.edu/download.php
2. File → Select Computer...
3. Host name: your homelab IP address
4. Password: the value of `BOINC_GUI_RPC_PASSWORD`

## Key Differences from GPU Version (10A)

| Feature | CPU-Only (10B) | GPU (10A) |
|---------|---------------|-----------|
| Image | `boinc/client:latest` | `boinc/client:intel` |
| GPU Support | No | Intel Iris Xe (OpenCL) |
| `/dev/dri` Passthrough | No | Yes |
| Host Port | 31417 | 31416 |
| Compatible Projects | All | GPU-compatible only |
| RAM Usage | ~4MB idle | ~4MB idle |

## Troubleshooting

### Container Won't Start

```bash
# Check for port conflicts
ss -tlnp | grep 31417

# Clean up and restart
podman compose down -v
podman compose up -d
```

### CPU Suspended - "On Batteries"

BOINC detects the laptop is running on battery and suspends all compute. Options:

1. Plug in the laptop (recommended)
2. Change computing preferences to allow compute on batteries via BOINC Manager
3. Manually resume: `podman exec homelab-boinc-cpu sh -c 'boinccmd --resume'`

### No Work Units Assigned

- New accounts may take hours to receive work
- Try multiple projects for faster assignment
- Check logs for errors: `podman logs homelab-boinc-cpu | grep -i error`
- Force contact with project: `podman exec homelab-boinc-cpu sh -c 'boinccmd --update'`

### Healthcheck Failing

```bash
# Test the healthcheck command manually
podman exec homelab-boinc-cpu sh -c 'boinccmd --passwd boinc-cpu-2026 --get_cc_status'

# If it fails, check if BOINC is actually running
podman exec homelab-boinc-cpu sh -c 'boinccmd --get_host_info'
```

## Resource Usage

| Metric | Value | Budget |
|--------|-------|--------|
| RAM | ~4MB (idle) | 200MB |
| CPU | ~0% (idle) | - |
| Disk | ~400MB image + work units | 1-3GB |

## Stopping

```bash
# Stop without removing data
podman compose down

# Stop and remove data volumes
podman compose down -v
```

## Related

- [GPU BOINC (10A)](../boinc/) - Intel Iris Xe GPU-accelerated variant
- [Experiment Plan](../../ideas/experiments.md#experiment-10b-boinc-cpu-only-mode)
- [BOINC Official](https://boinc.berkeley.edu/)
