# llama.cpp Local LLM Serving (CUDA/NVIDIA)

**Experiment:** 4B-cuda - llama.cpp with NVIDIA GPU acceleration  
**Phase:** 5 (AI/ML)  
**Status:** In Progress

---

## Overview

Runs llama.cpp's `llama-server` with NVIDIA CUDA GPU acceleration to serve GGUF models via an OpenAI-compatible API. Uses the GTX 1660 Ti dGPU for inference, providing better performance than the AMD iGPU Vulkan path.

## Quick Start

```bash
cd ~/homelab/ai-inference/llamacpp-cuda
podman compose up -d
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| llamacpp | 11437 | OpenAI-compatible API (CUDA backend) |
| test-client | — | Connectivity testing |

## How It Works

```
Client (curl, API client, Web UI)
    │
    │  HTTP POST to http://localhost:11437/v1/chat/completions
    │
    ▼
llama-server (container: homelab-llamacpp-cuda)
    │
    ├── nvidia.com/gpu=all → NVIDIA GTX 1660 Ti (CUDA)
    ├── /models/gemma-3-1b-it-Q4_K_M.gguf → GGUF model (~770MB)
    │
    ├── /v1/chat/completions  (OpenAI-compatible)
    ├── /v1/models             (model listing)
    └── /                      (Web UI)
```

## Verification Commands

### Check service is running

```bash
podman ps | grep homelab-llamacpp-cuda
```

### Verify CUDA GPU backend

```bash
podman logs homelab-llamacpp-cuda | grep -i cuda
```

### List available models

```bash
curl -s http://localhost:11437/v1/models | python3 -m json.tool
```

### Test chat completion

```bash
curl -s -X POST http://localhost:11437/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gemma-3-1b-it-Q4_K_M.gguf","messages":[{"role":"user","content":"Say hello in one word."}]}' | python3 -m json.tool
```

### Test from another container

```bash
podman exec homelab-llamacpp-cuda-test ping -c 2 llamacpp
podman exec homelab-llamacpp-cuda-test wget -qO- http://llamacpp:8080/health
```

### Check resource usage

```bash
podman stats --no-stream homelab-llamacpp-cuda
```

## Cleanup

```bash
podman compose down -v
```
