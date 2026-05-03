# Phase 4: Reactive Image Processing Pipeline

**Experiment:** 9A (Image Processor) + 9C (Metadata Extractor) — combined  
**Status:** Deployed

---

## How It Works

This experiment demonstrates a **filesystem-driven reactive pattern** using inotify (via Python's `watchdog` library) to monitor a directory for new images. When an image is dropped into the input directory, the watcher automatically:

1. **Resizes** the image to three scale factors (50%, 25%, 12.5%)
2. **Extracts metadata** (dimensions, format, EXIF tags, file size) and stores it in MongoDB

### Architecture

```
Experiment directory         Container network (homelab-imageproc-net)
───────────────────          ──────────────────────────────────────
input/               ────▶   image-watcher (Python 3.11)
   (drop images          │
    here)                  │ MongoDB URI: mongodb://mongodb:27017
                           │
output/              ◀──── ├──▶ mongodb:27017 (mongo:7.0)
   (resized variants)      │     (mongo_data volume)
                           │
                      ┌────┴────┐
                      │test-client│
                      │ (alpine)  │
                      └───────────┘
```

**Data flow:**
1. User drops image into `input/` directory
2. `watchdog` detects the `on_created` event
3. Watcher debounces (1s delay) to ensure file write completes
4. Watcher computes file hash to avoid reprocessing duplicates
5. Watcher resizes image to 3 scales → writes to `output/`
6. Watcher extracts metadata → inserts into MongoDB
7. MongoDB stores the document with dynamic EXIF fields

---

## Quick Start

### Start the experiment

```bash
cd ~/homelab/reactive-processing/image-processor
podman compose up -d --build
```

### Check all containers are running

```bash
podman ps --filter network=homelab-imageproc-net
```

**Expected output:** 3 containers (image-watcher, homelab-mongo-reactive, homelab-image-processor-test)

### Check watcher logs

```bash
podman logs homelab-image-watcher
```

**Expected startup output:**
```
============================================================
Image Processor Watcher
============================================================
  Input directory:  /input
  Output directory: /output
  Resize scales:    [0.5, 0.25, 0.125]
  MongoDB:          mongodb://mongodb:27017
  DB/Collection:    image_metadata/images
  Supported formats: .avif, .bmp, .gif, .ico, .jpg, .jpeg, .png, .tiff, .tif, .webp
============================================================
MongoDB connection: OK

Watching for new images in /input...
Drop images into the input directory to process them.
```

---

## Testing

### Test with an image

```bash
# Copy an image to the input directory
cp /path/to/your-image.jpg input/

# Wait ~3 seconds for processing

# Check output directory
ls -la output/
```

**Expected output:**
```
<your-image>_half.jpg
<your-image>_quarter.jpg
<your-image>_eighth.jpg
```

### Verify watcher processed it

```bash
podman logs homelab-image-watcher
```

**Expected output:**
```
[PROCESSING] <your-image>.jpg
  Resized: <your-image>_half.jpg (1024x768 -> 512x384)
  Resized: <your-image>_quarter.jpg (1024x768 -> 256x192)
  Resized: <your-image>_eighth.jpg (1024x768 -> 128x96)
  Metadata stored in MongoDB (doc id: 68...)
    dimensions: (1024, 768)
    format: JPEG
    mode: RGB
    file_size_bytes: 115052
    exif tags: N fields extracted
```

### Query MongoDB for metadata

```bash
podman exec homelab-mongo-reactive mongosh image_metadata --eval "db.images.find().pretty()"
```

**Expected output:** A document with filename, dimensions, format, mode, file_size_bytes, and optional exif fields.

### Test container networking

```bash
podman exec homelab-image-processor-test sh -c '
  apk add --no-cache curl > /dev/null 2>&1
  curl -s http://mongodb:27017 | head -c 50
'
```

### Test with multiple image types

```bash
cp /path/to/image1.jpg input/
cp /path/to/image2.png input/
```

---

## Configuration

All settings are via environment variables in `docker-compose.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `MONGO_URI` | `mongodb://mongodb:27017` | MongoDB connection string |
| `MONGO_DB` | `image_metadata` | MongoDB database name |
| `MONGO_COLLECTION` | `images` | MongoDB collection name |
| `INPUT_DIR` | `/input` | Watched directory (bind-mounted from `./input/`) |
| `OUTPUT_DIR` | `/output` | Output directory for resized images (bind-mounted from `./output/`) |
| `RESIZE_SCALES` | `0.5,0.25,0.125` | Comma-separated scale factors |

---

## MongoDB Schema

MongoDB is schema-less. Each document contains whatever metadata the image provides:

**JPEG with EXIF:**
```json
{
  "_id": ObjectId("..."),
  "filename": "vacation.jpg",
  "file_size_bytes": 2458630,
  "dimensions": [4032, 3024],
  "mode": "RGB",
  "format": "JPEG",
  "processed_at": "2026-04-19T14:32:00+00:00",
  "exif": {
    "Make": "Apple",
    "Model": "iPhone 14 Pro",
    "DateTimeOriginal": "2026:03:15 10:23:45"
  }
}
```

**PNG without EXIF:**
```json
{
  "_id": ObjectId("..."),
  "filename": "screenshot.png",
  "file_size_bytes": 102400,
  "dimensions": [1920, 1080],
  "mode": "RGBA",
  "format": "PNG",
  "processed_at": "2026-04-19T14:35:00+00:00"
}
```

### Useful MongoDB queries

```bash
# All images
podman exec homelab-mongo-reactive mongosh image_metadata --eval "db.images.find().pretty()"

# Count by format
podman exec homelab-mongo-reactive mongosh image_metadata --eval "db.images.aggregate([{ \$group: { _id: \"\$format\", count: { \$sum: 1 } } }]).pretty()"

# Images above a certain size
podman exec homelab-mongo-reactive mongosh image_metadata --eval "db.images.find({ file_size_bytes: { \$gt: 1000000 } }).pretty()"
```

---

## Common Pitfalls

### Watchdog fires before file write completes
**Symptom:** Watcher tries to open a partially written file.  
**Mitigation:** 1-second delay on file event before processing.

### EXIF tag names not resolved for non-standard formats
**Symptom:** EXIF tags stored as numeric IDs (e.g., `274`, `282`) instead of names (e.g., `Orientation`, `XResolution`).  
**Cause:** `PIL.ExifTags.TAGS.get(tag_id)` returns `None` for AVIF-specific tags. The fallback `str(tag_id)` is used.  
**Impact:** Data is stored correctly, just less human-readable. Tags 274/282/283/296/531/34665 correspond to standard EXIF fields.

### MongoDB connection fails on first file event
**Symptom:** First image processed but metadata not stored. Watcher logs show `MongoDB error: No servers found yet, Timeout: 5.0s`.  
**Cause:** Watcher connects to MongoDB on startup; the 5-second pymongo timeout may expire before MongoDB is fully ready for application connections (even after healthcheck passes).  
**Mitigation:** Watcher retries connection on each subsequent file event. Subsequent files will have metadata stored successfully. To fix permanently, increase `serverSelectionTimeoutMS` in `watcher.py` or add a startup wait loop.

### Duplicate processing
**Symptom:** Same file processed multiple times.  
**Mitigation:** MD5 hash deduplication in memory. Note: hash set is cleared on container restart.

### Port conflict
**Symptom:** MongoDB port 27021 already in use.  
**Check:** `ss -tlnp | grep 27021` before starting.

---

## Stop the Experiment

```bash
# Stop all services (keep data)
podman compose down

# Stop and remove volumes (WARNING: deletes MongoDB data)
podman compose down -v
```

---

## Verification Checklist

- [x] Compose file uses full image references (`docker.io/library/...`)
- [x] Ports are > 1024 (27018:27017)
- [x] Test client container included
- [x] MongoDB healthcheck configured
- [x] Volumes use hybrid strategy (named `imageprocessor_mongodb_data` + bind mounts)
- [x] Network name follows `homelab-*` pattern (`homelab-imageproc-net`)
- [x] Verification commands documented
- [x] Expected output samples provided

---

## Resource Usage

| Service | RAM | CPU | Storage |
|---------|-----|-----|---------|
| image-watcher | ~60-80MB | 5-10% (burst on file drop) | ~50MB image |
| mongodb | ~150-200MB | 5-10% | ~200MB + metadata docs |
| test-client | ~5MB | <1% | Negligible |
| **Total** | **~215-285MB** | **~15-20%** | **~255MB** |

---

## Files

```
reactive-processing/image-processor/
├── docker-compose.yml      # 3 services: watcher, mongodb, test-client
├── Dockerfile              # Python 3.11 + watchdog + Pillow + pymongo
├── watcher.py              # Combined resize + metadata extraction logic
├── samples/                # Sample images for testing
├── input/                  # Drop images here for processing
├── output/                 # Processed/resized images (generated)
├── README.md               # This file
└── experiment-timeline.md  # Lab notebook
```

---

*Deployed: April 19, 2026*
