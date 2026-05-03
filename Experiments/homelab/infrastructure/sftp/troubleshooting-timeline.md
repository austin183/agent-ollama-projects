# SFTP Container Troubleshooting Timeline

## Date: 2026-04-16

### Initial State
- Container: `docker.io/atmoz/sftp:alpine`
- User: `labratorian:ChangeMe`
- Port: 2222:22
- Test client: Alpine container with openssh-client

---

## Issue 1: SSH Host Keys Missing

**Symptom:** `sshd: no hostkeys available -- exiting.`

**Root Cause:** Volume mount `./config:/etc/sftp` was creating an empty directory that interfered with the container's SSH key generation in `/etc/ssh/`.

**Fix:** Removed the `./config:/etc/sftp` volume mount entirely.

**Date:** 2026-04-16 20:36

---

## Issue 2: Invalid User Command Syntax

**Symptom:** `ERROR: Invalid GID "/home/labratorian/files", do not match required regex pattern: [[:digit:]]*`

**Root Cause:** Command format `labratorian:ChangeMe::/home/labratorian/files` was missing UID and GID. The `atmoz/sftp` image expects `user:password:uid:gid:home`.

**Fix:** Changed command to `labratorian:ChangeMe:1000:1000:/home/labratorian/files`

**Date:** 2026-04-16 20:41

---

## Issue 3: Password Authentication Disabled

**Symptom:** `Permission denied (publickey,password,keyboard-interactive)` despite correct password.

**Root Cause:** The `atmoz/sftp` image disables password authentication by default for security.

**Fix:** Created `/home/labratorian/homelab/infrastructure/sftp/config/auth.conf` with `PasswordAuthentication yes` and mounted it to `/etc/ssh/sshd_config.d/auth.conf:ro`

**Date:** 2026-04-16 20:44

---

## Issue 4: Incorrect Home Path in Command

**Symptom:** `Creating directory: /home/labratorian//home/labratorian/files` (double path)

**Root Cause:** Using absolute path `/home/labratorian/files` in the command when the user's home is already `/home/labratorian`. The image appends the path to the home directory.

**Fix:** Changed command to use relative path: `labratorian:ChangeMe:1000:1000:/files`

**Date:** 2026-04-16 20:57

---

## Issue 5: Volume Mount Path Mismatch

**Symptom:** `/files` directory not found in container

**Root Cause:** Volume was mounted to `/home/labratorian/files` but command expected `/files`.

**Fix:** Changed volume mount from `./data:/home/labratorian/files` to `./data:/files`

**Date:** 2026-04-16 20:58

---

## Issue 6: Broken PAM Configuration

**Symptom:** SSH authentication failed with "Permission denied" despite correct password. Server logs showed `Failed password for labratorian` even when password was correct.

**Root Cause:** The `/etc/pam.d/sshd` file referenced `base-auth`, `base-account`, `base-password`, and `base-session` which don't exist in Alpine Linux. This caused PAM authentication to fail silently.

**Fix:** Created `/home/labratorian/homelab/infrastructure/sftp/config/sshd.pam` with proper PAM configuration:
```
auth       required      pam_unix.so
account    required      pam_unix.so
password   required      pam_unix.so
session    required      pam_unix.so
```

Mounted it to `/etc/pam.d/sshd:ro` in docker-compose.yml.

**Date:** 2026-04-17 05:25

---

## Issue 7: Volume Path Mismatch (Second Occurrence)

**Symptom:** After PAM fix, SSH worked but SFTP subsystem still failed.

**Root Cause:** Volume was mounted to `/files` but user home is `/home/labratorian`. The `atmoz/sftp` image expects volumes to be mounted relative to the user's home directory (`/home/<user>/<path>`).

**Fix:** Changed volume mount from `./data:/files` to `./data:/home/labratorian/files`

**Date:** 2026-04-17 05:30

---

## Current Status (2026-04-17 05:35) - WORKING

The SFTP server is now fully functional:
- SSH authentication works with password `ChangeMe`
- SFTP connections work in interactive mode
- Users are chrooted to `/home/labratorian/files`
- File uploads/downloads work correctly

### Working Test Command:
```bash
sshpass -p "ChangeMe" sftp -o StrictHostKeyChecking=no labratorian@sftp
```

