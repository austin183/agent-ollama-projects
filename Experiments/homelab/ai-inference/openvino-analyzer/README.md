# Experiment 9E: OpenVINO Image Analyzer

Reactive file processing combined with AI inference: watches a folder for new images, runs YOLOv8n object detection via OpenVINO, and stores results in PostgreSQL.

## How It Works

```
[User drops image] --> [input/ folder] --> [inotify watcher] --> [OpenVINO inference] --> [PostgreSQL]
                                       |
                                       v
                                  debounce 1s
                                  skip duplicates
```

1. **File Detection:** Python watchdog library monitors `input/` via Linux inotify
2. **Debounce:** 1-second delay avoids processing partial file writes
3. **Deduplication:** MD5 hash check skips already-processed files
4. **Preprocessing:** Image resized to 640x640, normalized to [0,1], converted to NCHW format
5. **Inference:** YOLOv8n object detection model runs via OpenVINO Model Server (GPU)
6. **Parsing:** Raw model output parsed into bounding boxes, class IDs, confidence scores
7. **Storage:** Results stored in PostgreSQL with detection count and latency
8. **Output:** Processed images saved to `output/` directory

## Architecture

| Component | Details |
|-----------|---------|
| Inference Server | `openvino/model_server:2026.1-gpu` (custom build with YOLOv8n) |
| Model | YOLOv8n (640x640 input, 80 COCO classes, ~3.5MB weights) |
| Watcher | Python 3.11 + Pillow + numpy + psycopg2 + watchdog |
| Database | PostgreSQL 16 Alpine (detections table) |
| Network | `homelab-openvino-analyzer` (bridge) |
| GPU | Intel Iris Xe via `/dev/dri` passthrough |

## Quick Start

```bash
cd ~/homelab/ai-inference/openvino-analyzer

# Build and start (model download + conversion happens during build)
podman compose up -d --build

# Watch logs (model loading takes ~30-60s)
podman logs -f homelab-openvino-analyzer-server
```

## Testing

### 1. Verify containers are running

```bash
podman ps --filter name=homelab-openvino-analyzer

# Expected output:
# homelab-openvino-analyzer-server  (OpenVINO Model Server, healthy)
# homelab-openvino-analyzer-pg      (PostgreSQL, healthy)
# homelab-openvino-analyzer         (Python watcher, running)
# homelab-openvino-analyzer-test    (alpine, sleeping)
```

### 2. Test PostgreSQL connectivity

```bash
podman exec homelab-openvino-analyzer-test /query.sh connectivity
```

Expected output:
```
Testing PostgreSQL connectivity...
 connected 
-----------
          1
(1 row)
```

### 3. Test object detection

```bash
# Copy a test image into the input directory
cp ~/Pictures/test.jpg input/

# Or use a sample image
cp /home/labratorian/homelab/ai-inference/openvino-server/test-image.jpg input/

# Watch the analyzer logs
podman logs -f homelab-openvino-analyzer
```

Expected log output:
```
[PROCESSING] test.jpg
  Preprocessed: 800x600 -> 640x640 (NCHW FP32)
  Inference latency: 25.3ms
  Detections: 3 objects found
    - person (0.9234): [120,50,350,480]
    - dog (0.8712): [400,200,600,500]
    - chair (0.6543): [50,300,150,450]
  Results stored in PostgreSQL
```

### 4. Query the database

```bash
# Via test client
podman exec homelab-openvino-analyzer-test /query.sh list
podman exec homelab-openvino-analyzer-test /query.sh recent
podman exec homelab-openvino-analyzer-test /query.sh objects
podman exec homelab-openvino-analyzer-test /query.sh high_conf

# Via host (port 5434)
 PGPASSWORD=detect_pass_123 psql -h 127.0.0.1 -p 25434 -U detect_user -d detections -c \
  "SELECT filename, image_width, image_height, detection_count, 
          ROUND(inference_latency_ms, 1) AS latency_ms, processed_at
   FROM detections ORDER BY processed_at DESC LIMIT 5"
```

#### Test Client Query Commands

| Command | Description |
|---------|-------------|
| `connectivity` | Test PostgreSQL connection |
| `count` | Total detection records |
| `list` | Recent detections (summary) |
| `details <id>` | Detailed results for specific detection |
| `objects` | Most detected object types |
| `high_conf` | High confidence detections (>80%) |
| `recent` | Last 5 processed images |
| `clear` | Clear all records |
| `schema` | Show table schema |

### 5. Test model server directly

```bash
# Check model status
curl http://localhost:28003/v1/models/yolov8n

# Check model metadata
curl http://localhost:28003/v1/models/yolov8n/metadata
```

