# Video Transcoder Experiment Timeline

**Date:** April 26, 2026
**Status:** Completed

## Setup Phase

### Pre-flight Checks
- Port 25435: available (no conflicts)
- GPU: NVIDIA GeForce GTX 1660 Ti, driver 580.126.18, 6GB VRAM
- CUDA toolkit 12.0 available on host
- Test video: `~/Videos/HaloSample.mkv` — H.264, 1920x1080, ~209s, ~232MB

### Build Iterations

**Trial 1:** Dockerfile with `--enable-cuda-sdk` flag
- **Error:** `ERROR: failed checking for nvcc` — CUDA SDK flag requires nvcc compiler, not in base image
- **Fix:** Removed `--enable-cuda-sdk` (not needed for NVENC/CUVID, only for CUDA filters)

**Trial 2:** Dockerfile without `--enable-cuda-sdk`
- **Error:** `ERROR: cuvid requested, but not all dependencies are satisfied: ffnvcodec`
- **Fix:** Added `nv-codec-headers` (FFmpeg/nv-codec-headers) build step before FFmpeg configure

**Trial 3:** Clone `nv-codec-headers` with `-b release`
- **Error:** `fatal: Remote branch release not found in upstream origin`
- **Fix:** Removed `-b release`, use default branch

**Trial 4:** Alpine test client
- **Error:** `postgresql-cli (no such package)`
- **Fix:** Changed to `postgresql-client`

**Trial 5:** FFmpeg build succeeds, containers start
- Watcher NVENC check reported "NO" — `ffmpeg -encoders` outputs to stdout, not stderr in git version
- **Fix:** Updated watcher.py to check `result.stdout + result.stderr`

**Trial 6:** Watcher processes first video
- **Error:** `Requested output format 'mkv' is not known` — explicit `-f mkv` not recognized by git FFmpeg
- **Fix:** Removed `-f mkv` flag; FFmpeg auto-detects format from file extension
- **Status:** Fix applied, pending retest

### Files Created
```
reactive-processing/video-transcoder/
├── docker-compose.yml       # PostgreSQL 16 + FFmpeg CUDA + Alpine test client
├── Dockerfile               # nvidia/cuda:12.6.0-base + FFmpeg from source (NVENC/CUVID/x264/x265)
├── Dockerfile.test-client   # Alpine 3.21 + postgresql-client + curl + jq
├── schema.sql               # transcode_jobs table
├── watcher.py               # inotify watcher + FFmpeg launcher + PostgreSQL logging
├── benchmark.sh             # CPU x264 vs NVENC vs full CUDA pipeline
├── .env                     # PostgreSQL credentials
├── .env.example
├── input/
└── output/
```

## Containers Running

| Container | Status | Notes |
|-----------|--------|-------|
| `homelab-pg-videotranscoder` | healthy | PostgreSQL 16, port 25435 |
| `homelab-ffmpeg-cuda` | running | FFmpeg CUDA, NVENC YES, GPU detected |
| `homelab-video-transcoder-test` | running | Alpine test client |

## Verification Phase

### FFmpeg Capabilities (inside container)
```
Hardware acceleration: cuda
Encoders: h264_nvenc, hevc_nvenc, av1_nvenc, libx264, libx265
GPU: NVIDIA GeForce GTX 1660 Ti
```

### Database
- PostgreSQL connected, schema initialized
- `transcode_jobs` table created with indexes

## Benchmark Results

**Completed** — April 26, 2026

### Reactive Transcoding
- HaloSample.mkv (1920x1080, H.264, 208.8s, 232MB) transcoded successfully
- NVENC output: 227MB, 29.1s wall time, 7.3x realtime
- GPU: 55% utilization, 1444MB VRAM used
- PostgreSQL job record created (job #2 completed, job #1 was the failed `-f mkv` attempt)

### Benchmark Comparison

| Method | Time | Size | FPS | Speed |
|--------|------|------|-----|-------|
| CPU x264 (medium, CRF 23) | 243s | 81MB | — | 0.86x |
| CUDA NVENC (p4, CQ 23) | 30s | 226MB | 423 | 7.05x |
| Full CUDA (CUVID+NVENC) | 29s | 226MB | 436 | 7.27x |

**Key finding:** NVENC is ~8x faster than CPU x264 but produces ~2.8x larger files at equivalent quality settings (CQ 23 vs CRF 23 are not directly comparable — NVENC CQ scale differs from x264 CRF). Full CUDA pipeline (GPU decode + encode) is marginally faster than NVENC alone (~2% improvement).

### Benchmark Script Fix
- `-loginfo` deprecated in git FFmpeg → replaced with `-loglevel info`

## What Didn't Work
- `--enable-cuda-sdk` requires nvcc (not needed for encode/decode)
- CUVID requires `nv-codec-headers` installed before FFmpeg configure
- `ffmpeg -encoders` output moved from stderr to stdout in recent git versions
- Explicit `-f mkv` not recognized; let FFmpeg auto-detect from extension
- `inotify` doesn't fire for files existing before watcher starts; must re-add file
- `-loginfo` flag removed in git FFmpeg; use `-loglevel info`

## Resource Usage
- FFmpeg image size: ~500MB (CUDA base + FFmpeg build + Python deps)
- PostgreSQL: ~30MB
- Test client: ~17MB
- GPU during encode: 55% utilization, 1444MB VRAM

## Lessons Learned
- NVENC/CUVID only needs `nv-codec-headers`, not full CUDA toolkit (nvcc)
- FFmpeg git HEAD may differ from release in output stream behavior
- Always check `ffmpeg -encoders` output stream when writing detection logic
- NVENC CQ 23 is NOT equivalent to x264 CRF 23 — NVENC produces larger files at same numeric value
- Full CUDA pipeline offers minimal benefit over NVENC-only for simple transcode (2% faster)
- `bind mount :ro` files are picked up live but in-memory state (processed_hashes) resets on restart
- SIGTERM handling: watcher.py only catches KeyboardInterrupt, not SIGTERM — container kills after 10s timeout
