# Experiment 9E: OpenVINO Image Analyzer - Experiment Timeline

**Date:** April 21, 2026  
**Status:** In Progress (paused - model conversion issue)

---

## Simplification Cleanup (April 24, 2026)

Applied per-experiment simplification plan (experiment #31 from `agent_docs/plans/experiment-simplification-per-experiment.md`).

### Phase 1 - Trivial Cleanup
- [x] Removed `version: '3.8'` line from docker-compose.yml
- [x] Pinned `alpine:latest` → `alpine:3.21` in test-client.Dockerfile
- [x] Pinned `openvino/ubuntu24_dev:latest` → `openvino/ubuntu24_dev:2026.1` in Dockerfile.server (build still fails due to rootless Podman `apt-get` issue)

### Phase 2 - Test-Client Standardization
- [x] Service already named `test-client` ✓
- [x] Already uses custom build (test-client.Dockerfile) with psql, jq, curl ✓
- [x] Container name `homelab-openvino-analyzer-test` matches convention ✓

### Phase 3 - Secret Hygiene
- [x] Created `.env` with `POSTGRES_PASSWORD=detect_pass_123`
- [x] Created `.env.example` with placeholder value and comment
- [x] Replaced hardcoded `detect_pass_123` in docker-compose.yml with `${POSTGRES_PASSWORD}`
- [x] Updated `query.sh` to use `DB_PASSWORD` env var with fallback
- [x] `.env` already excluded by repo root `.gitignore` ✓

### Phase 4 - Network Naming
- [x] Network key `homelab-openvino-analyzer` already follows convention ✓
- [x] Dropped redundant `name: homelab-openvino-analyzer` field from network definition

### Phase 5 - Volume Naming
- [x] Renamed named volume `pg_data` → `openvino-analyzer_postgresql_data`
- [x] Updated service reference in postgresql service

### Phase 6 - Port Conflicts
- [x] PostgreSQL host port: `5434` → `25434` (resolves conflict with postgresql-replication on 5434)
- [x] OpenVINO API host port: `8003` → `28003` (per plan allocation)
- [x] Updated README port references, troubleshooting section, and architecture diagram

### Phase 8 - README Consistency
- [x] Verified Overview section exists ✓
- [x] Updated port numbers in Testing section
- [x] Updated port numbers in Troubleshooting section
- [x] Updated architecture diagram host ports
- [x] Testing checklist updated with new ports

### Verification
- [x] `podman compose down -v` ✓
- [x] `podman compose up -d` — PostgreSQL started, openvino-server build fails (pre-existing issue)
- [x] Check all containers are running — PostgreSQL healthy on port 25434 ✓
- [x] Run test-client verification — connectivity ✓, schema ✓
- [x] `podman compose down -v` (cleanup after verification) ✓

### Additional Fixes During Verification

**schema.sql bug fix:** The `detection_count` generated column used `json_array_length(detections)` but PostgreSQL requires `json_array_length(detections::json)` for JSONB columns. Fixed in `schema.sql:16`. This was a pre-existing bug that would have prevented the experiment from working.

### Known Limitations

**`openvino-server` build fails** — The `Dockerfile.server` uses `openvino/ubuntu24_dev:latest` which fails during `apt-get update` in rootless Podman builds. This is a pre-existing issue documented in the original timeline. Resolving this requires an alternative approach (e.g., on-host model conversion or a different base image). The simplification changes do not affect this build issue.

---

## Setup Phase

### Initial Exploration

**Goal:** Understand the existing codebase patterns and available resources.

- Read `ai-inference/openvino-server/` - existing OpenVINO Model Server experiment (4A)
  - Uses `docker.io/openvino/model_server:2026.1-gpu` image
  - Has ResNet-50 model pre-built with multi-stage Dockerfile
  - Requires `user: root` + `SYS_ADMIN` + `SYS_RAWIO` for GPU access
  - ResNet-50 runs slightly faster on CPU (21.9ms) vs GPU (23.4ms)

- Read `reactive-processing/image-processor/` - existing reactive processing pattern
  - Uses Python 3.11-slim + Pillow + pymongo + watchdog
  - MongoDB for metadata storage
  - Watcher.py with inotify-based file monitoring

- Read `reactive-processing/metadata-extractor/` - PostgreSQL-based metadata storage
  - PostgreSQL 16 Alpine with init scripts
  - Schema with JSONB column for flexible metadata
  - Test client with query helper script

**Decision:** Combine OpenVINO Model Server (for inference) with reactive processing pattern (watcher) and PostgreSQL (for results storage).

### Architecture Design

```
4 services:
1. openvino-server: OpenVINO Model Server with YOLOv8n (GPU)
2. postgresql: PostgreSQL 16 for detection results
3. image-analyzer: Python watcher + inference client
4. test-client: Alpine with psql, jq, curl, query.sh helper
```

**Ports:**
- OpenVINO REST API: 8003 (host) → 8000 (container)
- PostgreSQL: 5434 (host) → 5432 (container)

---

### File Creation

Created all experiment files:
- `docker-compose.yml` - 4 services, bridge network
- `schema.sql` - detections table with JSONB column
- `watcher.py` - reactive file watcher with OpenVINO inference
- `Dockerfile` - image-analyzer (Python 3.11-slim + deps)
- `test-client.Dockerfile` - Alpine with psql, jq, curl
- `query.sh` - query helper script
- `README.md` - full documentation
- `download-model.sh` - manual model download script
- `download-and-convert.py` - Python script for model conversion
- `Dockerfile.server` - multi-stage build for model server

---

### Build Attempt 1: Multi-stage Dockerfile

**Command:** `podman compose build openvino-server`

**Error:** `docker.io/openvino/openvino:2026.1-debian11` - 403 Forbidden

**Root cause:** The `openvino/openvino:2026.1-debian11` tag doesn't exist or requires authentication.

**Attempted fix:** Changed base image to `docker.io/openvino/ubuntu24_dev:latest`

**Error:** `apt-get update` fails inside build container - `List directory /var/lib/apt/lists/partial is missing. - Acquire (13: Permission denied)`

**Root cause:** Rootless Podman build has restricted filesystem access. The `openvino/ubuntu24_dev` image doesn't work well with rootless builds.

---

### Build Attempt 2: On-Host Model Conversion

**Goal:** Download and convert YOLOv8n ONNX → OpenVINO IR on the host, then use model_server image directly.

**Step 1: Install OpenVINO Python package**

- `pip3` not available on host
- `python3 -m pip` not available
- `sudo apt-get install python3-pip` - requires password, not available in this session

**Step 2: Use container for conversion**

- Ran `openvino/ubuntu24_dev` container with Python to download + convert
- **Error:** `PermissionError: [Errno 13] Permission denied: 'models/yolov8n'`
- **Fix:** Created directory on host first (`mkdir -p models/yolov8n`)

**Step 3: Download YOLOv8n ONNX model**

- URL `https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n.onnx` returns 404
- URL `https://github.com/ultralytics/ultralytics/releases/download/v8.3.0/yolov8n.onnx` returns 404
- OpenVINO Model Zoo URLs return HTML (redirect pages), not actual files
- HuggingFace URLs return 401 (authentication required)

**Step 4: Export YOLOv8n using ultralytics**

- Ran `python:3.11-slim` container with `ultralytics` installed
- **Error:** `ImportError: libxcb.so.1: cannot open shared object file`
- **Fix:** Added `libxcb1`, `libglib2.0-0`, `libgl1-mesa-glx` packages
- **Error:** `libgl1-mesa-glx` not available in Debian trixie (replaced with `libgl1`)
- **Success!** YOLOv8n exported to ONNX (12.3 MB) + saved `yolov8n.pt` (6.5 MB)

**Result:** `models/yolov8n/yolov8n.onnx` (12.3 MB) - ✅

---

### Model Conversion Attempt

**Step 5: Convert ONNX → OpenVINO IR**

Using `openvino/ubuntu24_dev` container:

```python
core = ov.Core()
model = core.read_model('yolov8n.onnx')  # Success!
ov.save_model(model, 'yolov8n.xml')       # Error: can't open bin file
```

**Error:** `RuntimeError: Check 'bin_file' failed at serialize.cpp:116: Can't open bin file: "yolov8n.bin"`

**Investigation:**
- `ov.save_model()` signature: `save_model(model, output_model, compress_to_fp16=True)` - no `output=` keyword argument
- `ov.read_model()` works on ONNX files directly (ONNX frontend is built-in)
- `ov.convert_model()` expects different input types, fails with `openvino.Model` objects
- `openvino.runtime` module doesn't exist in 2026.1 (API changed)
- `ov.save_model()` tries to write `model.bin` alongside `.xml` but can't find/write it

**Root cause:** The OpenVINO 2026.1 Python API has changed significantly. The `save_model()` function expects the output path to be the base name (without extension), but it's failing to write the `.bin` file, possibly due to:
1. Working directory permissions inside the container
2. The way `core.read_model()` returns a model that isn't fully compatible with serialization
3. OpenVINO 2026.1 may have removed or changed the IR serialization API

**Status:** ❌ Model conversion not yet resolved. Need to find alternative approach.

---

### Model Server Binary Investigation

**Goal:** Understand the model_server binary location and capabilities.

**Findings:**
- Binary is at `/ovms/bin/ovms` (not `/ovms/bin/model_server`)
- Help output shows text generation options (different version than expected)
- Supports `--model_path`, `--model_name`, `--rest_port`, `--port`
- Need to verify if it supports ONNX models directly or only IR format

**Status:** ⏸️ Paused - need to test model_server with ONNX model after conversion issue is resolved.

---

## What Worked

| Item | Status | Notes |
|------|--------|-------|
| Created experiment directory structure | ✅ | All directories created |
| Created docker-compose.yml | ✅ | 4 services, proper networking |
| Created schema.sql | ✅ | detections table with JSONB |
| Created watcher.py | ✅ | Full reactive processing pipeline |
| Created Dockerfile (image-analyzer) | ✅ | Python 3.11-slim + deps |
| Created test-client.Dockerfile | ✅ | Alpine with psql, jq, curl |
| Created query.sh | ✅ | 10 query commands |
| Created README.md | ✅ | Full documentation |
| Exported YOLOv8n to ONNX | ✅ | 12.3 MB file |
| OpenVINO Core.read_model() on ONNX | ✅ | Model loaded successfully |
| PostgreSQL container starts | ✅ | Already verified in compose |
| Test client builds | ✅ | Already cached from previous run |

---

## What Didn't Work

| Item | Issue | Root Cause |
|------|-------|------------|
| Multi-stage Dockerfile build | `apt-get` fails in rootless Podman | Rootless build has restricted filesystem access |
| `openvino/openvino:2026.1-debian11` | 403 Forbidden | Tag doesn't exist or requires auth |
| `libgl1-mesa-glx` package | Not available in Debian trixie | Package renamed/removed in newer Debian |
| YOLOv8n ONNX download | 404 from GitHub | URL structure changed in ultralytics repo |
| OpenVINO IR conversion | `save_model()` fails | OpenVINO 2026.1 API changes + serialization issue |
| `ov.convert_model()` | `Unknown model type: openvino._ov_api.Model` | API expects framework-specific objects, not IR Model |
| `ov.save_model()` | Can't write `.bin` file | Unknown - possibly API change or working dir issue |

---

## Debugging Steps Taken

1. **Explored available OpenVINO images:** `podman search docker.io/openvino/` - found `ubuntu24_dev`, `model_server`
2. **Checked model optimizer availability:** `mo` command not found, `openvino.tools.mo` module not importable
3. **Checked Python API:** `ov.convert_model`, `ov.save_model`, `ov.Core.read_model` all available
4. **Tested ONNX reading:** `core.read_model('yolov8n.onnx')` succeeds, returns model with correct shape `[1,3,640,640]`
5. **Tested save_model with keyword args:** `output=` parameter rejected - positional only
6. **Tested save_model with positional args:** `save_model(model, 'yolov8n.xml')` - fails on `.bin` file
7. **Tested serialize module:** `from openvino.runtime import serialize` - module doesn't exist in 2026.1
8. **Explored model_server binary:** Found at `/ovms/bin/ovms`, different CLI than expected

---

## Next Steps (When Resuming)

1. **Fix model conversion:** Options to try:
   - Use `openvino/tools/ovc` command-line tool inside container
   - Try `ov.save_model()` with explicit `.bin` path
   - Check if model_server can load ONNX directly (bypass IR conversion)
   - Try a different OpenVINO image version that has working model optimizer

2. **Test model_server with ONNX:** See if the model accepts ONNX format directly

3. **Start containers and verify:** Once model is in place, run `podman compose up -d`

4. **Test inference pipeline:** Drop an image into `input/` and verify detection results

5. **Verify database storage:** Query PostgreSQL for detection records

---

## Lessons Learned

1. **OpenVINO 2026.1 API is different from 2024.x:** `ov.read_model()`, `ov.save_model()`, and `ov.convert_model()` behave differently. Documentation may not be updated.

2. **Rootless Podman has build limitations:** `apt-get` operations fail during multi-stage builds due to filesystem permission restrictions.

3. **YOLOv8 model URLs change frequently:** GitHub release URLs break. Using `ultralytics` Python library to export models is more reliable than downloading pre-built ONNX files.

4. **Debian trixie package changes:** `libgl1-mesa-glx` was replaced with `libgl1`. Package names evolve.

5. **OpenVINO Model Zoo URLs are redirect pages:** The storage.openvinotoolkit.org URLs return HTML redirect pages, not direct file downloads.

6. **Multi-stage Dockerfiles in rootless Podman:** The builder stage runs as root inside the build context, but filesystem operations like `apt-get` can still fail due to rootless restrictions.

---

## Resource Notes

- **Host:** Dell Inspiron 5502, i5-1135G7, 12GB RAM, 256GB NVMe
- **Available disk:** ~101GB free (53% used)
- **Running containers during work:** metadata-extractor (3 containers)
- **YOLOv8n ONNX size:** 12.3 MB
- **YOLOv8n PT size:** 6.5 MB
- **OpenVINO ubuntu24_dev image:** ~2.5 GB downloaded
- **Python:3.11-slim + ultralytics:** ~1.5 GB downloaded