Expected output:
```json
{
  "name": "yolov8n",
  "base_model": "",
  "state": "READY",
  "parameters": {},
  "status": {"errors": []},
  "metrics": {"state": "READY"}
}
```

### 6. Test with different image types

```bash
# Test with various formats
cp ~/Pictures/photo.jpg input/
cp ~/Pictures/screenshot.png input/
cp ~/Downloads/image.webp input/

# Watch logs to see processing
podman logs -f homelab-openvino-analyzer
```

## Database Schema

```
detections
├── id                (SERIAL PK)
├── filename          (VARCHAR)
├── file_path         (TEXT)
├── file_size_bytes   (BIGINT)
├── image_width/height ( INTEGER)
├── image_format      (VARCHAR)
├── model_name        (VARCHAR - default 'yolov8n')
├── model_input_size  (VARCHAR - default '640x640')
├── inference_device  (VARCHAR - default 'GPU')
├── inference_latency_ms (DOUBLE PRECISION)
├── detections        (JSONB - array of detection objects)
├── detection_count   (INTEGER - generated from JSONB)
└── processed_at      (TIMESTAMP)
```

Each detection in the `detections` JSONB array:
```json
{
  "class_id": 0,
  "class_name": "person",
  "confidence": 0.9234,
  "bbox": {
    "x1": 120, "y1": 50, "x2": 350, "y2": 480
  }
}
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `INPUT_DIR` | `/input` | Directory to watch for new images |
| `OUTPUT_DIR` | `/output` | Directory for processed outputs |
| `DB_HOST` | `postgresql` | PostgreSQL container name |
| `DB_PORT` | `5432` | PostgreSQL port (internal) |
| `DB_NAME` | `detections` | PostgreSQL database name |
| `DB_USER` | `detect_user` | PostgreSQL username |
| `DB_PASSWORD` | (env) | PostgreSQL password |
| `OVMS_HOST` | `openvino-server` | OpenVINO Model Server container |
| `OVMS_PORT` | `8000` | Model Server REST API port |
| `CONFIDENCE_THRESHOLD` | `0.4` | Min confidence to include detection |

## YOLOv8n Model Details

- **Architecture:** You Only Look Once v8 Nano
- **Input:** 640x640 RGB, NCHW layout, FP32
- **Output:** Bounding boxes + class probabilities (80 COCO classes)
- **COCO Classes:** person, bicycle, car, motorcycle, airplane, bus, train, truck, boat, traffic light, fire hydrant, stop sign, parking meter, bench, bird, cat, dog, horse, sheep, cow, elephant, bear, zebra, giraffe, backpack, umbrella, handbag, tie, suitcase, frisbee, skis, snowboard, sports ball, kite, baseball bat/glove, skateboard, surfboard, tennis racket, bottle, wine glass, cup, fork, knife, spoon, bowl, banana, apple, sandwich, orange, broccoli, carrot, hot dog, pizza, donut, cake, chair, couch, potted plant, bed, dining table, toilet, tv, laptop, mouse, remote, keyboard, cell phone, microwave, oven, toaster, sink, refrigerator, book, clock, vase, scissors, teddy bear, hair drier, toothbrush
- **Model Size:** ~3.5MB (ONNX), ~7MB (OpenVINO IR)
- **Expected Performance:** ~20-40ms per image on Iris Xe GPU

## Resource Usage

| Resource | Estimate | Actual |
|----------|----------|--------|
| RAM | ~800MB | TBD |
| Storage | ~500MB (model + deps) | TBD |
| CPU | Near idle (event-driven) | TBD |
| GPU | Intel Iris Xe (during inference) | TBD |

## Common Pitfalls

### Model fails to load (state: FAILED)
- Check server logs: `podman logs homelab-openvino-analyzer-server`
- Verify model files exist: `podman exec homelab-openvino-analyzer-server ls -la /models/yolov8n/`
- Should show `model.xml` and `model.bin` files
- Rebuild with: `podman compose up -d --build --force-recreate openvino-server`

### GPU access issues
- Requires `user: root` + `SYS_ADMIN` + `SYS_RAWIO` capabilities
- Requires `/dev/dri` device passthrough
- Check: `podman exec homelab-openvino-analyzer-server cat /proc/driver/intel-gpu/info`

### Images not being processed
- Check watcher logs: `podman logs homelab-openvino-analyzer`
- Verify input directory is mounted: `podman exec homelab-openvino-analyzer ls /input/`
- Ensure file extension is supported (.jpg, .png, .webp, .bmp, .tiff)
- Check PostgreSQL is healthy: `podman logs homelab-openvino-analyzer-pg | grep "ready"`

### Duplicate processing
- Files with the same MD5 hash are automatically skipped
- Clear hash tracking by restarting: `podman compose restart image-analyzer`
- Or clear database: `podman exec homelab-openvino-analyzer-test /query.sh clear`

### Port conflict
- PostgreSQL is mapped to host port **25434** (not 5432, 5433, or 5434)
- Model Server REST API is on host port **28003** (not 8000, 8002, or 8003)
- Use `psql -h 127.0.0.1 -p 25434` to connect from host

### Inference fails with connection error
- The analyzer waits for both services to be healthy before starting
- If it still fails, check: `curl http://localhost:8003/v1/models/yolov8n`
- Model loading can take 30-60 seconds on first start

