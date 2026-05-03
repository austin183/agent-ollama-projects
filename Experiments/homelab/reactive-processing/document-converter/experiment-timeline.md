# Experiment 9B: Document to PDF Converter - Timeline

## Setup Phase

### Initial Planning
- Chose LibreOffice headless over pdftk for broader format support
- Target RAM: ~400MB (LibreOffice is heavier than alternatives)
- Need a watcher script to monitor input directory reactively

### Image Selection
- **linuxserver/libreoffice:latest** - Chosen for being well-maintained, pre-configured, and reasonably sized (~400MB)
- Already has Python 3.12 installed (no need to install in Dockerfile)
- `watchdog` package was already present in the image

### File Structure Created
```
reactive-processing/document-converter/
├── converter.py          # Watcher + converter logic
├── Dockerfile            # Build from linuxserver/libreoffice
├── docker-compose.yml    # Services + networking
├── input/                # Drop zone for documents
├── output/               # Converted PDFs
├── processed/            # Original files after conversion
└── logs/                 # Converter logs
```

### Build & First Start
```bash
podman compose build && podman compose up -d
```
- Image built successfully from `docker.io/linuxserver/libreoffice:latest`
- Both `doc-converter` and `test-client` containers started
- Network `homelab-docconv-network` created

## Verification Phase

### Test 1: ODT Conversion
Created a minimal valid ODT file using Python's zipfile module (ODT is a ZIP archive with specific XML structure).

**Command:**
```bash
# Created test-document.odt in input/
sleep 5
podman logs homelab-doc-converter | grep 'Converting'
```

**Result:**
```
[2026-04-20 23:36:05] Converting: test-document.odt
[2026-04-20 23:36:08]   -> test-document.pdf (18216 bytes)
```

**Issue discovered:** File was re-processed continuously because it stayed in the input directory.

### Test 2: Fix Duplicate Processing
Added logic to move source files to `processed/` after successful conversion.

**Initial fix attempt:** Used `os.rename()` to move files.

**Issue:** `Cross-device link` error (errno 18) because bind mounts are separate filesystems.

**Resolution:** Changed to `shutil.copy2()` + `os.remove()` which works across filesystem boundaries.

### Test 3: DOCX Conversion
Created a minimal valid DOCX file (also a ZIP archive with Office Open XML structure).

**Result:**
```
[2026-04-20 23:40:42] Converting: sample.docx
[2026-04-20 23:40:43]   -> Moved source to processed/
```

PDF output verified:
```
sample.pdf: PDF document, version 1.7, 1 page(s) (zip deflate encoded)
```

### Test 4: Network Connectivity
```bash
podman exec homelab-test-client-docconv ping -c 2 doc-converter
```
**Result:** 0% packet loss, round-trip <0.1ms. Service name DNS resolution works.

### Test 5: Resource Usage
```bash
podman stats --no-stream homelab-doc-converter
```
**Result:** 81.19MB RAM (0.66% of 12.25GB), minimal CPU when idle.

## Configuration Phase

### Key Configuration Decisions

1. **Polling interval:** 0.5s - frequent enough for responsive conversion but not wasteful
2. **File stability check:** 6 checks at 0.5s intervals, 15% size variance threshold
3. **Processing delay:** 1.0s between files to avoid LibreOffice overload
4. **Conversion timeout:** 120s per file (complex documents can be slow)
5. **Processed directory:** Separate from input to allow audit trail of what was converted

