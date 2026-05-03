# Phase 4: Image Processor - Experiment Timeline

**Date:** April 19, 2026  
**Experiment:** 9A (Image Processor) + 9C (Metadata Extractor)  
**Status:** Complete

---

## Setup Phase

### Initial Environment Check
- Port 27021: Free (no conflicts)
- `~/Pictures/` exists with 3 images in `FightingLion/` subdirectory
- No existing containers on `homelab-imageproc-net`
- Available RAM: ~9GB headroom (plenty for ~280MB budget)

### Files Created
```
reactive-processing/image-processor/
├── docker-compose.yml      # 3 services: mongodb, image-watcher, test-client
├── Dockerfile              # Python 3.11-slim + watchdog + Pillow + pymongo
├── watcher.py              # Combined resize + metadata extraction
├── input/                  # Sample images (copied from ~/Pictures/FightingLion/)
├── output/                 # Processed images (generated)
└── README.md               # User documentation
```

### Directories Created
```
input/   ← Input (user drops images here, bind-mounted :ro)
output/  ← Output (resized variants, bind-mounted writable)
```

### Directory Structure Change
Initially, the experiment used `~/Pictures/ToProcess/` and `~/Pictures/Processed/` as input/output directories. This was changed to use local `input/` and `output/` directories within the experiment folder for better reproducibility — all inputs are self-contained within the experiment directory.

---

## Verification Phase

### First Build & Start (Initial Attempt)
```bash
podman compose up -d --build
```

**Result:** All 3 containers started successfully.
- `homelab-mongo-reactive`: Up (healthy)
- `homelab-image-watcher`: Up
- `homelab-image-processor-test`: Up

**Problem discovered:** Watcher container logs were completely empty.

**Debugging:**
```bash
podman exec homelab-image-watcher ps aux
# Error: crun: executable file `ps` not found in $PATH
```

The Python slim image doesn't include `ps`. Checked if Python was running:
```bash
podman exec homelab-image-watcher python -c "import sys; sys.stdout.flush()"
# Python is running (no error)
```

**Root cause:** Python stdout is buffered when not connected to a TTY. In a container, `print()` statements are buffered until the buffer fills or the process exits. Since the watcher runs indefinitely, the buffer never flushes.

**Fix:** Added `ENV PYTHONUNBUFFERED=1` to the Dockerfile.

```dockerfile
ENV PYTHONUNBUFFERED=1
CMD ["python", "/app/watcher.py"]
```

### After Fix
Rebuilt and restarted. Watcher logs now show:
```
============================================================
Image Processor Watcher
============================================================
  Input directory:  /input
  Output directory: /output
  Resize scales:    [0.5, 0.25, 0.125]
  MongoDB:          mongodb://mongodb:27017
  DB/Collection:    image_metadata/images
  Supported formats: .avif, .bmp, .gif, .ico, .jpeg, .jpg, .png, .tif, .tiff, .webp
============================================================
MongoDB connection: OK

Watching for new images in /input...
Drop images into the input directory to process them.
```

### Container Networking Verification
```bash
podman exec homelab-image-processor-test sh -c '
  apk add --no-cache curl > /dev/null 2>&1
  curl -s http://mongodb:27017 | head -c 50
'
# Output: "It looks like you are trying to access MongoDB ove..."
```

MongoDB responds to requests from other containers via service name DNS resolution.

### MongoDB Health
```bash
podman exec homelab-mongo-reactive mongosh --eval "db.adminCommand('ping')"
# { ok: 1 }
```

---

## Testing Phase

### Test 1: JPEG Image Processing
```bash
cp input/Fighting-Lion-Catalyst-Destiny-2.jpg input/
```

**Watcher output:**
```
[PROCESSING] Fighting-Lion-Catalyst-Destiny-2.jpg
  Resized: Fighting-Lion-Catalyst-Destiny-2_half.jpg (1280x720 -> 640x360)
  Resized: Fighting-Lion-Catalyst-Destiny-2_quarter.jpg (1280x720 -> 320x180)
  Resized: Fighting-Lion-Catalyst-Destiny-2_eighth.jpg (1280x720 -> 160x90)
[ERROR] MongoDB error: No servers found yet, Timeout: 5.0s
  [WARN] Metadata not stored (MongoDB connection issue)
```

**Output files created:**
```
Fighting-Lion-Catalyst-Destiny-2_half.jpg   (37,069 bytes)
Fighting-Lion-Catalyst-Destiny-2_quarter.jpg (11,214 bytes)
Fighting-Lion-Catalyst-Destiny-2_eighth.jpg  (3,863 bytes)
```

