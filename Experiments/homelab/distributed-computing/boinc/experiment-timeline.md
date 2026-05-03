# BOINC Experiment 10A - Experiment Timeline

**Started:** April 20, 2026  
**Status:** Paused (container running, GPU working, awaiting project account)

---

## Setup Phase

### Pre-flight Checks

**GPU Device Nodes:**
```
$ ls -la /dev/dri
total 0
drwxr-xr-x  3 root root        100 Apr 20 03:52 .
drwxr-xr-x 21 root root        4720 Apr 20 03:52 ..
drwxr-xr-x  2 root root          80 Apr 20 03:52 by-path
crw-rw----+ 1 root video  226,   1 Apr 20 03:52 card1
crw-rw----+ 1 root render 226, 128 Apr 20 03:52 renderD128
```
- `card1` (not `card0`) - this is normal on some systems
- `renderD128` exists - needed for OpenCL/GPU compute

**Intel i915 Driver:**
```
$ lsmod | grep i915
i915                 4812800  55
drm_buddy              28672  2 xe,i915
ttm                   126976  3 drm_ttm_helper,xe,i915
...
```
- Driver is loaded and active (55 users)

**Video Group Membership:**
```
$ cat /etc/group | grep video
video:x:44:cosmic-greeter,greeter,ollama
```
- User `labratorian` is NOT in the `video` group
- Attempted to add via `usermod -aG video labratorian` - failed (no sudo password available)
- **Impact:** GPU passthrough still worked anyway (same pattern as OpenVINO/llama.cpp experiments)

**Resource Availability:**
```
$ free -h
Mem: 11Gi total, 5.5Gi used, 1.6Gi free, 5.9Gi available
$ df -h /
225G total, 111G used, 103G available (52%)
```
- Plenty of RAM and disk space for BOINC

**Port Conflicts:**
- Port 31416 (BOINC data port) - not in use
- No conflicts

**Stale Containers:**
- Many exited containers from previous experiments (RabbitMQ, Kafka, Redis, Gitea, etc.)
- No running containers competing for resources
- Active: `homelab-doc-converter` and `homelab-pdf-converter` (lightweight)

### Image Pull

```
$ podman pull docker.io/boinc/client:intel
Trying to pull docker.io/boinc/client:intel...
...
392cc9f9cfeb3dd3707dc057e6d4b1dc6700f32fbd6e5cd9502ea8df07396ff2
```
- Pulled successfully, ~422MB image
- Based on Ubuntu 24.04.2 LTS

### Compose File Creation

Created `docker-compose.yml` with:
- `docker.io/boinc/client:intel` image (full reference, required by Podman)
- GPU passthrough via `/dev/dri:/dev/dri`
- Bind mount: `./boinc-data:/var/lib/boinc`
- GUI RPC password: `boinc-homelab-2026`
- Port 31416 mapped (BOINC data transfer port)
- Bridge network: `homelab-boinc`
- Healthcheck: `boinccmd --get_cc_status` (see issues below)

### Container Start

```
$ podman compose up -d
podman-compose version: 1.0.6
using podman version: 4.9.3
...
80c9fab4a422666a2f3ff6fad2469aae77eabb7d0b2fb469251b73f70c737d49
exit code: 0
```
- Container started successfully
- Status: `Up 5 seconds (starting)`

---

## Verification Phase

### Container Status
```
$ podman ps -a --filter name=homelab-boinc
CONTAINER ID  IMAGE                         STATUS                     NAMES
80c9fab4a422  docker.io/boinc/client:intel  Up 5 seconds (starting)    homelab-boinc
```

### Initial Logs - GPU Detection SUCCESS!
```
20-Apr-2026 20:17:29 [---] Data directory: /var/lib/boinc
20-Apr-2026 20:17:30 [---] OpenCL: Intel GPU 0: Intel(R) Iris(R) Xe Graphics (driver version 23.43.027642, device version OpenCL 3.0 NEO, 10535MB, 10535MB available, 832 GFLOPS peak)
20-Apr-2026 20:17:30 [---] Creating new client state file
20-Apr-2026 20:17:30 [---] Processor: 8 GenuineIntel 11th Gen Intel(R) Core(TM) i5-1135G7 @ 2.40GHz
20-Apr-2026 20:17:30 [---] Memory: 11.41 GB physical, 15.41 GB virtual
20-Apr-2026 20:17:30 [---] This computer is not attached to any projects
20-Apr-2026 20:17:30 Initialization completed
20-Apr-2026 20:17:30 [---] Suspending GPU computation - computer is in use
```

