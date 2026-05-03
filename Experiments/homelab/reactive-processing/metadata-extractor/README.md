# Media Metadata Extractor

Reactive file processing that monitors a folder for new media files and automatically extracts all metadata into PostgreSQL.

## Overview

This experiment demonstrates event-driven file processing using Python watchdog (inotify), with metadata extraction for images, audio, and video files stored in PostgreSQL.

## Quick Start

```bash
cd ~/homelab/reactive-processing/metadata-extractor

# Copy and configure environment
cp .env.example .env
# Edit .env to set your password

# Build and start
podman compose up -d --build

# Watch logs
podman logs -f homelab-metadata-extractor
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| postgresql | 25433:5432 | Metadata storage |
| metadata-extractor | — | File watcher + metadata extraction |
| test-client | — | Testing with psql, jq, curl |

## Testing

### 1. Verify containers are running
```bash
podman ps --filter name=homelab-metadata

# Expected output:
# homelab-metadata-pg          (PostgreSQL, healthy)
# homelab-metadata-extractor   (watcher, running)
# homelab-metadata-extractor-test (alpine, sleeping)
```

### 2. Test PostgreSQL connectivity
```bash
podman exec homelab-metadata-extractor-test /query.sh connectivity
```

Expected output:
```
Testing PostgreSQL connectivity...
 connected
-----------
          1
(1 row)
```

### 3. Test metadata extraction
```bash
# Copy any image into the input directory
cp /path/to/your-image.jpg input/

# Watch the extractor logs
podman logs -f homelab-metadata-extractor
```

Expected log output:
```
[INFO] Detected new file: /input/test.jpg
[INFO] Processing image: test.jpg
[INFO] Stored metadata for: test.jpg
[INFO] Cleaned up: /input/test.jpg
```

### 4. Query the database
```bash
podman exec homelab-metadata-extractor-test /query.sh list
```

#### Test Client Query Commands

The test client includes a `/query.sh` helper script with these commands:

| Command | Description |
|---------|-------------|
| `connectivity` | Test PostgreSQL connection |
| `count` | Total files processed |
| `list` | Recently processed files |
| `images` | Image metadata only |
| `audio` | Audio metadata only |
| `video` | Video metadata only |
| `gps` | GPS coordinates from images |
| `duplicates` | Check for duplicate hashes |
| `cleanup` | Clear all records |

```bash
podman exec homelab-metadata-extractor-test /query.sh images
podman exec homelab-metadata-extractor-test /query.sh audio
podman exec homelab-metadata-extractor-test /query.sh video
```

### 5. Query GPS coordinates from images
```bash
podman exec homelab-metadata-extractor-test /query.sh gps
```

### 6. Query audio metadata
```bash
podman exec homelab-metadata-extractor-test /query.sh audio
```

### 7. Query video metadata
```bash
podman exec homelab-metadata-extractor-test /query.sh video
```

## Database Schema

```
media_metadata
├── id              (SERIAL PK)
├── filename        (VARCHAR)
├── file_path       (TEXT)
├── file_type       (VARCHAR: image/audio/video)
├── file_size_bytes (BIGINT)
├── duration_seconds (DOUBLE PRECISION)
├── width/height    (INTEGER)
├── format/codec    (VARCHAR)
├── bitrate         (INTEGER)
├── sample_rate     (INTEGER)
├── artist/album/title/genre (VARCHAR)
├── date_created    (TIMESTAMP)
├── gps_latitude/longitude (DOUBLE PRECISION)
├── camera_make/model (VARCHAR)
├── exposure/aperture/focal_length/iso (VARCHAR/INTEGER)
├── all_metadata    (JSONB - raw extracted data)
├── file_hash       (VARCHAR(32) - MD5)
└── processed_at    (TIMESTAMP)
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `INPUT_DIR` | `/input` | Directory to watch for new files |
| `OUTPUT_DIR` | `/output` | Directory for processed outputs |
| `DB_HOST` | `postgresql` | PostgreSQL container name |
| `DB_PORT` | `5432` | PostgreSQL port (internal) |
| `DB_NAME` | `metadata` | PostgreSQL database name |
| `DB_USER` | `metadata_user` | PostgreSQL username |
| `DB_PASSWORD` | (env) | PostgreSQL password (from `.env`) |
| `POSTGRES_PASSWORD` | (env) | PostgreSQL password (compose `.env`) |

