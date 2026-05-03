---
name: running-container-experiments
description: Set up, run, and reproduce container experiments with Podman compose. Use when creating new experiments, reproducing existing ones, or debugging containerized services on the homelab.
---

# Running Container Experiments

Set up, run, and reproduce `docker-compose.yml` experiments on the homelab using Podman rootless containers.

## What Are You Doing?

**Creating a new experiment from scratch?**
See [reference/building.md](reference/building.md) for compose templates, patterns, and architecture guidance.

**Running or reproducing an existing experiment?**
See [reference/executing.md](reference/executing.md) for the execution workflow, verification steps, and debugging patterns.

**Documenting results?**
See [reference/documenting.md](reference/documenting.md) for timeline entries, README structure, and cleanup of generated artifacts.

---

## Hardware Constraints

| Resource | Available | Max Usage | Notes |
|----------|-----------|-----------|-------|
| RAM | 15 GB | ~10 GB | Keep 30% headroom for host |
| Storage | 225 GB free | 50-75 GB | Budget per experiment |
| CPU | 8 threads (AMD Ryzen 7 3750H) | 4-6 active | Background tasks need room |
| GPU | NVIDIA GTX 1660 Ti | Use NVIDIA toolkit | NVENC H.264/HEVC, CUVID decoders |
| Network | Ethernet available | No Wi-Fi limitation | Network-intensive tests OK |

## Pre-flight Checklist

Before starting any experiment:

- [ ] Check for port conflicts: `ss -tlnp | grep <port>`
- [ ] Remove stale volumes: `podman compose down -v`
- [ ] Verify image tags (avoid `:latest` for databases)
- [ ] Confirm rootless port limitations (< 1024 need special config)
- [ ] Check if service needs setup wizard (config files don't exist until wizard completes)
- [ ] `cd` into experiment directory first (compose won't find files from parent)

## Commands Reference

```bash
# Start experiment
podman compose up -d

# Start with custom builds
podman compose up -d --build

# View logs
podman logs -f homelab-<service>

# Check health status
podman inspect homelab-<service> --format '{{.State.Health.Status}}'

# Execute command in container
podman exec -it homelab-<experiment>-test sh

# Monitor resources
podman stats --filter name=homelab-<experiment>

# Stop experiment
podman compose down

# Stop and remove data
podman compose down -v
```

## Key Constraints

- **Use `podman compose`, not `docker compose`** — rootless containers
- **Containers run without sudo** — volumes in `~/.local/share/containers/storage/volumes/`
- **Each experiment gets its own directory** with isolated network
- **Track results** in `experiment-timeline.md` per experiment — see the documenting phase for guidance

## Common Pitfalls

- Port 53 (DNS) requires `cap_add: NET_ADMIN`
- Rootless containers can't bind ports < 1024 without special config
- BOINC requires `network_mode: host` which has rootless limitations
- Podman-compose `depends_on` is unreliable for DB startup ordering — use wait loops
- Environment variables may not modify runtime config — check entrypoint scripts
- Always run `podman compose down -v` when changing init scripts — stale data causes silent failures
- Single-quoted heredocs in compose commands don't expand variables — use `echo` statements