**Key findings:**
- **GPU DETECTED:** Intel Iris Xe Graphics with OpenCL 3.0 NEO driver
- **832 GFLOPS** peak compute performance
- **10535MB (~10.3GB)** available for GPU (shared system memory)
- GPU is suspended because "computer is in use" (default BOINC behavior)
- No projects attached yet (expected for fresh install)

### GPU Device Access in Container
```
$ podman exec homelab-boinc ls -la /dev/dri
total 0
drwxr-xr-x  2 root   root          80 Apr 20 20:17 .
drwxr-xr-x  6 root         360 Apr 20 20:17 ..
crw-rw----+ 1 nobody nogroup 226,   1 Apr 20 04:52 card1
crw-rw----+ 1 nobody nogroup 226, 128 Apr 20 04:52 renderD128
```
- Both `card1` and `renderD128` are accessible inside the container
- Ownership changed to `nobody:nogroup` (rootless Podman remapping)

### BOINC Client Communication - ISSUES

**Problem 1: `boinccmd --status` returns usage text**
```
$ podman exec homelab-boinc boinccmd --status
usage: boinccmd [--host hostname] [--passwd passwd] [--unix_domain] command
...
```
- The `--status` command alone doesn't work as expected
- This is likely because `boinccmd` needs to connect via the GUI RPC socket
- The default auth reads from `gui_rpc_auth.cfg` which contains `boinc-homelab-2026`

**Problem 2: Various argument orderings all return usage text**
- `boinccmd --passwd <pass> --status` - fails
- `boinccmd --status --passwd <pass>` - fails
- `boinccmd --host 127.0.0.1 --passwd <pass> --status` - fails
- `sh -c 'boinccmd --status'` - fails

**Solution found: `boinccmd --get_host_info` works!**
```
$ podman exec homelab-boinc sh -c 'boinccmd --get_host_info'
timezone: -14400
  domain name: 80c9fab4a422
  IP addr: <CONTAINER_IP>
  #CPUS: 8
  CPU vendor: GenuineIntel
  CPU model: 11th Gen Intel(R) Core(TM) i5-1135G7 @ 2.40GHz
  Intel GPU
    OpenCL: Intel GPU 0: Intel(R) Iris(R) Xe Graphics (driver version 23.43.027642, device version OpenCL 3.0 NEO, 10535MB, 10535MB available, 832 GFLOPS peak)
```
- This confirms BOINC is running and can report GPU status
- The GUI RPC socket IS working (otherwise this would fail too)

**Working commands:**
- `boinccmd --get_host_info` - shows full system + GPU info
- `boinccmd --get_cc_status` - shows CPU/GPU/Network computing status

**Healthcheck updated:** Changed from `boinccmd --status` to `boinccmd --get_cc_status`

### GPU Computing Status
```
$ podman exec homelab-boinc sh -c 'boinccmd --get_cc_status'
CPU status
    not suspended
    current mode: according to prefs
GPU status
    suspended: computer is in use
    current mode: according to prefs
Network status
    not suspended
    current mode: according to prefs
```
- GPU is suspended because the computer is "in use" (default behavior)
- This is normal - BOINC won't compute while you're actively using the laptop
- Once projects are attached and work units are assigned, GPU will activate when idle

### Resource Usage
```
$ podman stats homelab-boinc --no-stream
ID            NAME           CPU %  MEM USAGE / LIMIT  MEM %  PIDS
80c9fab4a422  homelab-boinc  0.30%  3.76MB / 12.25GB   0.03%  2
```
- **RAM:** 3.76MB (extremely lightweight)
- **CPU:** 0.30% (idle)
- **Processes:** 2 (boinc main + shell)

### Empty State (Expected)
```
$ podman exec homelab-boinc sh -c 'boinccmd --get_simple_gui_info'
======== Projects ========
======== Tasks ========
```
- No projects attached - expected for fresh install
- No tasks running - expected

---

## Configuration Phase (In Progress)

### Healthcheck Fix

**Problem:** Container shows `unhealthy` status despite BOINC running fine.

**Root cause:** The healthcheck command `boinccmd --get_cc_status` fails when run by Podman's healthcheck mechanism. The command works interactively but fails in the healthcheck context (likely auth file resolution issue).

**Resolution:** Added `--passwd` flag to the healthcheck command:
```yaml
test: ["CMD-SHELL", "boinccmd --passwd boinc-homelab-2026 --get_cc_status > /dev/null 2>&1 || exit 1"]
```
Redeployed with `podman compose down && podman compose up -d`.

