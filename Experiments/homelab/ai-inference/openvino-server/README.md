# OpenVINO Model Server - Experiment 4A

ResNet-50 image classification server with GPU passthrough on Intel Iris Xe.

## Quick Start

```bash
cd ai-inference/openvino-server
podman compose up -d
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| openvino-server | 28002 (host) → 9000 (container) | gRPC API (TensorFlow Serving format) |
| openvino-server | 9002 (host) → 8000 (container) | REST API (TensorFlow Serving format) |

## Testing

```bash
# Start the server
podman compose -f ai-inference/openvino-server/docker-compose.yml up -d

# Check health
curl http://localhost:8002/v1/models/resnet

# Run inference test from test client
podman exec homelab-openvino-test python3 /test-inference.py

# Run benchmark
podman exec homelab-openvino-test python3 /benchmark.py
```

## Testing

```bash
# Verify containers are running
podman ps | grep openvino

# Check server health
curl http://localhost:9002/v1/models/resnet

# Test connectivity from test client
podman exec homelab-openvino-test ping openvino-server

# Run inference test
podman exec homelab-openvino-test python3 /test-inference.py

# Run benchmark
podman exec homelab-openvino-test python3 /benchmark.py
```

## Troubleshooting

- **GPU not detected**: Check logs with `podman logs homelab-openvino-server | grep "Available devices"`. If only CPU appears, verify `user: root` and capabilities are set (see GPU Troubleshooting below).
- **Model not loading**: Verify model files exist in `models/resnet50/1/` with both `.xml` and `.bin` files. Run `file models/resnet50/1/*` to confirm they are not HTML pages.
- **Container unhealthy**: The healthcheck uses `curl` (not `wget`). Check logs with `podman logs homelab-openvino-server`.

## Cleanup

```bash
podman compose down -v
```

## Architecture

| Component | Details |
|-----------|---------|
| Server | `docker.io/openvino/model_server:2026.1-gpu` (357MB) |
| Model | ResNet-50 (22MB weights, 1000 ImageNet classes) |
| Input | 224x224 RGB, NCHW layout, FP32 |
| Output | 1000-class logit scores |
| REST API | `http://localhost:8002/v1/models/resnet:predict` |
| gRPC API | `localhost:9002` (TensorFlow Serving API) |
| Network | `homelab-openvino` (bridge) |

## API Usage

### REST API (TensorFlow Serving format)

```bash
# Model status
curl http://localhost:8002/v1/models/resnet

# Model metadata
curl http://localhost:8002/v1/models/resnet/metadata

# Inference (base64-encoded image)
curl -X POST http://localhost:8002/v1/models/resnet:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[[[0.1, 0.2, ...]]]]}'
```

The `instances` format expects preprocessed image data as a nested list with shape `[1, 3, 224, 224]`.

### Python Example

```python
import json, urllib.request
from PIL import Image
import numpy as np

img = Image.open("test.jpg").convert("RGB").resize((224, 224))
arr = np.array(img, dtype=np.float32)
mean, std = np.array([0.485, 0.456, 0.406]), np.array([0.229, 0.224, 0.225])
arr = ((arr / 255.0 - mean) / std).transpose(2, 0, 1)[np.newaxis]

payload = {"instances": arr.tolist()}
req = urllib.request.Request(
    "http://localhost:8002/v1/models/resnet:predict",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"}
)
resp = json.loads(urllib.request.urlopen(req).read())
top10 = sorted(enumerate(resp["predictions"][0]), key=lambda x: x[1], reverse=True)[:10]
```

## Performance (i5-1135G7)

### CPU (ResNet-50, FP32)

| Metric | Value |
|--------|-------|
| Avg latency | 21.9ms |
| Throughput | 45.6 req/s |
| RAM usage | 112MB |
| Min latency | 18.3ms |
| P95 latency | 41.1ms |

### GPU (ResNet-50, FP32, Intel Iris Xe)

| Metric | Value |
|--------|-------|
| Avg latency | 23.4ms |
| Throughput | 42.7 req/s |
| Min latency | 20.4ms |
| P50 latency | 22.5ms |
| P99 latency | 37.6ms |

**Note:** GPU is slightly slower for ResNet-50. The Iris Xe iGPU has limited compute compared to the CPU's AVX512 units, and data transfer overhead to/from the GPU outweighs computation benefit for small models.

## Known Limitations

- **Requires `user: root` for GPU access**: Rootless Podman remaps device ownership to `nobody:nogroup`, blocking non-root users. The `SYS_ADMIN` + `SYS_RAWIO` capabilities are sufficient (no `--privileged` needed).
- **GPU slower than CPU for small models**: ResNet-50 runs slightly faster on CPU (21.9ms) vs GPU (23.4ms) due to data transfer overhead. Larger models may benefit more from GPU.
- **gRPC API**: Requires TensorFlow Serving protobuf stubs to test. REST API is fully functional.
- **Model downloads**: Some OpenVINO storage URLs return HTML instead of model files. Verify with `file` command.

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Container configuration |
| `Dockerfile.test-client` | Test client image with Python, PIL, numpy |
| `test-inference.py` | REST API inference test |
| `benchmark.py` | Latency/throughput benchmark |
| `download-model.sh` | ResNet-50 model download script |
| `models/resnet50/1/` | Model files (.xml + .bin) |
| `test-image.jpg` | Test image (Destiny 2 cat) |

## GPU Troubleshooting

### GPU Not Detected

**Root cause:** Rootless Podman remaps device file ownership to `nobody:nogroup`. The container user (even with `video` group) cannot access devices owned by `nobody:nogroup`.

**Working configuration:**
```yaml
services:
  openvino-server:
    user: root                    # Required for device access
    cap_add:                      # Sufficient (no --privileged needed)
      - SYS_ADMIN
      - SYS_RAWIO
    devices:
      - /dev/dri:/dev/dri
    command: >
      --target_device GPU         # Must be explicit
```

### Why `user: root`?

```bash
# Host device ownership:
$ ls -la /dev/dri/
crw-rw----+ 1 root video  226,   1 card1
crw-rw----+ 1 root render 226, 128 renderD128

# Container device ownership (rootless Podman remaps):
$ ls -la /dev/dri/
crw-rw----+ 1 nobody nogroup 226,   1 card1
crw-rw----+ 1 nobody nogroup 226, 128 renderD128
```

The `ovms` user (uid=5000, in `video` group) cannot access `nobody:nogroup` owned devices. Root bypasses this check.

### GPU vs CPU Performance

| Metric | CPU | GPU |
|--------|-----|-----|
| Avg latency | 21.9ms | 23.4ms |
| Throughput | 45.6 req/s | 42.7 req/s |

GPU is slightly slower for ResNet-50 (small model). Expect better GPU utilization with larger models where compute outweighs data transfer overhead.

## References

- [OpenVINO Model Server docs](https://docs.openvino.ai/)
- [TensorFlow Serving API](https://www.tensorflow.org/serving/api_rest)
- [Open Model Zoo](https://github.com/openvinotoolkit/open_model_zoo)