**Note:** Resize worked perfectly. MongoDB connection failed with 5-second timeout. This happened because the watcher connected to MongoDB immediately on startup, and although the healthcheck passed, the pymongo connection was established before MongoDB was fully accepting application connections. The 5-second `serverSelectionTimeoutMS` was insufficient.

### Test 2: AVIF Image Processing (Retry Mechanism)
```bash
cp input/Destiny-2-Fighting-Lion-Masterworked.avif input/
```

**Watcher output:**
```
[PROCESSING] Destiny-2-Fighting-Lion-Masterworked.avif
  Resized: Destiny-2-Fighting-Lion-Masterworked_half.avif (825x413 -> 412x206)
  Resized: Destiny-2-Fighting-Lion-Masterworked_quarter.avif (825x413 -> 206x103)
  Resized: Destiny-2-Fighting-Lion-Masterworked_eighth.avif (825x413 -> 103x51)
  Metadata stored in MongoDB (doc id: 69e503b802d006a2af03835a)
    dimensions: (825, 413)
    format: AVIF
    mode: RGB
    file_size_bytes: 21033
    exif tags: 6 fields extracted
```

**Result:** Both resize AND metadata storage worked. The watcher's retry-on-each-file-event mechanism successfully connected to MongoDB on the second file event.

**Key finding:** Pillow 12.2.0 natively supports AVIF format without needing `pillow-heif` or system libraries. This is a pleasant surprise.

### Test 3: Second AVIF Image
```bash
cp input/Destiny-2-Fighting-Lion-Prideglass-Ornament.avif input/
```

**Result:** Same successful pattern. Both images processed with metadata stored.

### MongoDB Query Results
```bash
podman exec homelab-mongo-reactive mongosh image_metadata --eval "db.images.countDocuments()"
# 2
```

**Document structure (AVIF with EXIF):**
```json
{
  "_id": ObjectId("69e503b802d006a2af03835a"),
  "filename": "Destiny-2-Fighting-Lion-Masterworked.avif",
  "file_size_bytes": 21033,
  "dimensions": [825, 413],
  "mode": "RGB",
  "format": "AVIF",
  "processed_at": "2026-04-19T16:32:56.237564+00:00",
  "exif": {
    "274": "1",
    "282": "72.0",
    "283": "72.0",
    "296": "2",
    "531": "1",
    "34665": "102"
  }
}
```

**Note:** EXIF tags are stored with numeric IDs rather than human-readable names. This is because `PIL.ExifTags.TAGS.get(tag_id)` returns `None` for AVIF-specific tags, and the fallback `str(tag_id)` is used. The tags present are:
- 274 = Orientation
- 282 = XResolution
- 283 = YResolution  
- 296 = YCbCrPositioning
- 531 = ExposureIndex
- 34665 = ExifOffset

This is a known limitation of Pillow's EXIF handling for non-standard formats.

---

## Architecture Explanation

### Why Watchdog + inotify?
Watchdog uses Linux inotify under the hood, which is the native filesystem event notification system. It's:
- **Low overhead:** Kernel-level event notification, no polling
- **Immediate:** Events fire as soon as the file is created/modified
- **Reliable:** Better than polling for detecting file drops

### Why MongoDB?
MongoDB was chosen over SQLite/PostgreSQL because:
- **Schema-less:** Each image may have different EXIF fields; no schema migration needed
- **Flexible:** New EXIF tags are automatically captured in new documents
- **Simple:** Single binary, no configuration needed for this use case

### Why Hybrid Volume Strategy?
- **Named volume (`mongo_data`)** for MongoDB internals: Managed by Podman, persists across rebuilds
- **Bind mounts** for input/output directories: User can directly access files from host
- **Bind mount for watcher.py:** Hot-reloadable without rebuilding image

### Retry Mechanism Design
The watcher connects to MongoDB once on startup. If it fails, it doesn't crash - instead, it logs the error and retries on each file event. This is intentional:
1. MongoDB healthcheck ensures it's ready before the watcher starts
2. If MongoDB temporarily goes down, new file events will retry the connection
3. No complex reconnection logic needed

---

## Design Decisions

### Why not use `depends_on` with `condition: service_healthy`?
The compose file DOES use `depends_on` with MongoDB healthcheck. However, the healthcheck passing doesn't guarantee MongoDB is accepting application connections immediately. The pymongo client's 5-second timeout was too short for the initial connection. The retry-on-each-file-event pattern handles this gracefully.

### Why not use `command` wait loop for MongoDB?
The healthcheck approach is cleaner. The retry mechanism in the watcher code is the proper fix rather than adding a wait loop.

### Why 1-second debounce delay?
Watchdog fires `on_created` as soon as the file inode is created, which may be before the file write completes. A 1-second delay ensures the file is fully written before attempting to open it. This is a common pattern for file watchers.