### Project Attachment Attempt - World Community Grid

**Command:**
```bash
podman exec homelab-boinc sh -c 'boinccmd --project_attach https://www.worldcommunitygrid.org boinc-homelab-2026'
```

**Result:** Attached to WCG but scheduler returned HTTP 503 (Service Unavailable).

**Logs:**
```
20-Apr-2026 20:38:43 [https://www.worldcommunitygrid.org/] Sending scheduler request: Project initialization.
20-Apr-2026 20:38:43 [https://www.worldcommunitygrid.org/] Requesting new tasks for CPU and Intel GPU
20-Apr-2026 20:38:45 [https://www.worldcommunitygrid.org/] Scheduler request to https://scheduler.worldcommunitygrid.org/boinc/wcg_cgi/fcgi failed: HTTP service unavailable
```

**Discovery:** WCG (like all major BOINC projects) requires a registered account. The password `boinc-homelab-2026` is just the GUI RPC auth, not a WCG account credential. The scheduler needs valid WCG account credentials.

**Next step:** User needs to create a WCG account at https://www.worldcommunitygrid.org and use the account's auth string for attachment.

### User Decision: Pause at Current State

User decided to pause the experiment at the container setup stage rather than completing project attachment. The container is fully functional:
- GPU detected and working
- BOINC client running
- Healthcheck fixed and passing
- Ready to attach to any project once account is created

---

## Architecture Explanation

### How BOINC Works in This Setup

```
┌─────────────────────────────────────────────┐
│         Host System (Dell Inspiron)          │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │  /dev/dri (card1, renderD128)        │    │
│  │     │                                │    │
│  │     ▼                                │    │
│  │  ┌────────────────────────────────┐  │    │
│  │  │  homelab-boinc (Podman)        │  │    │
│  │  │                                │  │    │
│  │  │  BOINC Client (root)           │  │    │
│  │  │    ├─ OpenCL (Iris Xe GPU)     │  │    │
│  │  │    ├─ GUI RPC (localhost)      │  │    │
│  │  │    └─ /var/lib/boinc (volume)  │  │    │
│  │  └────────────────────────────────┘  │    │
│  └──────────────────────────────────────┘    │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │  homelab-boinc-test (Alpine)         │    │
│  │  (test client - sleep 3600)          │    │
│  └──────────────────────────────────────┘    │
│                                              │
│  Network: homelab-boinc (bridge)             │
└─────────────────────────────────────────────┘
         │
         ▼ (network)
┌─────────────────────────────────────────────┐
│        BOINC Project Server                  │
│  (Folding@home, Einstein@Home, etc.)         │
│                                              │
│  Sends: Work units (GPU/CPU tasks)           │
│  Receives: Computed results                  │
└─────────────────────────────────────────────┘
```

### Key Design Decisions

1. **Why `docker.io/boinc/client:intel` tag?**
   - The `intel` tag includes Intel GPU/OpenCL support (needed for Iris Xe)
   - The base `latest` tag is CPU-only
   - Full image reference required by Podman

2. **Why `/dev/dri` passthrough?**
   - BOINC needs access to the GPU for OpenCL acceleration
   - This is the same pattern used by OpenVINO and llama.cpp experiments
   - Works in rootless Podman without being in the `video` group

3. **Why bridge network instead of `network_mode: host`?**
   - The experiments.md spec suggested `network_mode: host` for BOINC
   - However, rootless Podman has limitations with host networking
   - Bridge network works fine since BOINC only needs outbound internet access
   - GUI RPC is bound to `127.0.0.1` inside the container, accessible via `boinccmd`
   - Port 31416 is mapped for data transfer

4. **Why bind mount for `/var/lib/boinc`?**
   - Persistent BOINC state (projects, credentials, completed work)
   - Easy to backup and inspect
   - Survives container rebuilds

5. **Why port 31416?**
   - This is the default BOINC data port (exposed by the image)
   - Used for downloading/uploading work units
   - Not a web UI - just a data transfer port

