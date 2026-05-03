# Experiment 9D: ClamAV Virus Scanner - Lab Notebook

**Date:** April 23-24, 2026  
**Status:** Complete - Working scanner with EICAR detection  
**Location:** `~/homelab/reactive-processing/clamav-scanner/`

---

## Setup Phase

### Errors Encountered & Resolutions

#### Error 1: `clamd/clamav:1.2` image not available
**Symptom:** `podman compose up` fails with `requested access to the resource is denied`  
**Root cause:** The `clamd/clamav` image on Docker Hub is either private or doesn't exist.  
**Resolution:** Switched to single-container approach using `debian:bookworm-slim` with ClamAV packages installed via apt.

#### Error 2: pip PEP 668 externally-managed-environment
**Symptom:** `pip3 install watchdog` fails with `This environment is externally managed`  
**Root cause:** Debian 12 enforces PEP 668.  
**Resolution:** Added `--break-system-packages` flag to pip install in Dockerfile.

#### Error 3: `clamdscan: command not found`
**Symptom:** Scanner logs show `/app/start.sh: line 8: clamdscan: command not found`  
**Root cause:** The `clamav` package (which provides `clamdscan`) was not installed. Only `clamav-daemon`, `clamav-freshclam`, and `clamav-base` were installed.  
**Resolution:** Added `clamav` package to Dockerfile apt install list.

#### Error 4: `clamdscan --daemon` is the wrong command
**Symptom:** `clamdscan` is the client tool, not the daemon launcher.  
**Root cause:** Confusion between `clamd` (daemon) and `clamdscan` (client).  
**Resolution:** Changed start.sh to launch `clamd` directly.

#### Error 5: `freshclam --foreground` blocks startup
**Symptom:** Scanner never starts because freshclam runs indefinitely in foreground.  
**Root cause:** `freshclam --foreground` runs as a daemon that periodically checks for updates.  
**Resolution:** Run freshclam without `--foreground` (it daemonizes itself), then start clamd.

#### Error 6: Socket bind permission denied
**Symptom:** `ERROR: LOCAL: Socket file /var/run/clamav/clamd.ctl could not be bound: Permission denied`  
**Root cause:** `clamd.conf` has `User clamav` but the clamav user doesn't exist in the container. ClamAV uses the FIRST `User` directive it finds.  
**Resolution:** Use `sed -i 's/^User clamav/User root/'` to replace the user directive before starting clamd.

#### Error 7: `clamdscan` not in Debian 12 packages
**Symptom:** `clamdscan` binary not found even after installing `clamav` package.  
**Root cause:** Debian 12 split ClamAV packages differently - `clamdscan` was removed. The `clamav` package provides `clamscan`, `clambc`, `clamsubmit`, `sigtool` but NOT `clamdscan`.  
**Resolution:** Rewrote scanner.py to communicate with clamd directly via Python Unix socket instead of using `clamdscan`.

#### Error 8: Healthcheck used wrong command for clamd protocol
**Symptom:** Healthcheck sent `STAT` command but clamd returned `UNKNOWN COMMAND`.  
**Root cause:** ClamAV 1.4.3 doesn't support `STAT` command. It supports `PING` which returns `PONG`.  
**Resolution:** Changed both the compose healthcheck and scanner's `is_clamav_ready()` to use `PING`.

#### Error 9: Scanner couldn't quarantine files (read-only filesystem)
**Symptom:** `[ERROR] Failed to quarantine: Read-only file system`  
**Root cause:** Input directory mounted as `:ro`, scanner tried to move files from it.  
**Resolution:** Scanner now copies files to temp location for scanning, then routes clean files to output/ and infected files to quarantine/ without modifying the input directory.

---

## Architecture

```
┌─────────────────────────────────────────────┐
│           homelab-clamav-scanner            │
│                                             │
│  ┌──────────┐    ┌──────────────────────┐   │
│  │ freshclam │───>│  /var/lib/clamav/    │   │
│  │ (startup) │    │  (virus definitions) │   │
│  └──────────┘    └──────────────────────┘   │
│                            │                 │
│                            v                 │
│  ┌──────────────────────────────────────┐   │
│  │          clamd (daemon)               │   │
│  │    /var/run/clamav/clamd.ctl (socket) │   │
│  └──────────────────────────────────────┘   │
│                    │                         │
│                    v                         │
│  ┌──────────────────────────────────────┐   │
│  │     scanner.py (Python + watchdog)    │   │
│  │  - Watches /scan for new files        │   │
│  │  - Copies to /tmp for scanning        │   │
│  │  - Sends SCAN command via socket      │   │
│  │  - Routes: clean -> /output           │   │
│  │            infected -> /quarantine     │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  Volumes:                                   │
│    ./input -> /scan (ro)                    │
│    ./output -> /output                      │
│    ./quarantine -> /quarantine              │
│    clamav_data -> /var/lib/clamav           │
└─────────────────────────────────────────────┘
         │
         v
┌─────────────────────────────────────────────┐
│           homelab-clamav-scanner-test               │
│         (alpine:3.21, sleep 3600)           │
└─────────────────────────────────────────────┘
```

---

## Verification

### Container Status
```bash
$ podman ps --filter name=homelab-clamav
CONTAINER ID  IMAGE                             STATUS
9afbb535b379  localhost/clamav-scanner:latest   Up 2 minutes (healthy)
 640c5192ea11  docker.io/library/alpine:3.21     Up 2 minutes
```

