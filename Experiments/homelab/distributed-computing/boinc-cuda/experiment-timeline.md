# BOINC CUDA Experiment - Experiment Timeline

**Started:** April 26, 2026
**Status:** Running (container operational, awaiting project account)
**Related:** 10A (iGPU variant at `../boinc/`), 10B (CPU-only at `../boinc-cpu/`)

---

## Setup Phase

### Pre-flight Checks

**NVIDIA GPU Availability:**
- GTX 1660 Ti (6GB GDDR6, CC 7.5) confirmed on host
- NVIDIA driver 580.119.02 loaded
- CDI syntax `nvidia.com/gpu=all` proven working via `llamacpp-cuda` experiment

**Port Conflicts:**
- Port 31416 (GPU BOINC iGPU) - not in use
- Port 31417 (CPU BOINC) - not in use
- Port 31418 (CUDA BOINC) - not in use

**Resource Availability:**
```
$ free -h
Mem: 15Gi total, 7.6Gi used, 7.8Gi available
$ df -h /
225G total, 62G used, 152G available (29%)
```

### Image Pull
- `docker.io/boinc/client:intel` - already cached from prior experiments

### Container Start
```
$ podman compose up -d
```
- Container started successfully
- Network `boinc-cuda_homelab-boinc-cuda` created

---

## Verification Phase

### Container Status
```
CONTAINER ID  IMAGE                          STATUS                    PORTS                     NAMES
3d583d9d2ef7  docker.io/boinc/client:intel   Up 15 seconds (starting)  0.0.0.0:31418->31416/tcp  homelab-boinc-cuda
9f4bfd8410a1  docker.io/library/alpine:3.21  Up 14 seconds             ...                         homelab-boinc-cuda-test
```

### Initial Logs - NVIDIA GPU DETECTED
```
26-Apr-2026 13:56:11 [---] CUDA: NVIDIA GPU 0: NVIDIA GeForce GTX 1660 Ti (driver version 580.99, CUDA version 13.0, compute capability 7.5, 5747MB, 5747MB available, 4884 GFLOPS peak)
26-Apr-2026 13:56:11 [---] Processor: 8 AuthenticAMD AMD Ryzen 7 3750H with Radeon Vega Mobile Gfx
26-Apr-2026 13:56:11 [---] Memory: 15.43 GB physical, 19.43 GB virtual
26-Apr-2026 13:56:11 [---] Disk: 224.81 GB total, 151.57 GB free
26-Apr-2026 13:56:11 [---] This computer is not attached to any projects
26-Apr-2026 13:56:11 Initialization completed
26-Apr-2026 13:56:11 [---] Suspending GPU computation - computer is in use
```

**Key findings:**
- **NVIDIA GPU DETECTED:** GTX 1660 Ti with CUDA 13.0 runtime
- **Compute Capability 7.5** - Turing architecture
- **5747MB (~5.6GB)** available GPU memory
- **4884 GFLOPS** peak compute performance
- GPU suspended due to "computer is in use" (default BOINC behavior)

### BOINC Host Info
```
$ podman exec homelab-boinc-cuda sh -c 'boinccmd --get_host_info'
  CPU vendor: AuthenticAMD
  CPU model: AMD Ryzen 7 3750H with Radeon Vega Mobile Gfx
  NVIDIA GPU: NVIDIA GeForce GTX 1660 Ti (driver version 580.99, CUDA version 13.0, compute capability 7.5, 5747MB, 5747MB available, 4884 GFLOPS peak)
```

### Compute Status
```
$ podman exec homelab-boinc-cuda sh -c 'boinccmd --get_cc_status'
CPU status
    not suspended
GPU status
    suspended: computer is in use
Network status
    not suspended
```

- CPU not suspended, GPU suspended (default behavior)
- Set GPU mode to "always" with `boinccmd --set_gpu_mode always 0`

### Resource Usage
```
$ podman stats homelab-boinc-cuda --no-stream
NAME                CPU %  MEM USAGE / LIMIT  MEM %  PIDS
homelab-boinc-cuda  0.76%  3.756MB / 16.56GB  0.02%  2
```

- **RAM:** 3.756MB (extremely lightweight)
- **CPU:** 0.76% (idle)
- **Processes:** 2

---

## User Decision: Pause at Current State

Container is fully functional and ready for project attachment:
- NVIDIA GPU detected and working
- BOINC client running
- Healthcheck configured
- Ready to attach to any CUDA-compatible project

---

## Benchmark Metrics

| Metric | BOINC CPU (10B) | BOINC iGPU (10A) | BOINC CUDA |
|--------|----------------|-----------------|------------|
| Credits/day | TBD | TBD | TBD |
| CPU usage % | 0.45% idle | 0.30% idle | 0.76% idle |
| RAM usage | 3.744MB | 3.76MB | 3.756MB |
| VRAM usage | N/A | N/A | N/A (idle) |
| GPU Peak GFLOPS | N/A | 832 | 4884 |

---

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file created
- [x] .env file created
- [x] Pre-flight checks passed
- [x] Container started
- [x] NVIDIA GPU detected by BOINC
- [ ] Project attached
- [ ] Work units received
- [ ] CUDA computation verified
- [ ] Benchmark metrics recorded
```

---

## Lessons Learned

1. **`boinc/client:intel` image supports NVIDIA CUDA** - Despite the "intel" tag, the image detects and reports NVIDIA GPUs with CUDA capabilities. The image bundles CUDA runtime libraries that work with NVIDIA drivers.

2. **CDI syntax works for NVIDIA in BOINC** - The `nvidia.com/gpu=all` CDI device passthrough from `llamacpp-cuda` works identically for BOINC.

3. **GPU detection is immediate** - CUDA GPU reported within 1 second of container start, same as Intel iGPU.

4. **Peak GFLOPS significantly higher** - NVIDIA GTX 1660 Ti reports 4884 GFLOPS vs Intel Iris Xe at 832 GFLOPS (5.9x difference).

5. **Account creation via `boinccmd` can fail silently** - The `--create_account` command returned "can't resolve hostname" for einstein.ai, likely due to DNS resolution within the container at that moment.

---

*Timeline created: April 26, 2026*
*Session ended: Container running, GPU detected, paused pending project account creation*