---

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references (docker.io/boinc/client:intel)
- [x] Ports are > 1024 (31416)
- [x] GPU passthrough configured (/dev/dri)
- [x] Test client container included (homelab-boinc-test)
- [x] Healthcheck works (fixed with --passwd flag, redeployed)
- [x] Volumes configured (bind mount for /var/lib/boinc)
- [x] Network follows homelab-* pattern (homelab-boinc)
- [x] README includes setup steps
- [x] Verification commands documented
- [ ] GPU actually processes work units (pending project account + attachment)
```

---

## Common Questions

### Q: Why is the GPU suspended?
**A:** BOINC defaults to "suspend GPU when computer is in use." Since you're actively using the laptop, BOINC won't run GPU tasks until the computer is idle (default: 3 minutes of no mouse/keyboard input). This is by design to avoid impacting your work.

### Q: Will this use too much RAM?
**A:** No. The BOINC client itself uses only ~4MB RAM. GPU compute uses shared system memory (~10GB available). Even with work units active, total usage should stay under 500MB.

### Q: Can I run this alongside other containers?
**A:** Yes. BOINC is lightweight and uses minimal resources when idle. The GPU will only activate when idle and when you've attached projects with work units.

### Q: What if GPU doesn't work with a specific project?
**A:** Not all BOINC projects support Intel OpenCL. If a project doesn't assign GPU work, BOINC will fall back to CPU work. You can also switch to the `boinc/client:latest` (CPU-only) image if needed.

### Q: How do I check if GPU is actually computing?
**A:** Run `boinccmd --get_cc_status` - if GPU status shows "suspended: computer is in use", it's waiting for idle time. When actively computing, it would show current GPU usage.

---

## What Didn't Work

1. **`boinccmd --status` command** - Returns usage text instead of status. The `--get_host_info` and `--get_cc_status` commands work as alternatives.

2. **Adding user to `video` group** - `usermod -aG video labratorian` failed because sudo requires a password that wasn't provided. However, GPU passthrough worked anyway (same as other GPU experiments).

3. **`podman compose up -d` from subdirectory** - Running from `/home/labratorian/homelab` with `podman compose up -d` fails with "no compose.yaml found" even when the compose file is in a subdirectory. Need to `cd` into the experiment directory first. This is a recurring pattern across all experiments.

4. **Healthcheck with `boinccmd --get_cc_status` (without --passwd)** - The healthcheck failed with exit code 1 despite the command working interactively. Adding `--passwd boinc-homelab-2026` to the healthcheck command fixed it.

5. **WCG attachment with GUI RPC password** - Using the GUI RPC password (`boinc-homelab-2026`) for project attachment failed. This password is only for local GUI RPC access, not for WCG account authentication. WCG requires a separate registered account with its own auth string.

---

## Lessons Learned

1. **GPU passthrough works in rootless Podman** - Despite not being in the `video` group, `/dev/dri` passthrough works for Intel Iris Xe. This is consistent with the OpenVINO and llama.cpp experiments.

2. **BOINC client is extremely lightweight** - Only ~4MB RAM, minimal CPU when idle. Great for always-on workloads.

3. **`boinccmd` command variations matter** - Not all commands work the same way. `--get_host_info` and `--get_cc_status` are reliable for checking status.

4. **Healthcheck needs explicit password** - The `boinccmd` command in healthcheck context doesn't automatically find the auth file. Must pass `--passwd` explicitly in the healthcheck command.

5. **GPU detection happens at container start** - The OpenCL initialization happens immediately (within 1 second), so GPU availability can be verified right after `podman compose up -d`.

6. **Default BOINC behavior is conservative** - GPU is suspended when "computer is in use." This is good for a laptop but means you need to wait for idle time or manually enable GPU compute.

7. **All major BOINC projects require registration** - There are no significant projects that allow anonymous compute. The GUI RPC password is separate from project account credentials.

8. **WCG scheduler can be unreliable** - The WCG scheduler returned HTTP 503 even after a successful initial attach. May need to retry or try a different project first.

---

## Resource Usage

| Metric | Value | Budget | Status |
|--------|-------|--------|--------|
| RAM | 3.76MB | 300MB | Well within budget |
| CPU | 0.30% (idle) | - | Minimal |
| Disk | ~422MB image + growing | 1-5GB | Within budget |
| GPU | Intel Iris Xe, 832 GFLOPS | - | Working |

---

## Next Steps (When Resuming)

1. **Create a BOINC project account** - Choose a project (WCG, Einstein@Home, Folding@home, etc.) and register
2. **Attach to the project** - Use the account's auth string with `boinccmd --project_attach <project_url> <auth_string>`
3. **Wait for work unit assignment** - Can take hours after initial attachment
4. **Verify GPU actually processes work** - Check `boinccmd --get_task_summary` for GPU tasks
5. **Monitor resource usage during active computation**
6. **Consider adding more projects** once the first one is stable

---

*Timeline created: April 20, 2026*  
*Session ended: Container running with fixed healthcheck, paused pending project account creation*