### Current docker-compose.yml
```yaml
version: '3.8'

services:
  sftp:
    image: docker.io/atmoz/sftp:alpine
    container_name: homelab-sftp
    restart: unless-stopped
    ports:
      - "2222:22/tcp"
    volumes:
      - ./data:/home/labratorian/files
      - ./config/auth.conf:/etc/ssh/sshd_config.d/auth.conf:ro
      - ./config/sshd.pam:/etc/pam.d/sshd:ro
    environment:
      - TZ=America/New_York
    networks:
      - sftp-network
    healthcheck:
      test: ["CMD", "ssh", "-o", "BatchMode=yes", "-p", "22", "labratorian@localhost", "echo alive"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    command: "labratorian:ChangeMe:1000:1000:/files"

  test-client:
    image: docker.io/alpine:latest
    container_name: homelab-sftp-test
    command: sleep 3600
    networks:
      - sftp-network
    depends_on:
      - sftp
    entrypoint: ["/bin/sh", "-c", "apk add --no-cache openssh-client sshpass && sleep 3600"]

networks:
  sftp-network:
    driver: bridge
    name: homelab-sftp-network
```

## Summary of All Issues
1. **SSH Host Keys Missing** - Removed interfering volume mount
2. **Invalid User Command Syntax** - Added UID:GID to command
3. **Password Authentication Disabled** - Added auth.conf mount
4. **Incorrect Home Path in Command** - Changed to relative path `/files`
5. **Volume Mount Path Mismatch** - Aligned volume with user home
6. **Broken PAM Configuration** - Replaced with working pam_unix.so config
7. **Volume Path Mismatch (v2)** - Mounted to `/home/labratorian/files` instead of `/files`
8. **Rootless Podman UID Mapping** - Switched to named volume to avoid UID translation issues
9. **Nested Directory Structure** - Used `SFTP_USERS` with `:files` suffix for proper ownership

---

## Issue 8: Rootless Podman UID Mapping

**Symptom:** Files uploaded via SFTP appeared in the container but were not visible on the host filesystem.

**Root Cause:** Rootless Podman uses UID mapping (user's UID 1000 maps to 101000 inside containers). When using bind mounts, the container's UID 1000 user writes to a location that doesn't correspond to the host's directory structure.

**Fix:** Switched from bind mount to named volume to let Podman manage the UID mapping:
```yaml
volumes:
  - sftp-data:/home/labratorian

volumes:
  sftp-data:
```

**Date:** 2026-04-17 18:00

---

## Issue 9: Nested Directory Structure

**Symptom:** Files were stored at `/home/labratorian/home/labratorian/<filename>` instead of directly in the volume.

**Root Cause:** The `atmoz/sftp` image creates the user's home directory inside the mounted volume. Mounting to `/home/labratorian` resulted in the image creating `/home/labratorian/home/labratorian/`.

**Fix:** Used `SFTP_USERS` environment variable with `:files` suffix to create a properly-owned subdirectory:
```yaml
environment:
  - SFTP_USERS=labratorian:ChangeMe:1000:1000:files
volumes:
  - ./data:/home/labratorian
```

This tells the image to create a `files` subdirectory with correct ownership (UID 1000) inside the mounted volume.

**Date:** 2026-04-17 18:12

---

## Final Working Configuration (2026-04-17 18:15)

The SFTP server is now fully functional with files stored in `./data/files/`:

### Current docker-compose.yml
```yaml
version: '3.8'

services:
  sftp:
    image: docker.io/atmoz/sftp:alpine
    container_name: homelab-sftp
    restart: unless-stopped
    ports:
      - "2222:22/tcp"
    volumes:
      - ./data:/home/labratorian
      - ./config/auth.conf:/etc/ssh/sshd_config.d/auth.conf:ro
      - ./config/sshd.pam:/etc/pam.d/sshd:ro
    environment:
      - TZ=America/New_York
      - SFTP_USERS=labratorian:ChangeMe:1000:1000:files
    networks:
      - sftp-network
    healthcheck:
      test: ["CMD", "ssh", "-o", "BatchMode=yes", "-p", "22", "labratorian@localhost", "echo alive"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s

  test-client:
    image: docker.io/alpine:latest
    container_name: homelab-sftp-test
    command: sleep 3600
    networks:
      - sftp-network
    depends_on:
      - sftp
    entrypoint: ["/bin/sh", "-c", "apk add --no-cache openssh-client sshpass && sleep 3600"]

networks:
  sftp-network:
    driver: bridge
    name: homelab-sftp-network
```

### Key Learnings
- The `SFTP_USERS` environment variable with `:files` suffix creates a properly-owned directory for the SFTP user
- Files are stored at `./data/files/` on the host
- The `test-connectivity.sh` script was updated to `cd /files` before file operations

### Experiment Complete
All SFTP functionality verified:
- ✓ Container starts with podman compose
- ✓ SSH authentication works
- ✓ SFTP file upload works
- ✓ SFTP file download works
- ✓ Files persist on host in `./data/files/`
- ✓ Test script works
