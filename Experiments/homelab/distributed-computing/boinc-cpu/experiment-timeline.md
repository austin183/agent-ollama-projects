# BOINC Experiment 10B - Experiment Timeline (CPU-Only)

**Started:** April 23, 2026  
**Status:** Running (container operational, awaiting project account)  
**Related:** 10A (GPU variant at `../boinc/`)

---

## Setup Phase

### Pre-flight Checks

**Existing GPU BOINC Container:**
- No GPU BOINC containers currently running (container from April 20 was cleaned up)
- GPU BOINC data directory still exists at `../boinc/boinc-data/` with project state
- GPU experiment is paused (awaiting project account creation)

**Port Conflicts:**
- Port 31416 (GPU BOINC) - not in use
- Port 31417 (CPU BOINC) - not in use
- No conflicts

**Resource Availability:**
- Plenty of RAM and disk space available
- GPU BOINC image (~422MB) already cached locally

### Image Pull

```
$ podman pull docker.io/boinc/client:latest
Trying to pull docker.io/boinc/client:latest...
Getting image source signatures
Copying blob sha256:a1c7ae7c5f0547bdcadae827f9b9fc75608db0b10974cc9270046b9acb6387fa
Copying blob sha256:2726e237d1a37437b7a1f5529158e1de8e3564288bc85f7ef7936925131
...
7b1c502f6f4772935a9c364d2e80eff8b86b201aef5e6d8b66458ae9752b77a1
```

- Pulled successfully
- Base image: Ubuntu 24.04.2 LTS (same as GPU variant)
- No `intel` tag = no OpenCL/GPU support

### Compose File Creation

