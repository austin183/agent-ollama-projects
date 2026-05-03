# Video Transcoder

Reactive file processing that monitors a folder for new video files and automatically transcodes them using NVIDIA GPU (NVENC), with job metadata stored in PostgreSQL.

## Overview

This experiment demonstrates GPU-accelerated video transcoding using FFmpeg with NVIDIA NVENC/CUVID, triggered reactively via Python watchdog (inotify). Transcode job metadata is logged to PostgreSQL for tracking and benchmarking.

## Quick Start

```bash
cd ~/homelab/reactive-processing/video-transcoder

# Copy and configure environment
cp .env.example .env
# Edit .env to set your password

# Build and start
podman compose up -d --build

# Watch logs
podman logs -f homelab-ffmpeg-cuda
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| postgresql | 25435:5432 | Transcode job metadata |
| ffmpeg | — | GPU-accelerated video transcoder (NVENC) |
| test-client | — | Testing with psql, jq, curl |

## How It Works

### Architecture

```
User drops video  -->  /input  -->  Watcher (Python)  -->  FFprobe (metadata)
                                                                      |
                                                                      v
                                                        PostgreSQL (job record)
                                                                      |
                                                                      v
                                                        FFmpeg (NVENC encode)
                                                                      |
                                                                      v
                                                        /output (transcoded .mkv)
```

**Data Flow:**
1. User drops a video file into the `input/` directory
2. The Python watcher detects the new file via inotify and waits 2 seconds for write stability
3. FFprobe extracts input metadata (codec, resolution, duration, file size)
4. A "running" job record is created in PostgreSQL
5. FFmpeg transcodes using NVIDIA NVENC (GPU encoding) with CUDA hardware acceleration
6. Encode performance metrics (FPS, speed, GPU utilization) are logged to PostgreSQL
7. The transcoded file appears in `output/` as `<name>_transcoded.mkv`

### Supported Input Formats

`.mkv`, `.mp4`, `.avi`, `.mov`, `.wmv`, `.flv`, `.webm`, `.m4v`, `.mts`, `.m2ts`, `.ts`

### Encoding Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Encoder | `h264_nvenc` | NVIDIA GPU encoder |
| Preset | `p4` | Speed/quality tradeoff (p1=fastest, p7=slowest) |
| Quality | `cq 23` | Constant quality (lower = better quality, larger file) |

## Verification

### Check containers are running

```bash
podman ps --filter name=homelab-pg-video --filter name=homelab-ffmpeg --filter name=homelab-video-transcoder
```

Expected output:
```
CONTAINER ID  IMAGE                                         COMMAND         STATUS
<id>          docker.io/library/postgres:16                 postgres        Up ...
<id>          localhost/video-transcoder_ffmpeg:latest      python3 ...     Up ...
<id>          localhost/video-transcoder_test-client:latest sleep 3600      Up ...
```

### Test transcoding with a video file

```bash
# Copy any video file to the input directory to trigger the watcher
cp /path/to/your-video.mkv input/

# Watch the transcoder logs
podman logs -f homelab-ffmpeg-cuda
```

Expected log output:
```
============================================================
[PROCESSING] <your-video>.mkv
  Input: 1920x1080 h264 208.8s 231.6MB
  Command: ffmpeg -y -hwaccel cuda -i /input/<your-video>.mkv -c:v h264_nvenc -preset p4 -cq 23 -c:a copy /output/<your-video>_transcoded.mkv
  Output: 226.9MB (0 fps, 7.3x realtime)
  GPU: 56% util, 2MB used
  Job 3: completed in 29.4s
```

### Query transcode jobs

```bash
# Recent jobs
podman exec homelab-video-transcoder-test /query.sh recent

# All jobs
podman exec homelab-video-transcoder-test /query.sh jobs

# Job status summary
podman exec homelab-video-transcoder-test /query.sh summary
```

#### Test Client Query Commands

The test client includes a `/query.sh` helper script with these commands:

| Command | Description |
|---------|-------------|
| `connectivity` | Test PostgreSQL connection |
| `jobs` | All transcode jobs |
| `recent` | Recent transcode jobs |
| `summary` | Job status summary |
| `cleanup` | Clear all records |

### Run benchmark comparison

```bash
# Compare CPU x264 vs NVENC vs full CUDA pipeline
podman exec homelab-ffmpeg-cuda /app/benchmark.sh /input/<your-video>.mkv /output/benchmarks

