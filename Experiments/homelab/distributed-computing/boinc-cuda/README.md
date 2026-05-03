# BOINC CUDA Experiment

NVIDIA GPU-accelerated BOINC client for distributed computing benchmarks.

## Quick Start

```bash
# Start the experiment
cd distributed-computing/boinc-cuda
cp .env.example .env
podman compose up -d

# Verify GPU detection
podman exec homelab-boinc-cuda sh -c 'boinccmd --get_host_info'

# Check compute status
podman exec homelab-boinc-cuda sh -c 'boinccmd --get_cc_status'

# Stop the experiment
podman compose down

# Stop and remove data
podman compose down -v
```

## GPU Detection

The container should detect your NVIDIA GPU on startup:

```
CUDA: NVIDIA GPU 0: NVIDIA GeForce GTX 1660 Ti (driver version 580.99, CUDA version 13.0, compute capability 7.5, 5747MB, 5747MB available, 4884 GFLOPS peak)
```

## Project Attachment

BOINC requires a registered account to download and compute work units. The container is ready to attach to any project; you just need to create an account first.

### Recommended CUDA-Compatible Projects

| Project | URL | CUDA Support | Notes |
|---------|-----|-------------|-------|
| Einstein@Home | https://einstein.ai | Yes | Pulsar searches, gravitational waves |
| Milkyway@home | https://milkyway.cs.rpi.edu/milkyway/ | Yes | Dark matter simulations |
| LHC@home | https://lhcathome.cern.ch/lhcathome/ | Yes | Particle physics |
| World Community Grid | https://www.worldcommunitygrid.org | Yes | Science for social good |
| Folding@home | https://foldingathome.org | Yes | Protein folding (uses custom client, not BOINC) |

### Attaching to a Project

1. **Register** at the project website to create an account
2. **Get your auth string** from the project's my account page
3. **Attach** the client to the project:

```bash
podman exec homelab-boinc-cuda sh -c 'boinccmd --project_attach <project_url> <auth_string>'
```

Or create an account directly from the client:

```bash
podman exec homelab-boinc-cuda sh -c 'boinccmd --create_account <project_url> <email> <password> <team_name>'
```

### Verifying Attachment

```bash
# Check attached projects and tasks
podman exec homelab-boinc-cuda sh -c 'boinccmd --get_simple_gui_info'

# Check task summary
podman exec homelab-boinc-cuda sh -c 'boinccmd --get_task_summary pcedsrw'
```

## GPU Compute Mode

By default, BOINC suspends GPU computation when the computer is "in use" (mouse/keyboard activity within 3 minutes). To enable GPU compute regardless:

```bash
podman exec homelab-boinc-cuda sh -c 'boinccmd --set_gpu_mode always 0'
```

## Architecture

```
┌─────────────────────────────────────────────┐
│         Host System (ASUS TUF)               │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │  NVIDIA GTX 1660 Ti (CDI passthrough)│    │
│  │     │                                │    │
│  │     ▼                                │    │
│  │  ┌────────────────────────────────┐  │    │
│  │  │  homelab-boinc-cuda (Podman)   │  │    │
│  │  │                                │  │    │
│  │  │  BOINC Client (CUDA-capable)   │  │    │
│  │  │    ├─ CUDA (NVIDIA GPU)        │  │    │
│  │  │    ├─ GUI RPC (localhost)      │  │    │
│  │  │    └─ /var/lib/boinc (volume)  │  │    │
│  │  └────────────────────────────────┘  │    │
│  └──────────────────────────────────────┘    │
│                                              │
│  Network: homelab-boinc-cuda (bridge)        │
└─────────────────────────────────────────────┘
         │
         ▼ (network)
┌─────────────────────────────────────────────┐
│        BOINC Project Server                  │
│  (Einstein@Home, Milkyway@home, etc.)        │
│                                              │
│  Sends: Work units (CUDA tasks)              │
│  Receives: Computed results                  │
└─────────────────────────────────────────────┘
```

## Resources

| Metric | Value |
|--------|-------|
| RAM | ~4MB idle |
| CPU | <1% idle |
| GPU | 5.6GB available |
| Disk | ~422MB image + work units |

## Related Experiments

- `../boinc/` - Intel iGPU variant (OpenCL, 832 GFLOPS)
- `../boinc-cpu/` - CPU-only variant (baseline)