### Health Check
```bash
# Healthcheck uses: echo PING | nc -U /var/run/clamav/clamd.ctl
# Returns: PONG
```

### Clean File Test
```bash
$ echo "Hello world" > input/test.txt
# Logs show:
# [SCANNING] test.txt (12 bytes)
# [CLEAN] No threats detected
# [OUTPUT] Saved to: /output/20260424014745_test.txt
```

### Malware Detection Test (EICAR)
```bash
$ echo -n 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > input/eicar.com
# Logs show:
# [SCANNING] eicar.com (68 bytes)
# [ALERT] VIRUS DETECTED: Eicar-Test-Signature
# [QUARANTINE] Saved to: /quarantine/eicar.com.20260424014757.infected
```

---

## Design Decisions

### Why Python socket instead of clamdscan?
- Debian 12 removed `clamdscan` from its packages
- Direct socket communication gives full control over the clamd protocol
- `PING` for health checks, `SCAN /path` for file scanning
- No external dependencies beyond Python stdlib

### Why copy files to /tmp before scanning?
- Input directory is mounted read-only (`:ro`) to prevent accidental modification
- Scanner copies to temp, scans temp file, then routes to output/quarantine
- Original files in input/ are never modified or deleted

### Why `User root` in clamd.conf?
- The `clamav` user doesn't exist in the container
- Running as root in a container is acceptable (container isolation provides security)
- Socket mode `666` ensures the scanner process can always connect

### Why PING instead of STAT for healthcheck?
- ClamAV 1.4.3 only supports `PING` -> `PONG`
- `STAT` was removed or renamed in newer versions
- `PING` is the simplest liveness probe

---

## What Didn't Work (Dead Ends)

1. **Separate clamav + clamav-scanner containers:** `clamd/clamav` Docker image doesn't exist publicly.

2. **Using `clamdscan --fdpass`:** The `clamdscan` binary doesn't exist in Debian 12 packages.

3. **Using `clamscan --fdpass`:** `clamscan` doesn't support the `--fdpass` flag in version 1.4.3. Only communicates standalone.

4. **Alpine-based image:** ClamAV package availability is poor on Alpine. Would require building from source.

5. **Appending `User root` to clamd.conf:** ClamAV uses the FIRST occurrence of a directive. Appending doesn't override `User clamav` at line 10. Must use `sed` to replace.

6. **Checking socket file existence for readiness:** `[ -S /var/run/clamav/clamd.ctl ]` returns true before clamd is listening. Need to actually send a command (PING) to verify readiness.

---

## Testing Checklist

- [x] Compose file uses full image references
- [x] No ports needed (Unix socket communication)
- [x] Test client container included
- [x] Volumes configured (named `clamav_data` + bind mounts)
- [x] Network name follows `homelab-*` pattern (`homelab-clamav-net`)
- [x] ClamAV daemon starts successfully
- [x] Scanner can connect to ClamAV daemon
- [x] EICAR test file detection works
- [x] Quarantine functionality works
- [x] Healthcheck passes (container shows "healthy")
- [x] Clean files routed to output directory

---

## Resource Usage

```bash
$ podman stats --no-stream homelab-clamav-scanner
CONTAINER    CPU %    MEM USAGE/LIMIT    MEM %    NET I/O    BLOCK I/O
homelab-...  0.15%    98.3MB / 12GB      0.8%     0B / 0B    4.2MB / 1.1MB
```

| Resource | Actual | Budget | Notes |
|----------|--------|--------|-------|
| RAM | ~98MB | 200-400MB | Well under budget |
| Storage | ~150MB image | 150-200MB | Virus DB ~5MB, image ~145MB |
| CPU | <1% | 4-6 threads | Background task, minimal CPU |

---

## Lessons Learned

1. **Debian package splits change between versions.** What was `clamdscan` in one version may be removed or merged in another. Always verify binary availability.

2. **ClamAV config uses first-match for directives.** Appending `User root` to clamd.conf doesn't work because `User clamav` at line 10 takes precedence. Use `sed` to replace.

3. **Socket file existence != service readiness.** The socket file can exist before clamd is listening. Always send a test command (PING) to verify.

4. **`freshclam --foreground` blocks.** It's designed to run as a background daemon. Run it without `--foreground` for startup scripts.

5. **Read-only mounts protect source data.** Mounting input as `:ro` prevents the scanner from accidentally deleting/modifying source files. Copy to temp for scanning.

6. **Running as root in containers is fine.** Container isolation provides the security boundary. The `clamav` user adds no value inside a container.

---

## Common Questions

**Q: How do I add custom virus signatures?**  
A: Drop `.cvd` or `.db` files into the `clamav_data` volume at `/var/lib/clamav/`. ClamAV loads them on startup.

**Q: How often are virus definitions updated?**  
A: Freshclam runs at startup. For ongoing updates, add a cron job or separate freshclam container.

**Q: Can I scan existing files, not just new ones?**  
A: The scanner uses watchdog for reactive scanning. For batch scans, run `podman exec homelab-clamav-scanner python3 /app/scanner.py --batch /scan` (would need to add this feature).

**Q: What happens if clamd crashes?**  
A: The container will restart (restart: unless-stopped). The startup script will reinitialize everything.

---

*Last updated: April 24, 2026*
