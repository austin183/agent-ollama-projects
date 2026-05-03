# BOINC Client with Intel GPU Support (Experiment 10A)

Distributed scientific computing on the Dell Inspiron 5502 homelab, leveraging Intel Iris Xe GPU acceleration.

## How It Works

BOINC (Berkeley Open Infrastructure for Network Computing) connects to scientific research projects that distribute work units to volunteer computers. This container runs the BOINC client with Intel GPU support, enabling OpenCL-accelerated compute on the Iris Xe GPU (832 GFLOPS peak).

```
┌─────────────────────────────────────┐
│  Dell Inspiron 5502 (Homelab)       │
│                                      │
│  ┌──────────────────────────────┐   │
│  │  homelab-boinc               │   │
│  │  ├─ BOINC Client (Intel tag) │   │
│  │  ├─ OpenCL → Iris Xe GPU     │   │
│  │  └─ /var/lib/boinc (volume)  │   │
│  └──────────────────────────────┘   │
│           │                          │
│           ▼ (network)                │
│  ┌──────────────────────────────┐   │
│  │  BOINC Project Server        │   │
│  │  (Folding@home, etc.)        │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| boinc | 31416 | BOINC client with Intel GPU support |
| test-client | — | Alpine test container for connectivity checks |

## Quick Start

### 1. Start the Container

```bash
cd ~/homelab/distributed-computing/boinc
podman compose up -d
```

### 2. Verify It's Running

```bash
# Check status
podman ps --filter name=homelab-boinc

# Verify GPU detection
podman logs homelab-boinc | grep "OpenCL"

# Check client health
podman exec homelab-boinc sh -c 'boinccmd --get_host_info'
```

Expected GPU line in output:
```
Intel GPU
  OpenCL: Intel GPU 0: Intel(R) Iris(R) Xe Graphics (... 832 GFLOPS peak)
```

### 3. Attach to a Project

**All major BOINC projects require registration** to track credits and assign work. Create an account first, then attach.

**Option A: Using BOINC Manager (Desktop App)**

1. Install BOINC Manager: https://boinc.berkeley.edu/download.php
2. Open BOINC Manager
3. File → Select Computer...
4. Host name: `127.0.0.1`
5. Password: value of `BOINC_GUI_RPC_PASSWORD` from `.env`
6. Projects → Join a new project
7. Enter project URL (e.g., `https://www.worldcommunitygrid.org`)

**Option B: Command Line**

```bash
# Attach to a project (requires auth string from project website)
podman exec homelab-boinc sh -c 'boinccmd --project_attach https://www.worldcommunitygrid.org <auth_string>'
```

### 4. Monitor Activity

```bash
# Check computing status
podman exec homelab-boinc sh -c 'boinccmd --get_cc_status'

# View active tasks
podman exec homelab-boinc sh -c 'boinccmd --get_task_summary'

# Check resource usage
podman stats homelab-boinc --no-stream

# Follow logs
podman logs -f homelab-boinc
```

## Configuration

### GUI RPC Password

Change in `.env`:
```
BOINC_GUI_RPC_PASSWORD=your-secure-password
```

### Recommended Computing Preferences

In BOINC Manager (after attaching):
- **CPU:** Use at most 50% when idle
- **GPU:** Allow when idle, 50% max
- **Disk:** Limit to 3GB
- **Network:** Unlimited (or limit for Wi-Fi)

## Verification Commands

### GPU Working Check
```bash
$ podman exec homelab-boinc sh -c 'boinccmd --get_host_info'
...
  Intel GPU
    OpenCL: Intel GPU 0: Intel(R) Iris(R) Xe Graphics (driver version 23.43.027642, device version OpenCL 3.0 NEO, 10535MB, 10535MB available, 832 GFLOPS peak)
```

### GPU Computing Status
```bash
$ podman exec homelab-boinc sh -c 'boinccmd --get_cc_status'
GPU status
    suspended: computer is in use  # Normal when actively using laptop
    current mode: according to prefs
```

### Resource Usage
```bash
$ podman stats homelab-boinc --no-stream
ID            NAME           CPU %  MEM USAGE / LIMIT  MEM %
80c9fab4a422  homelab-boinc  0.30%  3.76MB / 12.25GB   0.03%
```

### Device Access Verification
```bash
$ podman exec homelab-boinc ls -la /dev/dri
crw-rw----+ 1 nobody nogroup 226,   1 card1
crw-rw----+ 1 nobody nogroup 226, 128 renderD128
```

## Common Pitfalls

### GPU Not Detected
- Verify `/dev/dri` exists on host: `ls -la /dev/dri`
- Check i915 driver is loaded: `lsmod | grep i915`
- Container logs should show: `OpenCL: Intel GPU 0: Intel(R) Iris(R) Xe Graphics`

### No Work Units Assigned
- Projects can take hours to authenticate and assign work
- Force update: `podman exec homelab-boinc sh -c 'boinccmd --update'`
- Check logs: `podman logs homelab-boinc | grep -i error`

### GPU Suspended
- Default BOINC behavior: GPU pauses when "computer is in use"
- Wait for idle time (default: 3 min no mouse/keyboard)
- Or manually enable via BOINC Manager: GPU → Always

### Healthcheck Fails
- The `boinccmd --status` command doesn't work in this container
- Healthcheck uses `boinccmd --get_cc_status` instead

## Stopping

```bash
# Stop container (keeps data)
podman compose down

# Stop and remove data
podman compose down -v
```

## Files

- `docker-compose.yml` - Container configuration
- `boinc-data/` - Persistent BOINC state (projects, credentials, work)
- `experiment-timeline.md` - Full setup journey and lessons learned

## Project Suggestions

| Project | Focus | GPU Support | Registration |
|---------|-------|-------------|-------------|
| World Community Grid | Humanitarian research | Yes | Required |
| Einstein@Home | Pulsars, gravitational waves | Yes | Required |
| Folding@home | Protein folding | Yes (Intel OpenCL) | Required |
| SETI@home | Extraterrestrial signals | Varies | Required |
| Rosetta@home | Protein structure | Limited | Required |

**Note:** All major BOINC projects require registration. There are no significant projects that allow anonymous compute.

## Resources

- [BOINC Official](https://boinc.berkeley.edu/)
- [BOINC Projects](https://boinc.berkeley.edu/projects.php)
- [GPU Computing Guide](https://boinc.berkeley.edu/wiki/GPU_computing)
- [Experiment Timeline](experiment-timeline.md)