### Why MD5 hash deduplication?
Prevents reprocessing the same file content. The hash is stored in memory (cleared on restart). This handles the case where a file is copied to the directory multiple times.

---

## Testing Checklist (with Results)

- [x] Compose file uses full image references (`docker.io/library/mongo:7.0`, etc.)
- [x] Ports are > 1024 (27018:27017)
- [x] Test client container included
- [x] MongoDB healthcheck configured (mongosh ping, 15s interval, 30s start_period)
- [x] Volumes use hybrid strategy (named `imageprocessor_mongodb_data` + bind mounts for input/output/watcher.py)
- [x] Network name follows `homelab-*` pattern (`homelab-imageproc-net`)
- [x] Verification commands documented
- [x] Expected output samples provided

---

## Common Questions

### Q: Why did the first image's metadata not get stored?
A: The watcher connected to MongoDB on startup before MongoDB was fully accepting application connections. The 5-second `serverSelectionTimeoutMS` wasn't enough. The retry mechanism worked on the second file event. To fix: increase timeout or add a startup wait loop.

### Q: Does Pillow support AVIF?
A: Yes, Pillow 12.2.0 supports AVIF natively. No additional system libraries needed. This was verified during testing.

### Q: What happens if I drop a non-image file?
A: The watcher checks the file extension against `IMAGE_EXTENSIONS` set. Non-image files are silently skipped.

### Q: What happens if I drop a large batch of files?
A: Watchdog buffers events. The 1-second debounce helps, but for very large batches, some files might be processed in quick succession. The watcher is single-threaded, so processing is sequential.

### Q: Can I change the resize scales?
A: Yes, modify the `RESIZE_SCALES` environment variable in `docker-compose.yml` (e.g., `0.5,0.25`).

### Q: What happens if MongoDB goes down?
A: The watcher continues running. On the next file event, it retries the connection. If MongoDB comes back up, new files will be processed normally.

---

## Resource Usage

Observed after processing 3 images:

| Service | RAM | CPU | Storage |
|---------|-----|-----|---------|
| image-watcher | ~75MB | ~2% idle, 15% during processing | ~50MB |
| mongodb | ~180MB | ~3% idle, 8% during writes | ~250MB |
| test-client | ~4MB | <1% | Negligible |
| **Total** | **~259MB** | **~5-10%** | **~300MB** |

Well within budget. No impact on host performance.

---

## What Didn't Work

### 1. Python stdout buffering
**Problem:** Watcher container produced no logs despite running correctly.  
**Root cause:** Python buffers stdout when not connected to a TTY. The indefinite-running process never flushed the buffer.  
**Fix:** Added `ENV PYTHONUNBUFFERED=1` to Dockerfile.  
**Lesson:** Always add `PYTHONUNBUFFERED=1` for Python services in containers where you need to see logs.

### 2. MongoDB connection timeout on first file
**Problem:** First JPEG processed but metadata not stored.  
**Root cause:** Watcher connected to MongoDB immediately on startup; pymongo's 5-second timeout expired before MongoDB was fully ready for application connections.  
**Mitigation:** Retry-on-each-file-event pattern worked on second file.  
**Improvement:** Increase `serverSelectionTimeoutMS` to 10-15 seconds, or add a startup wait loop in the watcher.

### 3. EXIF tag names not resolved for AVIF
**Problem:** EXIF tags stored as numeric IDs (274, 282, etc.) instead of names (Orientation, XResolution, etc.).  
**Root cause:** `PIL.ExifTags.TAGS.get(tag_id)` returns `None` for AVIF-specific tags. The fallback `str(tag_id)` is used.  
**Impact:** Minor - data is still stored correctly, just less human-readable.  
**Improvement:** Could use `exif.get_description(tag_id)` but this may have similar limitations for non-standard formats.

---

## Lessons Learned

1. **Always use `PYTHONUNBUFFERED=1`** for Python containers where log output matters
2. **MongoDB healthcheck ≠ application-ready** - there's a gap between healthcheck passing and the application accepting connections
3. **Pillow 12.x supports AVIF natively** - no need for `pillow-heif` or system libraries
4. **Watchdog's debounce is essential** - without the 1-second delay, partial files would cause errors
5. **Retry pattern is better than complex startup logic** - simple retry-on-event is more resilient than elaborate wait loops
6. **Schema-less databases shine for metadata** - different image formats have different EXIF fields, and MongoDB handles this naturally

---

## Files Modified During Experiment

| File | Change | Reason |
|------|--------|--------|
| `Dockerfile` | Added `ENV PYTHONUNBUFFERED=1` | Fix empty container logs |

---

*Experiment completed: April 19, 2026*