# View results
ls -la output/benchmarks/
```

The benchmark runs three encoding methods and compares speed, output size, and GPU utilization.

### Verify network connectivity

```bash
podman exec homelab-video-transcoder-test ping -c 2 ffmpeg
```

## Database Schema

```
transcode_jobs
├── id                  (SERIAL PK)
├── filename            (TEXT)
├── file_size_bytes     (BIGINT)
├── input_codec         (TEXT)
├── input_width         (INT)
├── input_height        (INT)
├── input_duration_secs (FLOAT)
├── output_codec        (TEXT)
├── preset              (TEXT)
├── crf                 (INT)
├── command             (TEXT)
├── output_file         (TEXT)
├── output_size_bytes   (BIGINT)
├── encode_fps          (FLOAT)
├── speed_x             (FLOAT)
├── gpu_util_pct        (FLOAT)
├── gpu_mem_used_mb     (FLOAT)
├── cpu_usage_pct       (FLOAT)
├── status              (TEXT: pending/running/completed/failed)
├── error_message       (TEXT)
├── created_at          (TIMESTAMPTZ)
├── started_at          (TIMESTAMPTZ)
└── completed_at        (TIMESTAMPTZ)
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PG_HOST` | `postgresql` | PostgreSQL container name |
| `PG_PORT` | `5432` | PostgreSQL port (internal) |
| `PG_DB` | `transcoder` | PostgreSQL database name |
| `PG_USER` | `transcoder` | PostgreSQL username |
| `PG_PASSWORD` | (env) | PostgreSQL password (from `.env`) |
| `INPUT_DIR` | `/input` | Directory to watch for video files |
| `OUTPUT_DIR` | `/output` | Directory for transcoded output |
| `ENCODER` | `nvenc` | Encoder type (nvenc for H.264) |
| `CRF` | `23` | Constant quality value |
| `PRESET` | `p4` | NVENC preset (p1=p7, speed vs quality) |

## Resource Usage

| Resource | Estimate | Actual |
|----------|----------|--------|
| RAM | ~200MB | ~17MB (PostgreSQL ~4MB + FFmpeg ~13MB idle) |
| Storage | ~600MB | ~585MB (FFmpeg CUDA image ~565MB + test-client ~20MB) |
| CPU | Near idle (event-driven) | Near idle (spikes during encode) |
| GPU | — | 55-56% utilization during encode, 1444MB VRAM |

## Benchmark Results

| Method | Time | Size | FPS | Speed |
|--------|------|------|-----|-------|
| CPU x264 (medium, CRF 23) | 243s | 81MB | — | 0.86x |
| CUDA NVENC (p4, CQ 23) | 30s | 226MB | 423 | 7.05x |
| Full CUDA (CUVID+NVENC) | 29s | 226MB | 436 | 7.27x |

**Key finding:** NVENC is ~8x faster than CPU x264 but produces ~2.8x larger files at equivalent numeric quality settings (NVENC CQ 23 is not directly comparable to x264 CRF 23). Full CUDA pipeline (GPU decode + encode) offers only ~2% improvement over NVENC alone.

## Troubleshooting

### GPU not detected
- Ensure NVIDIA container toolkit is installed on the host
- The `devices: nvidia.com/gpu=all` compose option requires the toolkit
- Verify with: `podman exec homelab-ffmpeg-cuda nvidia-smi`

### NVENC reported as "NO" on startup
- FFmpeg must be built with `--enable-nvenc` and `nv-codec-headers` installed
- Check: `podman exec homelab-ffmpeg-cuda ffmpeg -encoders | grep nvenc`

### Files not being processed
- The watcher uses inotify — it only fires for new file events
- Files existing before the watcher starts won't be picked up
- Re-copy the file to trigger: `cp /tmp/file.mkv input/file.mkv`
- Ensure the file extension is in the supported list

### Transcode fails with format error
- FFmpeg git HEAD auto-detects output format from file extension
- Don't use explicit `-f mkv` flag — let the `.mkv` extension handle it

### Duplicate files
- Files with the same MD5 hash are automatically skipped
- The `processed_hashes` set is in-memory — restarting the container resets it

### PostgreSQL connection failures
- The watcher retries connection for up to 60 seconds
- If it fails completely, restart: `podman compose restart ffmpeg`

## Cleanup

```bash
# Stop without removing data
podman compose down

# Stop and remove data volumes
podman compose down -v
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    homelab-videotranscoder-net                   │
│                                                                  │
│  ┌──────────────────────┐       ┌───────────────────────────┐   │
│  │   postgresql          │       │   ffmpeg (CUDA)           │   │
│  │   (postgres:16)       │◄──────│   (nvidia/cuda:12.6.0)    │   │
│  │                       │       │                           │   │
│  │  transcode_jobs       │       │  watches /input/          │   │
│  │  schema.sql           │       │  ffprobe + ffmpeg NVENC   │   │
│  │                       │       │  logs to DB               │   │
│  └────────┬──────────────┘       └──────────┬────────────────┘   │
│           │                                  │                    │
│  host:25435│                                 │                    │
│  (external access)                           │                    │
└───────────┼──────────────────────────────────┼────────────────────┘
            │                                  │
     ┌──────▼──────┐                  ┌────────▼────────┐
     │  Host FS    │                  │  Host FS        │
     │  input/     │                  │  output/        │
     │  (drop videos)│               │  (transcoded)   │
     └─────────────┘                  └─────────────────┘
```

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references
- [x] Ports are > 1024 (25435)
- [x] Test client container included with tools (psql, jq, curl)
- [x] Healthcheck uses pg_isready
- [x] Volumes use named volume for PostgreSQL data
- [x] Network name follows homelab-* pattern
- [x] PostgreSQL schema via /app/schema.sql (applied at startup)
- [x] depends_on with service_healthy condition
- [x] Verified PostgreSQL connectivity from test client
- [x] Verified NVENC transcoding (sample video → transcoded)
- [x] Verified job metadata logged to PostgreSQL
- [x] Verified GPU utilization during encode (55-56%)
- [x] Query helper script (/query.sh) working
- [x] Secrets extracted to .env
- [x] Alpine test-client pinned to 3.21
- [x] Benchmark script working (CPU vs NVENC vs full CUDA)
- [ ] Resource usage measured under sustained load
```