Created `docker-compose.yml` with:
- `docker.io/boinc/client:latest` image (CPU-only, no GPU support)
- No `/dev/dri` passthrough (not needed for CPU-only)
- Bind mount: `./boinc-cpu-data:/var/lib/boinc` (separate from GPU data)
- GUI RPC password: `boinc-cpu-2026`
- Port 31417 mapped (BOINC data transfer port, different from GPU's 31416)
- Bridge network: `homelab-boinc-cpu` (isolated from GPU network)
- Healthcheck: `boinccmd --passwd boinc-cpu-2026 --get_cc_status`

### Container Start

```
$ podman compose -f /home/labratorian/homelab/distributed-computing/boinc-cpu/docker-compose.yml up -d
podman-compose version: 1.0.6
using podman version: 4.9.3
...
daa574935ca9ce9baf3585c5fc65b39bf87f777cfa7fe90fcd35227a52e9b0a3
exit code: 0
1120db44a08c1809cec6d7cc76686dbab5ae0505430b88c7fb9e7485b74557b0
exit code: 0
```

- Main container (homelab-boinc-cpu): started successfully
- Test client (homelab-boinc-cpu-test): started successfully
- Network `homelab-boinc-cpu` created

---

## Verification Phase

### Container Status

```
$ podman ps --filter name=homelab-boinc-cpu
CONTAINER ID  IMAGE                         STATUS                        NAMES
daa574935ca9  docker.io/boinc/client:latest  Up 8 seconds (starting)       homelab-boinc-cpu
1120db44a08c  docker.io/library/alpine:latest Up 6 seconds                 homelab-boinc-cpu-test
```

### Initial Logs - CPU Detection

```
23-Apr-2026 21:06:48 [---] Data directory: /var/lib/boinc
23-Apr-2026 21:06:48 [---] Processor: 8 GenuineIntel 11th Gen Intel(R) Core(TM) i5-1135G7 @ 2.40GHz
23-Apr-2026 21:06:48 [---] Memory: 11.41 GB physical, 15.41 GB virtual
23-Apr-2026 21:06:48 [---] Disk: 241.39 GB total, 106.13 GB free
23-Apr-2026 21:06:48 [---] This computer is not attached to any projects
23-Apr-2026 21:06:48 Initialization completed
23-Apr-2026 21:06:48 [---] Suspending computation - on batteries
```

**Key findings:**
- **CPU DETECTED:** 8-core i5-1135G7 at 2.40GHz
- **NO GPU LINE** - confirms CPU-only image has no OpenCL support
- 11.41 GB RAM detected
- 106.13 GB free disk space
- Suspended because "on batteries" (laptop power state)

### BOINC Host Info

```
$ podman exec homelab-boinc-cpu sh -c 'boinccmd --get_host_info'
timezone: -14400
  domain name: daa574935ca9
  IP addr: <CONTAINER_IP>
  #CPUS: 8
  CPU vendor: GenuineIntel
  CPU model: 11th Gen Intel(R) Core(TM) i5-1135G7 @ 2.40GHz [Family 6 Model 140 Stepping 1]
  CPU FP OPS: 1000000000.000000
  CPU int OPS: 1000000000.000000
  OS name: Linux Ubuntu
  OS version: Ubuntu 24.04.2 LTS [6.18.7-76061807-generic|libc 2.39]
  mem size: 12253413376.000000
  cache size: 8388608.000000
  swap size: 16548089856.000000
  disk size: 241390825472.000000
  disk free: 106134065152.000000
```

- Confirms 8 CPUs, Intel CPU-only (no GPU line)
- FP OPS and int OPS both at 1 billion (baseline, not GPU-accelerated)

### Compute Status

```
$ podman exec homelab-boinc-cpu sh -c 'boinccmd --get_cc_status'
network connection status: don't need connection
CPU status
    suspended: on batteries
    current mode: according to prefs
    perm mode: according to prefs
GPU status
    not suspended
    current mode: according to prefs
    perm mode: according to prefs
Network status
    not suspended
    current mode: according to prefs
    perm mode: according to prefs
```

- CPU suspended due to battery power
- GPU status shows "not suspended" (no GPU to suspend - expected for CPU-only image)

### Resource Usage

```
$ podman stats homelab-boinc-cpu --no-stream
ID            NAME               CPU %       MEM USAGE / LIMIT  MEM %       NET IO             BLOCK IO    PIDS
daa574935ca9  homelab-boinc-cpu  0.45%       3.744MB / 12.25GB  0.03%       14.55kB / 2.156kB  0B / 0B     2
```

- **RAM:** 3.744MB (extremely lightweight, same as GPU variant)
- **CPU:** 0.45% (idle)
- **Processes:** 2 (boinc main + shell)

### DNS Resolution Test

```
$ podman exec homelab-boinc-cpu-test nslookup boinc-cpu
Server:		<CONTAINER_IP>
Address:	<CONTAINER_IP>:53

Non-authoritative answer:
Name:	boinc-cpu.dns.podman
Address: <CONTAINER_IP>
```

- Test client resolves `boinc-cpu` by service name
- Podman DNS works correctly on `homelab-boinc-cpu` network

---

## Architecture Explanation

### How BOINC CPU-Only Works

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

### Key Design Decisions

1. **Why `docker.io/boinc/client:latest` instead of `intel`?**
   - The `intel` tag includes Intel GPU/OpenCL libraries (~422MB)
   - The `latest` tag is CPU-only, same base image without GPU support
   - Both use Ubuntu 24.04 LTS as the base

2. **Why no `/dev/dri` passthrough?**
   - CPU-only image has no OpenCL support, so GPU device access is irrelevant
   - Saves a mount point and avoids potential rootless Podman issues with GPU devices
   - If the user later wants to run GPU-compatible projects, they can switch to the `intel` tag

3. **Why separate data directory (`boinc-cpu-data`)?**
   - Keeps CPU and GPU BOINC instances independent
   - Each can attach to different projects
   - Prevents credential/state conflicts
   - If one needs to be rebuilt, the other's data is untouched

4. **Why port 31417 instead of 31416?**
   - Both containers use bridge networking (not host networking)
   - Port mapping is on the host, so two containers can't both map to 31416
   - 31417 is the next available BOINC data port

5. **Why bridge network instead of `network_mode: host`?**
   - Rootless Podman has limitations with host networking
   - Bridge network works fine since BOINC only needs outbound internet
   - GUI RPC is bound to localhost, accessible via `boinccmd`

---

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references (docker.io/boinc/client:latest)
- [x] Ports are > 1024 (31417)
- [x] No GPU passthrough (CPU-only by design)
- [x] Test client container included (homelab-boinc-cpu-test)
- [x] Healthcheck works (boinccmd --passwd with --get_cc_status)
- [x] Volumes configured (bind mount for /var/lib/boinc)
- [x] Network follows homelab-* pattern (homelab-boinc-cpu)
- [x] README includes setup steps
- [x] Verification commands documented
- [ ] CPU actually processes work units (pending project account + attachment)
```

---

## Common Questions

### Q: How is this different from the GPU version?
**A:** The CPU-only image (`boinc/client:latest`) doesn't include Intel OpenCL libraries. This means:
- No GPU work units will be assigned
- More BOINC projects are compatible (some don't support Intel GPU)
- Slightly smaller image (no GPU runtime libraries)
- Same RAM footprint (~4MB idle)

### Q: Can I run both CPU and GPU BOINC simultaneously?
**A:** Yes! They use separate data directories, networks, and host ports. This is useful for:
- Running GPU-compatible projects on the GPU instance
- Running CPU-only projects on the CPU instance
- Maximizing compute across both CPU and GPU

### Q: Will this use too much CPU when I'm working?
**A:** BOINC defaults to "suspend when computer is in use." On a laptop, it will also suspend when on battery power. You can adjust these preferences via BOINC Manager or the project web interface.

### Q: What if I want to switch to GPU later?
**A:** Change the image in `docker-compose.yml` from `docker.io/boinc/client:latest` to `docker.io/boinc/client:intel`, add `/dev/dri:/dev/dri` to volumes, and redeploy with `podman compose down -v && podman compose up -d`.

---

## What Didn't Work

1. **No issues encountered** - The CPU-only setup is simpler than the GPU variant and had no problems during setup.

---

## Lessons Learned

1. **CPU-only image is functionally identical minus GPU** - The `latest` tag is the same Ubuntu base without OpenCL libraries. Everything else (commands, healthcheck, networking) works the same way.

2. **GPU status line still appears in compute status** - Even though there's no GPU, `boinccmd --get_cc_status` shows a "GPU status" section with "not suspended." This is just the default BOINC output format, not an actual GPU.

3. **Battery detection is the same** - Both CPU and GPU variants suspend when on battery power. This is a BOINC default, not image-specific.

4. **Port separation is necessary** - When running both CPU and GPU BOINC, each needs a different host port (31416 vs 31417) since both use bridge networking with port mapping.

5. **Separate data directories prevent conflicts** - Keeping CPU and GPU BOINC state separate avoids credential and project conflicts. Each instance can attach to different projects independently.

---

## Resource Usage

| Metric | Value | Budget (10B) | Status |
|--------|-------|-------------|--------|
| RAM | 3.744MB | 200MB | Well within budget |
| CPU | 0.45% (idle) | - | Minimal |
| Disk | ~400MB image + growing | 1-3GB | Within budget |
| GPU | N/A (CPU-only) | - | N/A |

---

## Next Steps (When Resuming)

1. **Create a BOINC project account** - Choose a project (Folding@home, Einstein@Home, PrimeGrid, etc.) and register
2. **Attach to the project** - Use the account's auth string with `boinccmd --project_attach <project_url> <auth_string>`
3. **Wait for work unit assignment** - Can take hours after initial attachment
4. **Verify CPU actually processes work** - Check `boinccmd --get_task_summary` for CPU tasks
5. **Monitor resource usage during active computation**
6. **Consider running alongside GPU BOINC** for maximum compute

---

*Timeline created: April 23, 2026*  
*Session ended: Container running, awaiting project account creation*
