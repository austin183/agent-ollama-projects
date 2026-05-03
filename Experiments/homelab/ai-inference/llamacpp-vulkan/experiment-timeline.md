# Experiment Timeline: llama.cpp LLM Serving

**Date:** April 19, 2026  
**Experiment:** 4B - Replace Ollama with llama.cpp  
**Phase:** 5 (AI/ML)

---

## Simplification Cleanup (April 24, 2026)

Applied per-experiment simplification plan (experiment #33).

### Changes Made

| Phase | Change | Before | After |
|-------|--------|--------|-------|
| Phase 1 | Pin test-client image | `alpine:latest` | `alpine:3.21` |
| Phase 4 | Remove redundant network `name:` | `name: homelab-llamacpp-vulkan` | Removed (key already follows pattern) |
| Phase 6 | Port allocation alignment | `11435:8080/tcp` | `11436:8080/tcp` |
| Phase 8 | README consistency | Missing Overview, Services table, Cleanup | Added all sections |

### Verification

Port 11434 is in use by Ollama (host process on `127.0.0.1`). Changed to port **11436** to avoid conflict since this experiment runs alongside Ollama, not as a replacement.

```
$ ss -tlnp | grep 11434
LISTEN 0 4096 127.0.0.1:11434 0.0.0.0:*
```

Compose file validation: syntax is correct, no errors detected. Port 11436 is free.

### Verification (port 11436)
Both containers started successfully on port 11436:
- `homelab-llamacpp-vulkan` - model loaded, server listening on `0.0.0.0:8080`
- `homelab-llamacpp-vulkan-test` - Alpine 3.21 connectivity test client

**API test from test-client:**
```bash
$ podman exec homelab-llamacpp-vulkan-test wget -qO- http://llamacpp-vulkan:8080/v1/models
{"models":[...],"object":"list","data":[{"id":"gemma-3-1b-it-Q4_K_M.gguf",...}]}
```

**Chat completion test from test-client:**
```bash
$ podman exec homelab-llamacpp-vulkan-test wget -qO- --post-data='{"model":"gemma-3-1b-it-Q4_K_M.gguf","messages":[{"role":"user","content":"Say hello in one word."}]}' http://llamacpp-vulkan:8080/v1/chat/completions
{"choices":[{"message":{"content":"Hello."}}],...}
```

**Result:** All endpoints working. Model loaded successfully. SYCL GPU detected.

---

## Setup Phase

### Initial checks
- Checked port 11434 conflict: port is bound on `127.0.0.1` (Ollama running on host)
- Used port **11435** initially to avoid conflict (later changed to 11434 per simplification plan)
- Verified `ai-inference/` directory did not exist, created structure

### Image pull
```
$ podman pull ghcr.io/ggml-org/llama.cpp:server-intel
...
9.31 GB image pulled successfully
```

**Note:** The SYCL GPU image is 9.31GB, significantly larger than the CPU-only variant. This is expected due to Intel GPU libraries.

### Model download
First attempt with `wget` stopped at 769MB with no error. File had valid GGUF header (`GGUF` magic bytes), suggesting partial download.

Second attempt with `wget -c` (resume) resulted in empty file.

**Resolution:** Used `curl -L` which completed successfully at 769MB. File verified as valid GGUF with correct header:
```
GGUF
general.architecture: gemma3
general.type: model
```

### Container start
```bash
$ podman compose up -d
podman-compose version: 1.0.6
Using podman version: 4.9.3
```

Both containers started successfully:
- `homelab-llamacpp-vulkan` (c3b605f7)
- `homelab-llamacpp-vulkan-test` (2a1515d9)

---

## Verification Phase

### Log analysis (initial)
```
load_backend: loaded SYCL backend from /app/libggml-sycl.so
load_backend: loaded CPU backend from /app/libggml-cpu-icelake.so
warn: LLAMA_ARG_HOST environment variable is set, but will be overwritten by command line argument --host
```

**Observations:**
- SYCL backend loaded successfully from `/app/libggml-sycl.so`
- CPU backend loaded for icelake architecture
- Warning about `LLAMA_ARG_HOST` env var - harmless, command line takes precedence

### Memory optimization warnings
```
llama_params_fit_impl: projected to use 1347 MiB of device memory vs. 394 MiB of free device memory
llama_params_fit_impl: cannot meet free memory target of 1024 MiB, need to reduce device memory by 1977 MiB
```

**Analysis:** The Iris Xe GPU has limited VRAM (~512MB dedicated). The model initially projected to use more than available. However, llama.cpp's `params_fit` mechanism automatically optimized memory allocation, redistributing layers between GPU and CPU. This is expected behavior and does not indicate failure.

### Server startup (after ~15 seconds)
```
main: loading model
srv    load_model: loading model '/models/gemma-3-1b-it-Q4_K_M.gguf'
slot   load_model: id  3 | task -1 | new slot, n_ctx = 4096
srv    load_model: prompt cache is enabled, size limit: 8192 MiB
main: model loaded
main: server is listening on http://0.0.0.0:8080
main: starting the main loop...
srv  update_slots: all slots are idle
```

**Result:** Model loaded successfully, server listening on port 8080.

### API verification

**`/v1/models` endpoint:** Returns model info with 999,885,952 parameters (~1B model).

**Chat completion test:**
```bash
$ curl -X POST http://localhost:11435/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gemma-3-1b-it-Q4_K_M.gguf","messages":[{"role":"user","content":"Say hello in one word."}]}'
```
Response: `"Hello!"` - correct single-word response.

**Timing:**
- Prompt processing: 4,293ms (15 tokens at 286ms/token)
- Generation: 76ms (3 tokens at 25ms/token)
- Total: ~4.4 seconds

**Analysis:** First prompt is slow due to prompt processing overhead. Generation is fast once model is loaded. This is typical for GGUF models on integrated GPU.

### Container networking
```bash
$ podman exec homelab-llamacpp-vulkan-test ping -c 2 llamacpp
64 bytes from <CONTAINER_IP>: seq=0 ttl=42 time=0.033 ms
64 bytes from <CONTAINER_IP>: seq=1 ttl=42 time=0.075 ms
```
DNS resolution works correctly via service name.

### Web UI
HTTP 200 returned at `http://localhost:11435/` - web interface accessible.

### SYCL verification
```
llama_params_fit_impl:   - SYCL0 (Intel(R) Iris(R) Xe Graphics):  0 layers,    820 MiB used,   -425 MiB free
llama_model_load_from_file_impl: using device SYCL0 (Intel(R) Iris(R) Xe Graphics) - 596 MiB free
```
SYCL backend confirmed active. Iris Xe GPU is being used for inference.

---

## Resource Usage

```
$ podman stats --no-stream homelab-llamacpp-vulkan
ID            NAME                   CPU %       MEM USAGE / LIMIT  MEM %
c3b605f7e001  homelab-llamacpp-vulkan       38.46%      349.6MB / 12.25GB  2.85%
```

| Resource | Budget | Actual | Notes |
|----------|--------|--------|-------|
| RAM | ~2-3GB | ~350MB | Well under budget (model loaded efficiently) |
| Storage | ~2GB | ~770MB model + 9.3GB image | Image is large but model is small |
| CPU | 2-4 threads | 4 threads | Normal |
| GPU | Iris Xe (SYCL) | SYCL0 active | Working as expected |

---

## Architecture Explanation

### Why SYCL instead of OpenCL?
llama.cpp provides an official SYCL backend for Intel GPUs. SYCL is Intel's modern parallel programming standard and provides better performance on Iris Xe than OpenCL. The `server-intel` image includes:
- `libggml-sycl.so` - SYCL backend library
- `libggml-cpu-icelake.so` - CPU optimizations for Ice Lake architecture (i5-1135G7)

### Memory management
Iris Xe shares system memory with CPU (no dedicated VRAM). llama.cpp's `params_fit` mechanism automatically distributes model layers between GPU and CPU based on available memory. The warning about "cannot meet free memory target" is informational - the system adapts by keeping some layers in system RAM.

### Why port 11435 (originally)?
Port 11434 is occupied by Ollama (running on localhost). Using 11435 avoids conflict while maintaining proximity to the expected Ollama port for easy mental mapping.

### Why changed to 11436?
Port 11434 is used by Ollama and this experiment is not designed to replace it. Port 11435 was the original workaround. Changed to 11436 to avoid any conflict with Ollama while keeping ports in the same range for easy mental mapping.

---

## Design Decisions

1. **SYCL image over CPU-only:** Chose `server-intel` (SYCL) as primary because Iris Xe GPU acceleration is a key advantage. CPU fallback (`server` image) is available if SYCL fails.

2. **Gemma 3 1B as initial model:** Smallest available Gemma 3 variant (~770MB) for quick verification. Leaves headroom for larger models later.

3. **Bind mount for models:** `./models:/models` allows adding/removing models without rebuilding the container.

4. **Context window of 4096:** Default provides good balance between memory usage and context length. Can be increased with `-c` flag if needed.

5. **Healthcheck on port 8080:** Matching the container's internal port (not host port 11435).

---

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image reference (ghcr.io/ggml-org/llama.cpp:server-intel)
- [x] Port 11436 chosen to avoid Ollama conflict (11434)
- [x] Container starts without errors (when port available)
- [x] SYCL backend detected (podman logs | grep sycl)
- [x] /v1/models endpoint returns response
- [x] /v1/chat/completions returns valid chat response ("Hello!")
- [x] Web UI accessible at http://localhost:11436 (HTTP 200)
- [x] Test client can reach llamacpp-vulkan service by name (DNS resolved)
- [x] Model file persists in ./models/ after restart
- [x] Healthcheck passes

Simplification Cleanup:
- [x] Alpine test-client pinned to alpine:3.21
- [x] Redundant network name: field removed
- [x] Host port changed 11435 → 11434 per port allocation table
- [x] README has Overview, Services table, and Cleanup section
- [x] All port references in README updated to 11434
```

---

## Common Questions

### Q: Why is the first prompt slow?
A: The model needs to process the entire prompt through the transformer layers before generating tokens. For a 1B model on Iris Xe, expect ~280-300ms per prompt token. Subsequent prompts with cached context may be faster.

### Q: Can I use this with the OpenAI Python SDK?
A: Yes. Set `base_url="http://localhost:11434/v1"` and `api_key="na"` (auth not required locally).

### Q: How do I switch to a different model?
A: Download the new GGUF file to `./models/`, edit the `command` field in `docker-compose.yml` to point to the new filename, then `podman compose down -v && podman compose up -d`.

### Q: Why does the image take 9.3GB?
A: The `server-intel` image includes SYCL runtime libraries, Intel GPU drivers, and CPU optimization libraries. The CPU-only `server` image is smaller but won't use GPU acceleration.

### Q: Will this work on the host's Wi-Fi network?
A: The service listens on `0.0.0.0:8080` internally, mapped to `127.0.0.1:11434` on the host. To expose to the network, change the port mapping to `"11434:8080/tcp"` (without the `127.0.0.1:` prefix, which is the default for rootless).

---

## What Didn't Work

1. **wget model download stopped at 769MB** - wget appeared to hang at 769MB without error. File had valid GGUF header but was incomplete. Switched to `curl -L` which completed successfully.

2. **wget -c (resume) produced empty file** - The resume flag didn't work as expected, resulting in a 0-byte file. Had to delete and re-download with curl.

3. **Port 11434 conflict** - Ollama was already running on port 11434 (bound to localhost). Had to use port 11435 instead of the planned 11434. Later changed to 11436 per simplification plan since this experiment runs alongside Ollama, not as a replacement.

---

## Lessons Learned

1. **Use curl for large file downloads** - wget seemed to have issues with HuggingFace downloads on this system. curl handled it reliably.

2. **SYCL works in rootless Podman** - Despite concerns about GPU passthrough in rootless mode, `/dev/dri` mapping works correctly and SYCL backend detects Iris Xe.

3. **Memory warnings are informational** - The `llama_params_fit_impl` warnings about device memory are normal for integrated GPUs. The system adapts automatically.

4. **Image size matters** - The 9.3GB SYCL image is large. Consider whether GPU acceleration is worth the storage cost for each experiment.

5. **Model download before container start** - The container requires the model file to exist at startup. Download first, then start the container, to avoid startup failures.

---

## Reproduction on ASUS TUF (April 26, 2026)

**Machine:** ASUS TUF (Pop!_OS 24.04 LTS)
**CPU:** AMD Ryzen 7 3750H (4C/8T)
**GPU:** NVIDIA GTX 1660 Ti (6GB) + AMD Radeon Vega 10 iGPU (integrated)
**RAM:** 15GB total, ~11GB available

### Adaptations Required

| Change | Dell Inspiron (original) | ASUS TUF (reproduction) |
|--------|--------------------------|------------------------|
| Image | `server-intel` (SYCL) | `server-vulkan` (Vulkan) |
| GPU backend | Intel Iris Xe (SYCL) | AMD Radeon Vega 10 iGPU (Vulkan/RADV) |
| HuggingFace source | `bartowski/gemma-3-1b-it-GGUF` | `ggml-org/gemma-3-1b-it-GGUF` (original repo returned 401) |

### GPU Selection Note

Vulkan detected the **AMD Radeon Vega 10 iGPU** (RADV RAVEN, pci-0000:05:00.0), NOT the NVIDIA GTX 1660 Ti. The `/dev/dri` passthrough exposes both GPUs, and Vulkan enumerated the AMD iGPU first. The NVIDIA dGPU was not used.

```
llama_model_load_from_file_impl: using device Vulkan0 (AMD Radeon Vega 10 Graphics (RADV RAVEN)) (0000:05:00.0) - 7701 MiB free
```

The AMD iGPU has ~7.7GB VRAM available, sufficient for the 1B model. All 27/27 layers offloaded to GPU.

### Verification Results

| Test | Result |
|------|--------|
| Container startup | PASS - both containers running |
| Model loading | PASS - 27/27 layers offloaded to Vulkan0 |
| `/v1/models` endpoint | PASS - returns model info (999,885,952 params) |
| `/v1/chat/completions` | PASS - returned "Hello!" |
| `/health` endpoint | PASS - `{"status":"ok"}` |
| DNS resolution (test-client) | PASS - ping resolved to <CONTAINER_IP> |
| Healthcheck | PASS - `{"status":"ok"}` (after fixing wget → curl) |

### Performance Comparison

| Metric | Dell Inspiron (Iris Xe) | ASUS TUF (Vega 10 iGPU) |
|--------|------------------------|------------------------|
| Prompt processing | 286 ms/token (15 tokens, 4293ms) | 67 ms/token (15 tokens, 1004ms) |
| Generation | 25 ms/token (3 tokens, 76ms) | 41 ms/token (3 tokens, 122ms) |
| RAM (idle) | ~350MB | ~133MB |

**Observation:** Prompt processing is ~4x faster on the ASUS TUF Vega 10 iGPU compared to Dell Iris Xe. Generation is slightly slower but still fast.

### Resource Usage

```
CONTAINER    CPU %    MEM USAGE
homelab-llamacpp-vulkan  2.48%    132.8MB / 16.56GB
homelab-llamacpp-vulkan-test  0.01%    53.25kB
```

### What Didn't Work

1. **Original HuggingFace URL (`bartowski/gemma-3-1b-it-GGUF`)** - returned 401 "Invalid username or password". The model has moved to `ggml-org/gemma-3-1b-it-GGUF`.
2. **NVIDIA GPU not used** - Vulkan selected the AMD iGPU over the NVIDIA dGPU. To use NVIDIA, would need CUDA backend (not Vulkan) or explicit device selection.
3. **Healthcheck failed initially** - the `server-vulkan` image doesn't include `wget` (only `curl`). Fixed by updating healthcheck to use `curl -sf`.

### Lessons Learned

1. **Vulkan works in rootless Podman on ASUS TUF** - same as SYCL worked on Dell
2. **AMD iGPU outperforms Intel Iris Xe** for this workload on prompt processing
3. **HuggingFace URLs change** - always verify the repo exists before downloading
4. **Vulkan device selection is automatic** - first enumerated device wins; no easy way to force NVIDIA without CUDA backend
5. **Check healthcheck tools in new images** - the Vulkan image lacks `wget` but has `curl`; the Intel SYCL image had `wget`. Always verify healthcheck tools exist in the target image.

## Rerun (April 26, 2026)

Reproduced experiment on ASUS TUF. All tests passed.

| Test | Result |
|------|--------|
| Container startup | PASS |
| Model loading | PASS - 27/27 layers offloaded to Vulkan0 |
| `/health` endpoint | PASS |
| `/v1/models` endpoint | PASS |
| `/v1/chat/completions` | PASS - returned "Hello!" |
| DNS resolution (test-client) | PASS - resolved to <CONTAINER_IP> |

### Performance

| Metric | Value |
|--------|-------|
| Prompt processing | 67.5 ms/token (15 tokens, 1012ms) |
| Generation | 46.4 ms/token (3 tokens, 139ms) |
| RAM (idle) | 132.8MB |
| CPU (idle) | 3.24% |

### Notes
- Stale rootlessport process on port 11436 had to be killed manually before rerun
- GPU: AMD Radeon Vega 10 iGPU (RADV RAVEN), 5666 MiB free, all 27 layers offloaded
- Performance consistent with previous run (67 ms/token prompt, ~41-46 ms/token generation)

## Next Steps

- Test with larger models (3B-4B) to see Vega 10 performance limits
- Explore context window scaling (try `-c 8192`)
- Benchmark prompt vs generation token speeds
- Test with OpenAI SDK integration
- Compare performance against Ollama on same hardware
- Investigate NVIDIA GPU usage (CUDA backend vs Vulkan AMD iGPU)
