# Experiment 9C: Media Metadata Extractor - Timeline

**Date:** April 20, 2026  
**Status:** Complete  
**Duration:** ~45 minutes (including debugging)

---

## Setup Phase

### Iteration 1: Initial Build and Start

**Command:** `podman compose up -d --build`

**Result:** All 3 containers started successfully.

**Containers:**
- `homelab-metadata-pg` (PostgreSQL 16 Alpine) - healthy
- `homelab-metadata-extractor` (Python 3.11-slim custom) - running
- `homelab-metadata-test-client` (Alpine) - running

### Error 1: Schema File Not Found

**Error:**
```
FileNotFoundError: [Errno 2] No such file or directory: '/app/../schema.sql'
```

**Root Cause:** The `schema.sql` file was mounted into the PostgreSQL container via `/docker-entrypoint-initdb.d/`, but the extractor container couldn't access it. The path `/app/../schema.sql` resolves to `/schema.sql` which doesn't exist in the extractor container's filesystem.

**Resolution:** Added `COPY schema.sql /app/schema.sql` to the Dockerfile so the schema file is baked into the image alongside `extractor.py`.

**Lesson:** Files needed by the application container must be COPYed into the image, not just mounted into other containers.

---

### Error 2: Duplicate Index Error

**Error:**
```
psycopg2.errors.DuplicateTable: relation "idx_media_metadata_filename" already exists
```

**Root Cause:** The `schema.sql` was mounted into PostgreSQL's `/docker-entrypoint-initdb.d/` directory, so it ran on init and created the table + indexes. Then the extractor's `ensure_table()` function tried to run the same SQL again, causing a conflict on the `CREATE INDEX` statements.

**Resolution:** Changed all `CREATE INDEX` statements to `CREATE INDEX IF NOT EXISTS` to make the schema idempotent.

**Lesson:** When the same SQL runs both via PostgreSQL init scripts AND application code, use `IF NOT EXISTS` on all DDL statements.

---

### Error 3: KeyError 'duration_seconds'

**Error:**
```
[ERROR] Failed to process /input/test.png: 'duration_seconds'
```

