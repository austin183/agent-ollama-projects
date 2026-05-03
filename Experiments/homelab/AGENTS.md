# OpenCode Agent Instructions

## Container Runtime

- **Use `podman compose`, not `docker compose`** - This repo uses Podman (rootless containers)
- Commands are identical syntax: `podman compose up -d`, `podman compose down`, etc.
- Containers run without sudo; volumes are in `~/.local/share/containers/storage/volumes/`

## Repository Structure

```
~/homelab/
├── prerequisites/            # Host setup guide + verification tests
│   ├── README.md
│   └── tests/
│       └── docker-compose.yml
├── infrastructure/           # Active services
│   ├── adguard-home/         # Currently deployed (DNS ad-blocking)
│   └── sftp/                 # SFTP server
├── distributed-computing/    # BOINC client (planned)
├── agent_docs/               # Plans, learnings, and debriefs
│   ├── plans/
│   └── learnings/
└── ideas/                    # Design docs and experiment planning
    ├── experiments.md        # Master plan for all experiment domains
    └── experiments-asus-timeline.md  # ASUS TUF experiment results tracking
```

## Pre-flight Checklist

Before starting any experiment:

1. Check for port conflicts: `ss -tlnp | grep <port>`
2. Clean stale containers: `podman compose down`
3. Verify image tags (avoid `:latest` for databases)
4. Confirm rootless port limitations (ports < 1024 need special config)
5. Check if service needs a setup wizard (config files don't exist until wizard completes)

## Container Configuration Best Practices

### Use Dockerfiles Over Volume Mounts for Config
- **Bake static configs into custom images** rather than mounting config files
- Use volume mounts only for:
  - User data that persists across container rebuilds
  - Runtime-generated files
- Benefits: cleaner compose files, reproducible builds, fewer mount points

### Avoid Hardcoded Secrets in Compose Files
- **Never embed passwords in `command` or `environment` fields directly**
- Use `.env` files loaded by compose (add to `.gitignore`)
- For the `atmoz/sftp` image, use `SFTP_USERS` environment variable instead of command-line format
- Reference: `infrastructure/sftp/lab.env.example`

### Test Client Convenience
- Include test scripts mounted to test containers for easy connectivity verification
- Use `podman exec <test-container> /test-connectivity.sh` for quick validation

## Key Constraints

### Current Machine: ASUS TUF (Pop!_OS 24.04 LTS)
- **CPU:** AMD Ryzen 7 3750H (4C/8T)
- **RAM:** 15GB total, ~8.5GB available; keep container usage under 10GB
- **Swap:** 19GB available
- **GPU:** NVIDIA GeForce GTX 1660 Ti (driver 580.119.02)
  - NVENC encoders: H.264, HEVC (1 instance)
  - CUVID decoders: H.264, HEVC, VP8, VP9 (8-bit), AV1
  - Use NVIDIA container toolkit for GPU passthrough
- **Previous machine (Dell Inspiron 5502):** 12GB RAM, Intel Iris Xe, Wi-Fi 6 only

## Critical Files to Read First

- `prerequisites/README.md` - Podman setup, UFW config, troubleshooting
- `ideas/experiments.md` - Full experiment catalog with resource budgets
- `infrastructure/adguard-home/docker-compose.yml` - Reference for current implementation

## Common Pitfalls

- Port 53 (DNS) requires `cap_add: NET_ADMIN` in compose files
- Rootless containers can't bind ports < 1024 without special config; use high ports
- BOINC requires `network_mode: host` which has rootless limitations
- Always check `podman ps` not `docker ps`
- **Podman-compose `depends_on` is unreliable for DB startup ordering**; use `pg_isready` wait loops in compose `command`
- **Environment variables may not modify runtime config** — check the container's entrypoint and init script directories
- **Always run `podman compose down -v` when changing init scripts**; stale data causes silent failures
- **Single-quoted heredocs in compose commands don't expand variables**; use `echo` statements instead

## Scientific Process Directives
- Favor Trial and Error over overthinking Hypotheses
