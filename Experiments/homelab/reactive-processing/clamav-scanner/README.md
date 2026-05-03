# ClamAV Virus Scanner

Reactive file virus scanner using ClamAV daemon, watching a directory for new files and routing them based on scan results.

## How It Works

```
Drop file in input/  -->  Scanner detects  -->  Scan with ClamAV  -->  Route result
                                                                    ├── Clean  --> output/
                                                                    └── Infected --> quarantine/
```

1. **freshclam** runs at startup to download latest virus definitions
2. **clamd** (ClamAV daemon) starts and listens on Unix socket at `/var/run/clamav/clamd.ctl`
3. **scanner.py** (Python + watchdog) watches the input directory for new files
4. When a file appears, it's copied to a temp location and scanned via the clamd socket
5. Clean files are copied to `output/`, infected files are moved to `quarantine/`

## Quick Start

```bash
# Start the scanner
podman compose up -d

# Check status
podman ps --filter name=homelab-clamav

# View logs
podman logs -f homelab-clamav-scanner
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| clamav-scanner | None (Unix socket) | ClamAV daemon + Python file watcher scanner |
| test-client | None | Alpine container for cross-container testing |

## Usage

### Scan a File

Drop any file into the `input/` directory:

```bash
echo "Hello world" > input/document.txt
# Wait ~3 seconds, then check output/
ls output/
# output/20260424014745_document.txt
```

### Test Malware Detection

Use the EICAR test string (safe, standard antivirus test):

```bash
echo -n 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > input/eicar-test.com
# Check logs for detection:
podman logs homelab-clamav-scanner | grep ALERT
# [ALERT] VIRUS DETECTED: Eicar-Test-Signature

# Check quarantine:
ls quarantine/
# eicar-test.com.20260424014757.infected
```

### Stop the Scanner

```bash
podman compose down
```

## Directory Structure

```
clamav-scanner/
├── docker-compose.yml    # Container orchestration
├── Dockerfile            # Custom image with ClamAV + Python
├── scanner.py            # File watcher and scanner
├── start.sh              # Startup script (freshclam + clamd + scanner)
├── input/                # Drop files here to scan (read-only mount)
├── output/               # Clean files appear here
└── quarantine/           # Infected files moved here
```

## Verification

### Check Container Health

```bash
podman ps --filter name=homelab-clamav
# Should show: Up X minutes (healthy)
```

### Check Scanner Logs

```bash
podman logs homelab-clamav-scanner
```

Expected output for a clean file:
```
[SCANNING] document.txt (38 bytes)
  [CLEAN] No threats detected
  [OUTPUT] Saved to: /output/20260424014745_document.txt
```

Expected output for malware:
```
[SCANNING] eicar.com (68 bytes)
  [ALERT] VIRUS DETECTED: Eicar-Test-Signature
  [QUARANTINE] Saved to: /quarantine/eicar.com.20260424014757.infected
```

### Test from Another Container

```bash
podman exec homelab-clamav-scanner-test sh -c 'echo test > /dev/null && echo "Test client works"'
```

## Configuration

Environment variables (in `docker-compose.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `SCAN_DIR` | `/scan` | Input directory to watch |
| `OUTPUT_DIR` | `/output` | Directory for clean files |
| `QUARANTINE_DIR` | `/quarantine` | Directory for infected files |

## Resource Usage

- **RAM:** ~100MB (ClamAV daemon + Python scanner)
- **Storage:** ~150MB image + ~5MB virus definitions
- **CPU:** <1% (background task)

## Troubleshooting

### Scanner not detecting files

1. Check container is healthy: `podman ps --filter name=homelab-clamav`
2. Check logs: `podman logs homelab-clamav-scanner`
3. Verify file was dropped (not modified) in `input/`
4. Files starting with `.` or ending with `.tmp`/`.part` are skipped

### ClamAV daemon not starting

```bash
# Check clamd logs
podman exec homelab-clamav-scanner cat /var/log/clamav/clamav.log | tail -20

# Verify socket exists
podman exec homelab-clamav-scanner ls -la /var/run/clamav/
```

### Virus definitions not updating

```bash
# Force a freshclam run
podman exec homelab-clamav-scanner freshclam
```

## Architecture

- **Single container** with ClamAV daemon, freshclam, and Python scanner
- **Unix socket** communication between scanner and clamd (no network ports)
- **Watchdog** library for efficient file system monitoring
- **Read-only input** mount protects source files from modification
- **Hybrid volumes**: named volume for virus DB, bind mounts for input/output/quarantine

## Cleanup

```bash
podman compose down -v
```

## See Also

- [Lab Notebook](experiment-timeline.md) - Full debugging journey and lessons learned
- [ClamAV Documentation](https://docs.clamav.net/)