**Root Cause:** The `metadata` dict initialized in `process_file()` didn't include `duration_seconds`. For images, `extract_image_metadata()` doesn't set this field (images don't have a duration). The SQL INSERT expected all columns to be present in the dict.

**Resolution:** Added `duration_seconds: None` to the initial metadata dict.

**Lesson:** Always initialize ALL SQL columns in the metadata dict, even if the specific file type won't populate them.

---

### Error 4: KeyError 'codec'

**Error:**
```
[ERROR] Failed to process /input/test2.png: 'codec'
```

**Root Cause:** Same issue as Error 3, but with a different missing key. The metadata dict was missing `codec`, `width`, `height`, `format`, `bitrate`, and many other fields expected by the SQL INSERT.

**Resolution:** Added ALL 24 SQL columns to the initial metadata dict initialization:
- `duration_seconds`, `width`, `height`, `format`, `codec`
- `bitrate`, `sample_rate`, `channel_layout`
- `artist`, `album`, `title`, `track_number`, `genre`
- `date_created`, `gps_latitude`, `gps_longitude`
- `camera_make`, `camera_model`, `exposure_time`, `aperture`
- `focal_length`, `iso`, `white_balance`, `software`

**Lesson:** When building a metadata dict that maps to a wide SQL table, initialize all columns at once rather than relying on type-specific extractors to fill them in.

---

## Verification Phase

### Test 1: PostgreSQL Connectivity

**Command:**
```bash
podman exec homelab-metadata-test-client sh -c \
  "PGPASSWORD=metadata_pass_123 psql -h postgresql -U metadata_user -d metadata -c 'SELECT 1'"
```

**Expected:** `1` returned in a column named `test`  
**Actual:** 
```
test 
------
    1
(1 row)
```

**Result:** PASS

---

### Test 2: Image Metadata Extraction

**Command:** Created a minimal 2x2 red PNG and copied to `input/`

**File:** `test3.png` (73 bytes, 2x2 pixels, red)

**Extractor Logs:**
```
[INFO] Detected new file: /input/test3.png
[INFO] Processing image: test3.png
[INFO] Generated thumbnail: /input/test3_thumb.png
[INFO] Cleaned up: /input/test3_thumb.png
[INFO] Stored metadata for: test3.png
[INFO] Cleaned up: /input/test3.png
```

**Database Query:**
```sql
SELECT id, filename, file_type, width, height, format, file_size_bytes 
FROM media_metadata ORDER BY id DESC LIMIT 1;
```

**Result:**
```
id | filename  | file_type | width | height | format | file_size_bytes 
----+-----------+-----------+-------+--------+--------+-----------------
  1 | test3.png | image     |     2 |      2 | PNG    |              73
```

**Result:** PASS - Image metadata correctly extracted and stored.

---

## Configuration Phase

### Architecture Decisions

1. **PostgreSQL as metadata store** (user decision from experiments.md Q3)
   - Uses existing PostgreSQL pattern from other experiments
   - Port mapped to 5433 (not 5432) to avoid conflicts
   - Schema created via init script + idempotent ensure_table()

2. **Watchdog library for file monitoring**
   - Uses inotify for efficient event-based detection
   - 2-second debounce to avoid processing partial writes
   - Single-threaded event handler (simple, no queue complexity)

3. **Pure Python libraries for extraction**
   - Pillow for image EXIF/metadata
   - mutagen for audio tags
   - ffprobe (via subprocess) for video metadata
   - Avoided exiftool binary to reduce image size

4. **Hybrid volume strategy**
   - Named volume `pg_data` for PostgreSQL internals
   - Bind mounts for `input/` and `output/` (host-accessible)

---

## Architecture Explanation

```
┌─────────────────────────────────────────────────────────────┐
│                     homelab-reactive-net                     │
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
│  host:5433 │                              │                   │
│  (external access)                         │                   │
└───────────┼──────────────────────────────┼───────────────────┘
            │                              │
     ┌──────▼──────┐              ┌────────▼────────┐
     │  Host FS    │              │  Host FS        │
     │  input/     │              │  output/        │
     │  (drop files)│             │  (thumbnails)   │
     └─────────────┘              └─────────────────┘
```

**Data Flow:**
1. User drops media file into `input/` directory on host
2. Watchdog detects `inotify` event (`on_created`/`on_modified`)
3. 2-second debounce check (skip if recently modified)
4. MD5 hash deduplication check against database
5. Extract metadata based on file type:
   - **Images:** Pillow → EXIF, dimensions, GPS, camera info
   - **Audio:** mutagen → tags, duration, bitrate, sample rate
   - **Video:** ffprobe → streams, format, codec, duration
6. Generate thumbnail for images (400x400 max, cleaned up after)
7. Store all metadata in PostgreSQL `media_metadata` table
8. Remove processed file from `input/`

---

## Design Decisions

### Why 5433 instead of 5432?
Port 5432 is the standard PostgreSQL port. Other experiments (like the PostgreSQL replication setup) use 5434/5435. Using 5433 avoids conflicts with any existing PostgreSQL instances while keeping it close to the standard port for easy recall.

### Why named volume for PG data + bind mounts for input/output?
Named volumes are managed by Podman and work reliably with rootless containers. Bind mounts for input/output give the user direct filesystem access to drop files and inspect results without needing to `podman exec` into containers.

### Why not use exiftool binary?
exiftool is the gold standard for metadata extraction but requires installing a Perl-based binary (~50MB+). Using Pillow (Python library) keeps the image smaller and avoids dependency issues. Pillow handles most common EXIF tags adequately.

### Why generate and immediately delete thumbnails?
Thumbnails are generated as a proof-of-concept for the image processing pipeline. They're cleaned up immediately since the primary goal is metadata storage, not image processing. This can be changed to persist thumbnails if needed.

---

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references
- [x] Ports are > 1024 (5433)
- [x] Test client container included
- [x] Healthcheck uses pg_isready
- [x] Volumes use hybrid strategy (named + bind)
- [x] Network name follows homelab-* pattern
- [x] PostgreSQL init script via /docker-entrypoint-initdb.d/
- [x] depends_on with service_healthy condition
- [x] Verified PostgreSQL connectivity from test client
- [x] Verified image metadata extraction (test3.png → stored)
- [ ] Verified audio metadata extraction (not tested)
- [ ] Verified video metadata extraction (not tested)
- [x] Verified duplicate detection (hash-based)
- [x] Verified file cleanup after processing
- [ ] Resource usage measured
```

---

## Common Questions

**Q: Why does the extractor keep restarting?**  
A: The extractor retries database connection for up to 60 seconds during startup. This is normal - PostgreSQL takes a few seconds to initialize. Once connected, it stays running.

**Q: Why are files being deleted after processing?**  
A: The extractor removes files after successful metadata extraction to prevent reprocessing. If you want to keep files, remove the `cleanup_file(filepath)` call at the end of `process_file()`.

**Q: How do I add more supported file types?**  
A: Add extensions to the sets at the top of `extractor.py`:
- `SUPPORTED_IMAGE_EXTENSIONS`
- `SUPPORTED_AUDIO_EXTENSIONS`
- `SUPPORTED_VIDEO_EXTENSIONS`

**Q: Can I query the database from the host?**  
A: Yes, using `psql -h 127.0.0.1 -p 5433 -U metadata_user -d metadata`. You'll need to install `psql` on the host and set the password (`metadata_pass_123`).

**Q: What happens if PostgreSQL goes down?**  
A: The extractor will continue running but won't process new files. When PostgreSQL comes back up, the extractor will reconnect on the next file event.

---

## Resource Usage

| Resource | Budget | Actual (estimated) |
|----------|--------|-------------------|
| RAM | ~150MB | ~80MB (PostgreSQL ~40MB + extractor ~40MB) |
| Storage | ~100MB | ~150MB (image ~120MB + PG data ~30MB) |
| CPU | Near idle | Near idle (event-driven, no polling) |

---

## What Didn't Work

1. **Trying to read schema.sql via relative path** - The path `/app/../schema.sql` doesn't resolve correctly in the container. Fixed by COPYing into the image.

2. **Assuming extractors would fill all SQL columns** - Each type-specific extractor (image/audio/video) only sets the fields relevant to that type. The initial metadata dict must include ALL columns with default values.

3. **Not making schema idempotent** - Running CREATE INDEX without IF NOT EXISTS caused failures when the init script and application code both tried to create the same indexes.

---

## Lessons Learned

1. **COPY files needed by the app into the image** - Don't assume mounted files in one container are available in another.

2. **Initialize ALL SQL columns in dicts** - When building a dict that maps to a wide table, include every column with a default value, not just the ones the current file type will populate.

3. **Make DDL idempotent** - Use `IF NOT EXISTS` on CREATE statements when the same SQL might run multiple times.

4. **PostgreSQL init scripts run before healthcheck** - The schema.sql mounted in `/docker-entrypoint-initdb.d/` runs during PostgreSQL initialization, which happens before the healthcheck passes. This is why the extractor needs to handle "table already exists" gracefully.

5. **Watchdog debounce is essential** - Without the 2-second debounce, files being written via SFTP or other transfers would trigger processing on partial files.

---

*Experiment completed successfully on April 20, 2026.*

---

## Simplification Cleanup (April 25, 2026)

### Changes Applied

| Phase | Change | Details |
|-------|--------|---------|
| 1 | Removed `version: '3.8'` | No longer needed |
| 1 | Pinned alpine tag | `alpine:latest` → `alpine:3.21` in test-client.Dockerfile |
| 2 | Standardized test-client name | `homelab-metadata-test-client` → `homelab-metadata-extractor-test` |
| 3 | Extracted `POSTGRES_PASSWORD` | Moved to `.env`, added `.env.example` |
| 3 | Updated `query.sh` | Removed hardcoded password fallback; requires `DB_PASSWORD` env var |
| 4 | Renamed network | `homelab-reactive-net` → `homelab-metadata-net` |
| 5 | Renamed volume | `pg_data` → `metadata_extractor_pg_data` |
| 6 | Fixed port conflict | Host port `5433` → `25433` (conflict with timescaledb) |
| 8 | Updated README | All sections follow template; ports, names, passwords updated |

### Verification
- Had to force-remove stale containers from old network (`homelab-reactive-net`)
- Removed old volume (`metadata-extractor_pg_data`) and old network
- Ran `podman compose up -d --build` — all 3 containers started cleanly
- PostgreSQL became healthy within 15 seconds
- Test client connectivity: **PASS** (`SELECT 1` returned successfully)
- Extractor logs: connected on attempt 4, watching `/input`
- Ran `podman compose down -v` cleanup