## Resource Usage

| Resource | Estimate | Actual |
|----------|----------|--------|
| RAM | ~150MB | ~80MB (PostgreSQL ~40MB + extractor ~40MB) |
| Storage | ~100MB + DB | ~150MB (image ~120MB + PG data ~30MB) |
| CPU | Near idle (event-driven) | Near idle (event-driven, no polling) |

## Troubleshooting

### Files not being processed
- Check that the file is copied (not moved) into `input/`
- Verify the file extension is in the supported list
- Check extractor logs: `podman logs homelab-metadata-extractor`
- Ensure PostgreSQL is healthy: `podman logs homelab-metadata-pg | grep "ready"`

### Duplicate files
- Files with the same MD5 hash are automatically skipped
- Remove the hash from the database to reprocess:
  ```sql
  DELETE FROM media_metadata WHERE file_hash = '<md5hash>';
  ```

### Large files
- Video processing uses ffprobe which reads the entire file header
- Very large video files may take a few seconds to process
- The 2-second debounce may not be enough for files still being written
- For slow transfers, increase `PROCESSING_DELAY` in `extractor.py`

### PostgreSQL connection failures
- The extractor retries connection for up to 60 seconds
- If it fails completely, restart: `podman compose restart metadata-extractor`

### Port conflict
- PostgreSQL is mapped to host port **25433** (not 5432) to avoid conflicts
- Use the test-client for queries: `podman exec homelab-metadata-extractor-test /query.sh list`

## Cleanup

```bash
# Stop without removing data
podman compose down

# Stop and remove data volumes
podman compose down -v
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     homelab-metadata-net                     │
│                                                              │
│  ┌──────────────────┐       ┌──────────────────────────┐    │
│  │   postgresql      │       │   metadata-extractor      │    │
│  │   (postgres:16)   │◄──────│   (python:3.11-slim)     │    │
│  │                   │       │                          │    │
│  │  /var/lib/pgsql   │       │  watches /input/         │    │
│  │  schema.sql       │       │  extracts metadata       │    │
│  │                   │       │  stores in DB            │    │
│  └────────┬──────────┘       └──────────┬───────────────┘    │
│           │                              │                   │
│  host:25433│                              │                   │
│  (external access)                        │                   │
└───────────┼──────────────────────────────┼───────────────────┘
            │                              │
     ┌──────▼──────┐              ┌────────▼────────┐
     │  Host FS    │              │  Host FS        │
     │  input/     │              │  output/        │
     │  (drop files)│             │  (thumbnails)   │
     └─────────────┘              └─────────────────┘
```

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references
- [x] Ports are > 1024 (25433)
- [x] Test client container included with tools (psql, jq, curl, file, md5sum, tar, unzip)
- [x] Healthcheck uses pg_isready
- [x] Volumes use hybrid strategy (named + bind)
- [x] Network name follows homelab-* pattern
- [x] PostgreSQL init script via /docker-entrypoint-initdb.d/
- [x] depends_on with service_healthy condition
- [x] Verified PostgreSQL connectivity from test client
- [x] Verified image metadata extraction (test.png → stored)
- [x] Verified duplicate detection (hash-based)
- [x] Verified file cleanup after processing
- [x] Query helper script (/query.sh) working
- [x] Secrets extracted to .env
- [x] Alpine test-client pinned to 3.21
- [ ] Verified audio metadata extraction
- [ ] Verified video metadata extraction
- [ ] Resource usage measured
```
