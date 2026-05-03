# SFTP Experiment - Simplification Timeline

**Date:** April 24, 2026  
**Experiment:** `infrastructure/sftp`  
**Phase 3 Flag:** No (no secret extraction needed)

---

## Setup Phase

### Changes Applied

**Phase 1 - Trivial Cleanup:**
- Removed `version: '3.8'` line (deprecated in modern compose)
- Removed dead `sftp-data` named volume declaration (not used - data uses bind mount `./data:/home/labratorian`)

**Phase 2 - Test-Client Standardization:**
- Test-client was already named `test-client` with container_name `homelab-sftp-test`
- Pinned `alpine:latest` → `alpine:3.21` (was the only change needed)

**Phase 4 - Network Naming:**
- Renamed internal network key from `sftp-network` → `homelab-sftp-network`
- Removed redundant `name: homelab-sftp-network` field (Podman creates the network with the key name by default)
- Updated both service references (`sftp` and `test-client`) to use new network key

**Phase 6 - Port Conflicts:**
- Port 2222 already matches target allocation in plan (no changes needed)

**Phase 8 - README:**
- Restructured to follow standard template
- Added Overview, Services table, Testing section, Troubleshooting, Cleanup
- Removed outdated "Status: Phase 1 (Foundation)" header
- Removed "Maintenance" and "Next Steps" sections (not needed for active experiment)

---

## Verification Phase

### Pre-flight

```bash
# Check port is not in use
ss -tlnp | grep 2222
```

### Podman Compose

```bash
cd ~/homelab/infrastructure/sftp
podman compose down -v
podman compose up -d
podman ps
```

Expected output:
```
CONTAINER ID  IMAGE                              COMMAND         CREATED        STATUS        PORTS                   NAMES
<id>          docker.io/atmoz/sftp:alpine        /init           <time> ago   Up <time>     0.0.0.0:2222->22/tcp    homelab-sftp
<id>          docker.io/alpine:3.21              sleep 3600      <time> ago   Up <time>                            homelab-sftp-test
```

### Connectivity Tests

```bash
# Test SFTP from host
sftp labratorian@localhost -p 2222
# Password: ChangeMe

# Test DNS resolution from test-client
podman exec homelab-sftp-test nslookup sftp

# Test SSH connectivity from test-client
podman exec -it homelab-sftp-test ssh -p 22 -o StrictHostKeyChecking=no labratorian@sftp
```

---

## Architecture Explanation

### How `atmoz/sftp` Works

The `atmoz/sftp` image is a minimalist SFTP server that:

1. **User provisioning**: Reads `SFTP_USERS` env var at startup in format `username:password:uid:gid:directory`
2. **SSH key generation**: Generates host keys on first boot (stored in container filesystem)
3. **Chroot behavior**: Users are chrooted to their home directory (`/home/labratorian` in this case)
4. **Stateless design**: All configuration is via env vars/volumes, no database or config files needed

### Data Flow

```
Host ./data → /home/labratorian (bind mount)
Host ./config/auth.conf → /etc/ssh/sshd_config.d/auth.conf (read-only)
Host ./config/sshd.pam → /etc/pam.d/sshd (read-only)
```

The bind mount strategy means:
- User data persists across container rebuilds
- Config files are editable on the host without rebuilding
- No named volumes needed for this use case

---

## Design Decisions

### Why bind mount instead of named volume?

The `./data` directory is a bind mount because:
- User files need to be easily accessible from the host
- Backup and management is simpler with a known host path
- No need for Podman to manage the volume lifecycle

### Why `SFTP_USERS` env var instead of command-line format?

Per AGENTS.md, the `SFTP_USERS` environment variable is the preferred method for the `atmoz/sftp` image. The command-line format (`labratorian:ChangeMe:1000:1000:files`) is still supported but the env var is cleaner and documented.

### Why network key `homelab-sftp-network`?

Consistent naming convention across all experiments. The `homelab-*` prefix makes it clear which network belongs to homelab services. The redundant `name:` field was dropped because Podman compose uses the key name as the network name by default.

### Why keep `alpine:latest` test-client as `alpine:3.21`?

Pinning to a specific version ensures reproducible builds. The test-client uses `apk add` to install openssh-client and sshpass, so the exact Alpine version matters for package availability.

---

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references (docker.io/atmoz/sftp:alpine)
- [x] Ports are > 1024 (2222)
- [x] Test client container included (homelab-sftp-test)
- [x] Healthcheck port matches service config (port 22 internal)
- [x] Volumes use hybrid strategy (bind mount for data)
- [x] Network name follows homelab-* pattern (homelab-sftp-network)
- [x] README includes wizard steps (N/A - no wizard)
- [x] Verification commands documented
- [x] Expected output samples provided
```

---

## Common Questions

### Q: How do I add a new user?
A: Add to `SFTP_USERS` env var with colon-separated format:
```yaml
environment:
  - SFTP_USERS=labratorian:password1:1000:1000:files,bob:password2:1001:1001:files
```
Then `podman compose down -v && podman compose up -d` (user data is stateless).

### Q: Can I use SSH keys instead of passwords?
A: Yes, mount authorized_keys files in the user's home directory. The `atmoz/sftp` image supports this but requires additional SSH config.

### Q: Why is the healthcheck using port 22 internally?
A: The healthcheck runs inside the container and connects to localhost:22 (the container's internal SFTP port). It uses `ssh -o BatchMode=yes` to avoid password prompts.

### Q: What happens to data when I run `podman compose down -v`?
A: Named volumes are removed, but bind mounts (`./data`) are NOT affected. Your user files in `./data/` will persist.

---

## Lessons Learned

### What worked well:
- The `atmoz/sftp` image is simple and reliable
- Bind mount strategy for data is straightforward
- Test-client with openssh-client and sshpass is useful for connectivity testing
- Network naming change was clean with no side effects

### What could be improved:
- The README originally had outdated sections ("Status: Phase 1") that should be removed
- Consider adding a `.env` file for the password even though Phase 3 flag was "No" - makes it easier to change passwords without editing compose files
- The healthcheck connects to port 22 inside the container, but if the image changes its internal port, the healthcheck would need updating

### What didn't work:
- N/A - no dead ends encountered for this experiment

---

## Resource Usage

| Resource | Usage | Budget |
|----------|-------|--------|
| RAM | ~15-25 MB | 8-9 GB |
| Storage | ~5 MB image + data dir | 50-75 GB |
| CPU | < 1% idle | 4-6 threads |

SFTP is a lightweight service with minimal resource footprint.