### High confidence threshold misses detections
- Default threshold is 0.4 (40%)
- Lower it for more detections: set `CONFIDENCE_THRESHOLD=0.2`
- Higher for fewer, more reliable detections: set `CONFIDENCE_THRESHOLD=0.6`

## Stopping

```bash
# Stop without removing data
podman compose down

# Stop and remove data volumes (WARNING: deletes detection records)
podman compose down -v
```

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    homelab-openvino-analyzer                      │
│                                                                   │
│  ┌──────────────────────┐    ┌──────────────────────────────┐    │
│  │  openvino-server      │    │  postgresql                   │    │
│  │  (model_server:gpu)   │    │  (postgres:16-alpine)        │    │
│  │                      │    │                              │    │
│  │  YOLOv8n model       │◄───│  /var/lib/postgresql/data   │    │
│  │  REST API :8000      │    │  schema.sql                  │    │
│  │  GPU: /dev/dri       │    │                              │    │
│  └──────────┬───────────┘    └──────────┬───────────────────┘    │
│             │ inference requests        │ store results          │
│  host:8003  │                           │                        │
│  (REST API) │                           │                        │
│             │                           │                        │
│  ┌──────────▼───────────────────────────▼──────────────────┐    │
│  │  image-analyzer                                          │    │
│  │  (python:3.11-slim)                                     │    │
│  │                                                          │    │
│  │  watches /input/  ──► preprocesses ──► infers ──► stores│    │
│  │  watchdog + PIL + numpy + psycopg2                       │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │  test-client                                              │    │
│  │  (alpine + psql + jq + curl)                             │    │
│  │  /query.sh helper script                                 │    │
│  └──────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
        │                                    │
         ▼                                    ▼
    host:25434                         Host FS
    (PostgreSQL)                       input/  (drop images)
                                       output/ (processed)
```

## Testing Checklist

```
Experiment Setup Progress:
- [ ] Compose file uses full image references
- [ ] Ports are > 1024 (25434, 28003)
- [ ] Test client container included with tools (psql, jq, curl, file)
- [ ] Healthcheck uses curl for model server, pg_isready for PostgreSQL
- [ ] Volumes use hybrid strategy (named + bind)
- [ ] Network name follows homelab-* pattern
- [ ] PostgreSQL init script via /docker-entrypoint-initdb.d/
- [ ] depends_on with service_healthy conditions
- [ ] GPU passthrough with user: root + SYS_ADMIN + SYS_RAWIO
- [ ] Model downloaded and converted during build (multi-stage Dockerfile)
- [ ] Verified PostgreSQL connectivity from test client
- [ ] Verified model server health endpoint
- [ ] Verified object detection with sample image
- [ ] Verified detection results stored in PostgreSQL
- [ ] Resource usage measured
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Container configuration |
| `Dockerfile.server` | Multi-stage build: download + convert YOLOv8n model |
| `Dockerfile` | Image analyzer watcher (Python + dependencies) |
| `test-client.Dockerfile` | Test client with psql, jq, curl |
| `watcher.py` | Reactive file watcher + OpenVINO inference + PostgreSQL storage |
| `schema.sql` | PostgreSQL table schema for detection results |
| `download-model.sh` | Manual model download (alternative to Dockerfile build) |
| `query.sh` | Test client query helper script |
| `input/` | Drop images here for analysis |
| `output/` | Processed output directory |
| `models/` | Model files (created during build) |

## References

- [OpenVINO Model Server docs](https://docs.openvino.ai/)
- [YOLOv8 by Ultralytics](https://github.com/ultralytics/ultralytics)
- [COCO Dataset Classes](https://cocodataset.org/#home)
- [OpenVINO Model Optimizer](https://docs.openvino.ai/)
