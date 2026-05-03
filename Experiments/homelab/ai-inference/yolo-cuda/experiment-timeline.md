# Experiment C: YOLO CUDA Object Detection - Timeline

**Date:** April 26, 2026
**Status:** In Progress

---

## Initial Setup (April 26, 2026)

### Goal
Revive the paused OpenVINO analyzer (9E) experiment using CUDA-based YOLO instead of OpenVINO, with the same reactive processing pattern (watcher + PostgreSQL).

### Architecture
- **yolo-server**: FastAPI + ultralytics + CUDA GPU inference
- **postgresql**: PostgreSQL 16 Alpine for detection results
- **watcher**: Python file watcher that calls YOLO API and stores results
- **test-client**: Alpine with psql, jq, curl for querying

### Ports
- YOLO REST API: 28004 (host) -> 8000 (container)
- PostgreSQL: 25436 (host) -> 5432 (container)

### Files Created
- `docker-compose.yml` - 4 services, bridge network, NVIDIA CDI
- `Dockerfile` - CUDA runtime + Python + ultralytics + FastAPI
- `Dockerfile.watcher` - Python slim + Pillow + psycopg2 + watchdog
- `server.py` - FastAPI server with YOLOv8n CUDA inference
- `watcher.py` - Reactive file watcher with API calls + PostgreSQL storage
- `schema.sql` - detections table with JSONB (adapted from openvino-analyzer)
- `test-client.Dockerfile` - Alpine with tools
- `query.sh` - Query helper script
- `.env` / `.env.example` - PostgreSQL password

---

## Build & Startup Session (April 26, 2026)

### Build Issues
1. **`--break-system-packages` not supported**: The `nvidia/cuda:12.4.1-runtime-ubuntu22.04` image ships python3.11 with pip 22.x which doesn't have `--break-system-packages`. Fixed by removing the flag and using `python3.11 -m pip install` directly.
2. **Missing `python-multipart`**: FastAPI's `UploadFile` requires `python-multipart`. Added to Dockerfile pip install.
3. **`uvicorn` not in PATH**: The pip binary wasn't on PATH for the CMD. Fixed by using `python3.11 -m uvicorn` instead of bare `uvicorn`.

### Startup Results
- All 4 containers started successfully
- YOLO server: **healthy**, CUDA confirmed on GTX 1660 Ti
- PostgreSQL: **healthy** on port 25436
- Watcher: started but initial connection checks failed (PostgreSQL and YOLO server not ready yet)
  - Root cause: `podman-compose` `depends_on` with `condition: service_healthy` is unreliable (known issue per AGENTS.md)
  - Watcher will retry on each file event, so functional despite initial failures
- Test client: running

### Health Check
```json
{"status":"ok","model":"yolov8n.pt","cuda_available":true,"cuda_device":"NVIDIA GeForce GTX 1660 Ti"}
```

### Resource Usage
| Item | Value |
|------|-------|
| yolo-server image size | 8.21 GB |
| Model download | yolov8n.pt (6.2 MB, downloaded at runtime) |
| CUDA cold start | Model loaded on CUDA at container startup |

---

## Inference Testing (April 26, 2026)

### Watcher Startup Race Fix
- Added retry loop (30 attempts, 2s interval) for both PostgreSQL and YOLO server connections
- Watcher now blocks until both services are ready before starting the file watcher
- Only 1 retry needed per service in testing

### First Inference Results
- **Image**: bus.jpg (810x1080 JPEG, 137KB)
- **Cold inference latency**: 811.5ms (first inference after startup)
- **Warm inference latency**: 20-26ms (5 runs: 26.14, 19.56, 23.93, 21.32, 20.28)
- **Warm average**: ~22.2ms per image
- **Cold vs warm ratio**: ~22x slower on first inference
- **Detections**: 6 objects (bus 87.34%, 3x person 82-86%, 1x person 26.11%)
- **PostgreSQL**: Results stored successfully with JSONB detections

### Resource Usage
| Metric | Value |
|--------|-------|
| yolo-server RAM | 894.5 MB |
| PostgreSQL RAM | 4.1 MB |
| Watcher RAM | 20.2 MB |
| VRAM (model resident) | 1.65 GB / 6 GB |
| GPU utilization (idle) | 0% |
| yolo-server CPU | 2% |

### Benchmark Summary
| Metric | Value |
|--------|-------|
| Cold inference (first image) | 811.5ms |
| Warm inference (avg 5 runs) | 22.2ms |
| Warm inference (range) | 19.6 - 26.1ms |
| Detections per image | 6 (bus + people) |
| Model size on disk | 6.2 MB (yolov8n.pt) |
| VRAM footprint | 1.65 GB |
| Container image size | 8.21 GB |

---

## Known Issues

1. **Large image size**: 8.21 GB for the yolo-server image. The torch dependency pulls CUDA libraries. Could explore `torch-cuda` slim variants or pinning to CPU torch with CUDA runtime only.

---

## Next Steps

1. **Run more benchmark images**: Test with various image sizes and object counts
2. **Compare with OpenVINO**: Once 9E is unblocked, benchmark CUDA vs iGPU on identical images
3. **Explore smaller images**: Investigate torch-cuda slim or ONNX Runtime GPU as alternatives

---

## Lessons Learned

1. **`python-multipart` is required for FastAPI file uploads** - Easy to forget, clear error message though.
2. **`podman-compose` `depends_on` health conditions are unreliable** - Confirmed known pitfall. Need wait loops in application code.
3. **CUDA image with torch is large (8+ GB)** - Plan for disk budget accordingly.
4. **`--break-system-packages` is pip version-dependent** - Ubuntu 22.04 pip 22.x doesn't have it; Ubuntu 24.04+ does.
5. **ultralytics downloads models at runtime** - First container start needs network access to download yolov8n.pt from GitHub.
6. **Cold CUDA inference is expensive** - First inference takes ~800ms due to PTX compilation and GPU warmup. Subsequent inferences are ~22ms.
7. **YOLOv8n is very efficient on GTX 1660 Ti** - Only 1.65 GB VRAM, 22ms warm inference, excellent for real-time use.
8. **Watcher dedup by MD5 hash works** - Prevents reprocessing identical files dropped with same name.
