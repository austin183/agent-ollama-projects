# llama.cpp Local LLM Serving

**Experiment:** 4B - Replace Ollama with llama.cpp  
**Phase:** 5 (AI/ML)  
**Status:** Complete

---

## Overview

Runs llama.cpp's `llama-server` with Intel Iris Xe GPU acceleration (SYCL backend) to serve GGUF models via an OpenAI-compatible API. Used as a lighter-weight alternative to Ollama for local LLM inference.

## Quick Start

```bash
cd ~/homelab/ai-inference/llamacpp-vulkan
podman compose up -d
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| llamacpp-vulkan | 11436 | OpenAI-compatible API (OpenAI format) |
| test-client | — | Connectivity testing |

## How It Works

```
Client (curl, API client, Web UI)
    │
    │  HTTP POST to http://localhost:11436/v1/chat/completions
    │
    ▼
llama-server (container: homelab-llamacpp-vulkan)
    │
    ├── /dev/dri → Intel Iris Xe GPU (SYCL backend)
    ├── /models/gemma-3-1b-it-Q4_K_M.gguf → GGUF model (~770MB)
    │
    ├── /v1/chat/completions  (OpenAI-compatible)
    ├── /v1/models             (model listing)
    └── /                      (Web UI)
```

**Data flow:**
1. Client sends HTTP POST to `http://localhost:11436/v1/chat/completions`
2. llama-server loads GGUF model from bind-mounted `/models` directory
3. Inference runs on Intel Iris Xe GPU (SYCL) + CPU (AVX512)
4. Response returned as JSON in OpenAI-compatible format

---

## Quick Start

```bash
# Start the service
cd ~/homelab/ai-inference/llamacpp-vulkan
podman compose up -d

# Check status
podman ps | grep llamacpp-vulkan
```

---

## Verification Commands

### Check service is running
```bash
podman ps | grep homelab-llamacpp-vulkan
```

### Verify SYCL GPU backend
```bash
podman logs homelab-llamacpp-vulkan | grep -i sycl
```

**Expected output:**
```
load_backend: loaded SYCL backend from /app/libggml-sycl.so
... using device SYCL0 (Intel(R) Iris(R) Xe Graphics)
```

### List available models
```bash
curl -s http://localhost:11436/v1/models | python3 -m json.tool
```

**Expected output:**
```json
{
  "object": "list",
  "data": [
    {
      "id": "gemma-3-1b-it-Q4_K_M.gguf",
      "owned_by": "llamacpp"
    }
  ]
}
```

### Test chat completion
```bash
curl -s -X POST http://localhost:11436/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gemma-3-1b-it-Q4_K_M.gguf","messages":[{"role":"user","content":"Say hello in one word."}]}' | python3 -m json.tool
```

**Expected output:**
```json
{
  "choices": [{
    "message": {"role": "assistant", "content": "Hello!"}
  }],
  "object": "chat.completion"
}
```

### Test Web UI
```bash
open http://localhost:11436
```

### Test from another container (DNS resolution)
```bash
podman exec homelab-llamacpp-vulkan-test ping -c 2 llamacpp-vulkan
podman exec homelab-llamacpp-vulkan-test wget -qO- http://llamacpp-vulkan:8080/health
```

### Check resource usage
```bash
podman stats --no-stream homelab-llamacpp-vulkan
```

**Typical usage:** ~350MB RAM, 0-40% CPU (during inference)

---

## Adding New Models

Download GGUF models to the `models/` directory:

```bash
cd ~/homelab/ai-inference/llamacpp-vulkan/models

# Download a new model
curl -L -o phi-3.5-mini-instruct-Q4_K_M.gguf \
  "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf"

# Restart with new model
podman compose stop llamacpp-vulkan
# Edit docker-compose.yml command field to point to new model
podman compose up -d llamacpp-vulkan
```

---

## API Compatibility

llama.cpp uses the OpenAI-compatible API format, so any tool that works with OpenAI or Ollama should work:

```python
# Using OpenAI Python SDK
from openai import OpenAI

client = OpenAI(base_url="http://localhost:11436/v1", api_key="na")
response = client.chat.completions.create(
    model="gemma-3-1b-it-Q4_K_M.gguf",
    messages=[{"role": "user", "content": "Hello!"}]
)
print(response.choices[0].message.content)
```

---

## Common Pitfalls

### Port conflict with Ollama
This experiment uses port **11436** (same as Ollama). Do not run both experiments simultaneously.

### GPU not detected
If SYCL backend fails, check:
```bash
ls -la /dev/dri
podman logs homelab-llamacpp-vulkan | grep -i "sycl\|error\|fail"
```

### Model not loading
The container requires the model file to exist at startup. If the model is missing:
```bash
podman compose down -v
# Download model to ./models/
podman compose up -d
```

### High prompt latency
First prompt is slow (~4s for 15 tokens) due to prompt processing. Subsequent prompts are faster. This is normal for GGUF models.

---

## Architecture Notes

- **Image:** `ghcr.io/ggml-org/llama.cpp:server-intel` (9.31GB) - Official SYCL GPU variant
- **Model:** Gemma 3 1B (Q4_K_M quantization) - ~770MB, ~1.3GB RAM when loaded
- **GPU:** Intel Iris Xe via SYCL backend (not OpenCL)
- **CPU:** AVX512 acceleration on i5-1135G7
- **Context window:** 4096 tokens (configurable via `-c` flag)
- **API:** OpenAI-compatible (`/v1/chat/completions`, `/v1/models`, `/embedding`)

---

## Resource Budget

| Resource | Budget | Actual |
|----------|--------|--------|
| RAM | ~2-3GB | ~350MB idle |
| Storage | ~2GB (model) | ~770MB (model) + 9.3GB (image) |
| CPU | 2-4 threads | 4 threads (2 during idle, up to 8 during inference) |
| GPU | Iris Xe (SYCL) | SYCL0 detected and used |

---

## Cleanup

```bash
podman compose down -v
```