### Volume Strategy
- **input/** - Bind mount for user to drop files
- **output/** - Bind mount for user to retrieve PDFs
- **processed/** - Bind mount to track what was converted
- **logs/** - Bind mount for debugging

## Architecture Explanation

### Component Design

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   User      │────>│  /input/     │────>│  Watcher    │
│  drops file │     │  (bind mount)│     │  (Python)   │
└─────────────┘     └──────────────┘     └──────┬──────┘
                                                │
                                          File  │  Stable?
                                          found │  Yes
                                                ▼       │
                                         ┌──────────────┘
                                         │  LibreOffice
                                         │  headless
                                         └──────┬───────┘
                                                │
                                    ┌───────────┴───────────┐
                                    ▼                       ▼
                              ┌──────────┐          ┌──────────────┐
                              │ /output/ │          │ /processed/  │
                              │  (.pdf)  │          │  (original)  │
                              └──────────┘          └──────────────┘
```

### Why This Design?
- **Polling over inotify:** Simpler, doesn't require installing additional packages in the container. The `watchdog` package was already present but polling is sufficient for this use case.
- **Copy+delete over rename:** Cross-filesystem compatibility. Bind mounts appear as separate filesystems to the container.
- **Separate processed directory:** Allows users to review what was converted without cluttering the input directory.

## Design Decisions

### Why linuxserver/libreoffice over custom build?
- Pre-configured, well-maintained image
- Already has Python, LibreOffice, and dependencies
- Saves build time and complexity
- Tradeoff: ~80MB RAM overhead from the desktop environment (Selkies)

### Why Python over bash for the watcher?
- Better file stability detection (size comparison)
- Cleaner error handling and logging
- Easier to extend with features (format filtering, notifications)
- The `watchdog` package was already available

### Why not use inotify directly?
- Polling is simpler and sufficient for this use case
- Avoids edge cases with inotify (file deletion during watch, etc.)
- 0.5s polling interval is responsive enough for document conversion

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references
- [x] Ports are > 1024 (N/A - no exposed ports, internal only)
- [x] Test client container included
- [x] Healthcheck port matches service config (N/A - no HTTP service)
- [x] Volumes use hybrid strategy (all bind mounts for simplicity)
- [x] Network name follows homelab-* pattern (homelab-docconv-network)
- [x] README includes setup instructions
- [x] Verification commands documented
- [x] Expected output samples provided
```

## Resource Usage

| Metric | Actual | Budget | Notes |
|--------|--------|--------|-------|
| RAM | 81MB | ~400MB | Well within budget |
| Storage | ~400MB image | ~200MB + output | Image is larger due to desktop env |
| CPU | <1% idle | - | Spikes during conversion only |
| Network | Internal only | - | No external connections needed |

## Lessons Learned

### What Worked
1. **linuxserver/libreoffice image** - Works great for headless conversion despite the desktop environment overhead
2. **Polling-based watcher** - Simple and reliable for this use case
3. **Copy+delete pattern** - Solves the cross-filesystem rename issue
4. **Separate processed directory** - Clean separation of concerns

### What Didn't Work
1. **os.rename() for cross-filesystem moves** - Classic pitfall with bind mounts. Always use shutil.copy2() + os.remove() when dealing with separate mount points.
2. **Over-aggressive log filtering** - Initial log inspection was hampered by trying to filter out the Selkies desktop logs. Should have grepped more specifically from the start.

### What Would Do Differently
1. **Build a custom image** - Instead of linuxserver/libreoffice, build from `python:3.12-slim` and install only `libreoffice-core` to reduce RAM usage. The desktop environment is unnecessary for headless conversion.
2. **Add format filtering** - Could add a config file to specify which formats to process (e.g., skip images, only process documents).
3. **Add retry logic** - If conversion fails, move the file to a `failed/` directory instead of leaving it in input for re-processing.

## Common Questions

### Q: Why does the image use so much RAM (~80MB) when it's just converting documents?
A: The linuxserver/libreoffice image includes a Wayland desktop environment (Selkies) for remote desktop access. This runs even during headless conversion. A custom image without the desktop would use significantly less RAM.

### Q: Can I process files in subdirectories?
A: Not currently. The watcher only monitors the top-level input directory. Adding recursive watching would require using the `watchdog` library's `ObservedWatch` with `recursive=True`.

### Q: What happens if LibreOffice crashes during conversion?
A: The subprocess timeout (120s) will catch hung conversions. The file would remain in the input directory and be re-attempted on the next poll cycle. A `failed/` directory would be useful for tracking these cases.

### Q: Can I use this with actual Word documents (.doc)?
A: LibreOffice can convert .doc files, but older binary .doc format support may be limited depending on the LibreOffice version. .docx (XML-based) is more reliably supported.

### Q: How do I handle large documents with many pages?
A: The conversion timeout is 120 seconds. Complex documents with many images or pages may take longer. Monitor logs for timeout messages.

## What Didn't Work (Dead Ends)

1. **os.rename() for file moves** - Failed with "Cross-device link" error. Root cause: bind mounts are separate filesystems from the container's perspective. Switched to shutil.copy2() + os.remove().

2. **Custom Dockerfile from Ubuntu** - Considered building from `ubuntu:24.04` and installing LibreOffice manually. Rejected because:
   - More complex setup
   - linuxserver/libreoffice is well-maintained
   - Tradeoff of ~80MB RAM for simplicity is acceptable

3. **inotify-based watching** - Considered using Linux inotify directly via the `watchdog` library. Rejected because:
    - Polling is simpler and sufficient
    - Avoids edge cases (file deletion during watch, etc.)
    - `watchdog` library adds complexity without clear benefit for this use case

## Simplification Cleanup (April 25, 2026)

### Changes Applied
- **Phase 1**: Removed `version: '3.8'`; pinned alpine test-client to `3.21`
- **Phase 2**: Standardized test-client container name from `homelab-test-client-docconv` → `homelab-doc-converter-test`
- **Phase 3**: Skipped (no secrets)
- **Phase 4**: Network key renamed from `experiment-network` → `homelab-docconv-network`; dropped redundant `name:` field
- **Phase 5**: Skipped (all bind mounts, no named volumes)
- **Phase 6**: Skipped (no exposed ports)
- **Phase 8**: Updated README with Overview, Quick Start, Services table, Testing, Troubleshooting, and Cleanup sections

### Verification
- Build: Cached, successful
- Both containers started, ping test passed (0% packet loss)
- Conversion test: `test-file.txt` → `test-file.pdf` (14206 bytes), source moved to `processed/`
- All tests passed, cleaned up with `podman compose down -v`
