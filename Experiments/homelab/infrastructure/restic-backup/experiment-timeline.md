# Restic Backup Experiment - Timeline

**Experiment:** 7B - Restic Backup System  
**Started:** April 20, 2026  
**Completed:** April 20, 2026  
**Phase:** 6 (DevOps)  
**Status:** Core functionality verified (backup + restore working)

## Setup Phase

### Step 1: Directory Structure
Created `~/homelab/infrastructure/restic-backup/` with subdirectories:
- `source-data/` - Files to back up (contains `sample-file.txt`)
- `backup-repo/` - Restic repository (local cache)
- `ssh-config/` - SSH keys and known_hosts
- `README.md` - Documentation
- `docker-compose.yml` - Container configuration
- `setup.sh` - One-time setup script
- `.env` - RESTIC_PASSWORD (gitignored)
- `.env.example` - Template
- `.gitignore` - Excludes secrets and data

### Step 2: Docker Compose Configuration
Created `docker-compose.yml` with two services:
- `restic-backup` - Main backup container using `docker.io/restic/restic:latest`
- `backup-test` - Alpine test client for connectivity verification

**Design decisions:**
- SFTP repository: `sftp://labratorian@<YOUR_INTERNAL_IP>:2222/backups/repo`
- SSH key authentication for reliable container-to-SFTP connection
- `extra_hosts` to ensure SFTP server resolves correctly in rootless Podman
- `command` runs `restic backup /source` then `restic snapshots` on startup
- No cron for now — manual runs first to verify everything works

### Step 3: SSH Key Generation
Generated ed25519 SSH key pair via `setup.sh`:
- Private key: `ssh-config/id_rsa` (gitignored)
- Public key: `ssh-config/id_rsa.pub` (not gitignored — harmless)
- `known_hosts` created with SFTP server's host key

### Step 4: Adding Public Key to SFTP Server
The SFTP server (`atmoz/sftp:alpine`) only allows SFTP protocol, not SSH shell access. Attempted multiple approaches:

**Approach 1: `sshpass` via `setup.sh` (failed)**
```bash
sshpass -p ChangeMe ssh -p 2222 labratorian@<YOUR_INTERNAL_IP> "cat >> ~/.ssh/authorized_keys"
```
Result: `ssh` connects but prints "This service allows sftp connections only." — no shell access.

**Approach 2: Alpine container with `sshpass` (failed)**
Tried running sshpass inside an Alpine container via `podman run`, but nested heredocs caused quoting issues:
```
sh: sshpass: not found
```
Even with `apk add sshpass`, the inline `sh -c` with mixed quoting of environment variables and heredocs failed silently.

**Approach 3: Helper scripts written to temp files (partial failure)**
Wrote scripts to temp files to avoid quoting issues. The script ran but still hit the "sftp connections only" error because it tried to use `ssh` to add the key.

**Approach 4: Copy into SFTP container (SUCCESS)**
Since the SFTP container is already running on the same host, used `podman cp` and `podman exec` to work inside it:
```bash
podman cp ssh-config/id_rsa.pub homelab-sftp:/tmp/id_rsa.pub
podman exec homelab-sftp sh -c '
    mkdir -p /home/labratorian/.ssh && chmod 700 /home/labratorian/.ssh
    cat /tmp/id_rsa.pub >> /home/labratorian/.ssh/authorized_keys && chmod 600 /home/labratorian/.ssh/authorized_keys
    rm -f /tmp/id_rsa.pub
'
```
This worked because the SFTP container's internal SSH daemon accepts SSH connections (it just restricts external ones to SFTP only).

### Step 5: Restic Repository Initialization
**Attempt 1: Wrong image name (failed)**
Used `vaughnrestic/restic:latest` from the original experiment plan. Docker Hub returned 404 — this image doesn't exist.

**Attempt 2: Wrong image name with full reference (failed)**
Used `docker.io/vaughnrestic/restic:latest` — same result, repository access denied.

**Attempt 3: Correct image, wrong command (failed)**
Found the official image is `docker.io/restic/restic:latest`. Ran:
```bash
podman run --rm docker.io/restic/restic:latest restic init
```
Result: `unknown command "restic" for "restic"` — the image's entrypoint IS `restic`, so calling `restic restic init` is wrong.

**Attempt 4: Correct image, correct command (SUCCESS)**
```bash
podman run --rm -e RESTIC_REPOSITORY=/tmp/test -e RESTIC_PASSWORD=test docker.io/restic/restic:latest init
```
Result: `created restic repository 9cf1fcaa7c at /tmp/test`

Final initialization command:
```bash
podman run --rm \
    -e RESTIC_REPOSITORY=sftp://labratorian@<YOUR_INTERNAL_IP>:2222/backups/repo \
    -e RESTIC_PASSWORD=ResticBackup2026!Secure \
    -e RESTIC_CACHE_DIR=/cache \
    -v ./ssh-config:/root/.ssh:ro \
    docker.io/restic/restic:latest init
```

## Verification Phase

### Connectivity Tests
- Tested SSH connectivity from SFTP test container: `sshpass -p ChangeMe ssh ...` → "This service allows sftp connections only" (expected)
- Verified SFTP protocol works: can upload files to SFTP server
- Created `known_hosts` file with `ssh-keyscan -p 2222 <YOUR_INTERNAL_IP>`

### Restic Repository
- Repository initialized successfully on SFTP server at `/backups/repo`
- SSH key-based auth configured for container → SFTP connection

### Issues Encountered
1. **SFTP server blocks SSH shell**: The `atmoz/sftp` container only allows SFTP protocol. Cannot use `ssh` to execute commands on the SFTP server. Must use `podman exec` on the SFTP container itself, or use SFTP protocol for file operations.

2. **`sshpass` not available in containers**: Alpine images don't include `sshpass` by default. Must `apk add sshpass` before use. The original plan assumed it was available on the host.

3. **Wrong Docker image**: The experiment plan specified `vaughnrestic/restic:latest` which doesn't exist. The correct image is `docker.io/restic/restic:latest`.

4. **Restic image entrypoint**: The `restic/restic` image has `restic` as its entrypoint. Commands like `restic init` become `restic init` (not `restic restic init`). This is different from the `vaughnrestic/restic` image which likely had a different entrypoint.

5. **Nested heredocs in shell scripts**: Mixing heredocs with variable expansion inside `podman run ... sh -c` is extremely fragile. The quoting layers make it nearly impossible to get right. Use temp files or direct `podman exec` instead.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  docker-compose.yml (self-contained experiment)             │
│                                                             │
│  ┌──────────────────────┐    ┌──────────────────────────┐  │
│  │  homelab-sftp        │    │  homelab-restic-backup   │  │
│  │  atmoz/sftp:alpine   │    │  restic/restic:latest    │  │
│  │  :2222:22/tcp        │    │  entrypoint: /bin/sh -c  │  │
│  │  Chroot: /home/labratorian│    │  SSH_ASKPASS auth        │  │
│  │  /backups/repo/      │◄───│  backup /source          │  │
│  │  (SFTP root)         │    │                          │  │
│  └──────────────────────┘    └──────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  homelab-restic-test (Alpine)                        │  │
│  │  sshpass, curl, restic, openssh-client installed     │  │
│  │  Mounts: source-data/, ssh-config/                   │  │
│  │  Used for: manual backup/restore tests               │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  Shared network: homelab-restic-network                    │
│  Shared volume: sftp-data (named volume for SFTP data)     │
└─────────────────────────────────────────────────────────────┘
```

### Key concepts
- **SFTP chroot**: `ChrootDirectory %h` means SFTP path `/` maps to container path `/home/labratorian`. A backup repo at `/backups/repo` via SFTP is actually `/home/labratorian/backups/repo` inside the container.
- **SSH_ASKPASS**: SSH only uses the askpass mechanism when `DISPLAY` is set. The askpass script must be executable and echo the password.
- **Docker network DNS**: Containers resolve each other by service name. The restic container connects to `sftp:22` (the service name), not `127.0.0.1:2222`.
- **Restarts**: The `restic-backup` service has `restart: "no"` — it runs once and exits. To re-run, start the container again with `podman compose up -d`.
┌─────────────────────────────────────────────────┐
│  homelab-restic-backup (restic/restic:latest)   │
│  ┌───────────────────────────────────────────┐  │
│  │  source-data/  →  restic backup → SFTP    │  │
│  │  Local files   │  encrypt/dedup  │ server  │  │
│  └───────────────────────────────────────────┘  │
│       ▲                     │                    │
│       │ read                │ SSH/sftp           │
│       └── bind mount ───────┘                    │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│  SFTP Server (atmoz/sftp:alpine)                │
│  Port: 2222 → /backups/repo/                    │
│  - Encrypted restic objects                      │
│  - Deduplicated storage                         │
│  - SSH key auth for restic container            │
└─────────────────────────────────────────────────┘
```

### Why this approach?

1. **Restic over other backup tools**:
    - Built-in deduplication saves space
    - AES-256 encryption by default
    - Works over SFTP (no new infrastructure needed)
    - Simple CLI, easy to verify manually

2. **Self-contained SFTP server**:
    - No dependency on external services
    - Each experiment is independent and reproducible
    - Reuses the proven `atmoz/sftp:alpine` image from the SFTP experiment

3. **SSH_ASKPASS for password auth**:
    - SSH_ASKPASS mechanism allows non-interactive password-based SSH
    - Required because restic's SFTP transport uses SSH internally
    - More reliable than trying to configure SSH keys with atmoz/sftp

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references
- [x] Ports are > 1024 (SFTP on 2222)
- [x] Test client container included (backup-test)
- [x] Volumes use hybrid strategy (named volume for SFTP data, bind mounts for source/ssh)
- [x] Network name follows homelab-* pattern (homelab-restic-network)
- [x] README includes setup steps
- [x] Verification commands documented
- [x] Expected output samples provided
- [x] SFTP server self-contained in docker-compose.yml
- [x] SSH_ASKPASS configured for password auth
- [x] known_hosts generated from Docker network
- [x] Restic repository initialized
- [x] First backup successful (from test container)
- [x] Restore test successful (from test container)
- [x] First backup from restic-backup container (compose integration SUCCESS)
- [ ] Scheduled backup verified
- [ ] Deduplication verified with multiple backups
- [ ] Retention policy tested with restic forget
```

## Common Questions

### Q: What happens if the SFTP server is down?
A: The backup will fail. Check logs with `podman logs homelab-restic-backup`. Consider adding a notification mechanism.

### Q: How much space do backups take?
A: Restic deduplicates, so only changed blocks are stored. For small source data (~100 bytes in sample), expect ~10-50MB on disk for the repo structure.

### Q: Can I access backups from the host?
A: The backup repo is stored on the SFTP server at `/backups/repo/`. The local `backup-repo/` is a cache for performance. Use `restic` CLI with the SFTP repository URL to manage backups from the host.

### Q: What if I lose the RESTIC_PASSWORD?
A: Backups are unrecoverable without the password. Store it securely (password manager, encrypted file). Consider adding it to your SFTP server as a note.

### Q: Does the backup run automatically?
A: Currently no — the compose file runs backup once on startup. To add scheduling, use cron inside the container or run `podman compose exec restic-backup init` manually.

## Resource Usage

| Metric | Expected | Actual |
|--------|----------|--------|
| RAM | ~50-100MB during backup | ~30MB (restic container during backup) |
| CPU | Spikes during backup | Minimal (146 byte file) |
| Image size | restic: ~150MB, sftp: ~20MB | restic: ~150MB, sftp: ~20MB |
| Network | Depends on data size | Minimal (container-to-container) |
| Storage | ~10-50MB for repo + image | ~2MB for repo (146 byte file with overhead) |

## Lessons Learned

### What worked
- Reusing existing SFTP infrastructure avoids new services
- SSH key auth is reliable in containers when authorized_keys ownership is correct
- Using `podman exec` on an existing container to set up authorized_keys is more reliable than trying to use SFTP protocol for this
- Restic's deduplication is effective for small datasets
- Using temp files for helper scripts avoids heredoc quoting issues
- backup.sh script with runtime SSH config creation is the correct pattern
- Docker compose integration works with mounted script + custom entrypoint

### What didn't work
- Trying to use `ssh` to add authorized_keys to an SFTP-only server — it accepts the connection but rejects shell commands
- Using `sshpass` inside inline `sh -c` strings — the quoting layers make it nearly impossible
- Using `vaughnrestic/restic` image — doesn't exist on Docker Hub
- Calling `restic restic init` — the image entrypoint is `restic`, so the command should just be `init`
- Not verifying the Docker image name before starting — should always check Docker Hub first
- Not checking authorized_keys file ownership — must be owned by the connecting user (UID 1000 for labratorian)
- Not creating backups/repo directory structure in SFTP container before initializing restic repo

### What to do differently
1. Always verify Docker image names on Docker Hub before starting
2. Test the image entrypoint with a simple command before building the full setup
3. Use `podman exec` on existing containers for setup tasks when possible, rather than trying complex SFTP/SSH automation
4. Prefer temp files over inline heredocs for complex shell scripts in `podman run`
5. Check if the SFTP server allows SSH shell access before planning SSH-based setup steps
6. Always verify authorized_keys ownership after adding keys to containers
7. Create all required directory structures before initializing repos

### Dead Ends
- **vaughnrestic/restic image**: Hunted for this image from the original plan, but it doesn't exist. The official image is `restic/restic`.
- **sshpass automation**: Spent significant time trying to automate SSH key setup with sshpass in Alpine containers. The nested quoting issues made this impractical. Switched to `podman exec` which is simpler and more reliable.
- **SFTP-only protocol**: Initially tried to use SFTP protocol to upload the public key file. This works for file transfer but is more complex than just copying into the running SFTP container.

## Round 2: Self-Contained SFTP Server

### Step 1: Move SFTP into this experiment's docker-compose.yml
Stopped the external `homelab-sftp` container from the SFTP experiment and copied its configuration here:
- Copied `config/auth.conf` and `config/sshd.pam` from `infrastructure/sftp/`
- Created `data/backups/repo/` directory structure
- Updated `.gitignore` to reflect new structure

**Design decision**: Make this experiment self-contained. Copy reusable SFTP components rather than depending on external services.

### Step 2: SFTP chroot directory mapping (FAILED)
The `atmoz/sftp` container uses `ChrootDirectory %h` — the SFTP root `/` maps to `/home/labratorian`. Created `/backups/repo` at the container root level, but it wasn't accessible via SFTP because the chroot changed the path.

**Fix**: Created `/home/labratorian/backups/repo` instead. Now accessible as `/backups/repo` via SFTP.

### Step 3: Healthcheck failure (FAILED)
Initial healthcheck used `ssh` command to test port 22, but the Alpine-based `atmoz/sftp:alpine` container doesn't include an SSH client.

**Fix**: Changed healthcheck to `nc -z localhost 22 || exit 1`. The container has `nc` available.

### Step 4: Restic entrypoint conflict (FAILED)
The `restic/restic` image has `restic` as its entrypoint. When compose sets `command: sh -c '...'`, it gets appended after the entrypoint, resulting in `restic sh -c '...'` which fails with `unknown command "sh" for "restic"`.

**Fix**: Added `entrypoint: ["/bin/sh", "-c"]` to override the default entrypoint.

### Step 5: Empty known_hosts file (FAILED)
Generated `known_hosts` from the host using `ssh-keyscan -p 2222 127.0.0.1`. When the restic container tried to connect to `sftp:22` (Docker network alias), the host key didn't match because the SFTP container generates a new key on each restart.

**Fix**: Generated `known_hosts` from *inside* the Docker network: `podman exec homelab-restic-test ssh-keyscan -p 22 sftp`. This captures the SFTP container's actual SSH key on the Docker network.

### Step 6: SSH password authentication failure (FAILED)
Restic's SFTP transport uses SSH internally. The `atmoz/sftp` container uses password authentication, but restic's SSH client doesn't prompt for passwords in non-interactive mode. Got repeated "Permission denied" errors.

**Fix**: SSH_ASKPASS mechanism. Set these environment variables:
```
DISPLAY=:0
SSH_ASKPASS_REQUIRE=force
SSH_ASKPASS=/tmp/ssh-askpass  (script that echoes the password)
```
The `DISPLAY=:0` is required — SSH only uses SSH_ASKPASS when DISPLAY is set.

### Step 7: Variable expansion in compose command (FAILED)
Tried to use `$SFTP_PASSWORD` in the compose `command` field:
```yaml
command: >
  sh -c '
    echo "echo $SFTP_PASSWORD" >> /tmp/ssh-askpass;
  '
```
The `$SFTP_PASSWORD` gets expanded by the compose file parser (or shell) before the container runs, resulting in an empty or incorrect password in the askpass script.

**Fix**: Hardcode the password in the askpass script: `echo "echo ChangeMe"`. Not ideal for secrets management but works for now.

### Step 8: First successful backup and restore (SUCCESS)
Ran restic from the `backup-test` container (Alpine with `restic` installed via `apk`):
```bash
podman exec homelab-restic-test sh -c '
    echo "#!/bin/sh" > /tmp/ssh-askpass
    echo "echo ChangeMe" >> /tmp/ssh-askpass
    chmod +x /tmp/ssh-askpass
    export SSH_ASKPASS=/tmp/ssh-askpass
    export SSH_ASKPASS_REQUIRE=force
    export DISPLAY=:0
    export RESTIC_REPOSITORY="sftp://labratorian@sftp:22/backups/repo"
    export RESTIC_PASSWORD="ResticBackup2026!Secure"
    restic init
    restic backup /source
    restic snapshots
'
```

**Output:**
```
created restic repository 8d2de06925 at sftp://labratorian@sftp:22/backups/repo
no parent snapshot found, will read all files
Files:           1 new,     0 changed,     0 unmodified
Dirs:            1 new,     0 changed,     0 unmodified
Added to the repository: 867 B (820 B stored)
processed 1 files, 146 B in 0:01
snapshot 47421234 saved

ID        Time                 Host          Tags        Paths    Size
-----------------------------------------------------------------------
47421234  2026-04-20 11:54:47  ef9b147c25ad              /source  146 B
-----------------------------------------------------------------------
1 snapshots
```

**Restore test:**
```bash
restic restore latest --target /tmp/restore
```
Verified restored file content: `This is a sample file for testing the Restic backup experiment.`

### Step 9: Docker compose integration (FAILED)
Tried to integrate SSH_ASKPASS into the main `restic-backup` service's compose `command`. The `$SFTP_PASSWORD` variable expansion issue (Step 7) prevented password-based authentication from working in the compose command.

Also tried writing a `backup.sh` script file and mounting it, but the compose `command` field still has quoting/escaping challenges.

**Current state**: Backup and restore work from the test container. The main `restic-backup` container fails to authenticate because the SSH_ASKPASS script can't read the password from environment variables in the compose command context.

## Issues Encountered

### New issues from Round 2
6. **SFTP chroot path mapping**: The `atmoz/sftp` container uses `ChrootDirectory %h`, meaning the SFTP root `/` maps to the user's home directory `/home/labratorian`. Paths like `/backups/repo` must be created at `/home/labratorian/backups/repo` inside the container.

7. **Healthcheck requires nc, not ss**: Alpine-based containers may not have `ss` (iproute2 package). Use `nc` for port checks instead.

8. **Restic image entrypoint overrides compose command**: The `restic/restic` image has `restic` as its entrypoint. Setting `command: sh -c '...'` results in `restic sh -c '...'`. Must override entrypoint with `entrypoint: ["/bin/sh", "-c"]`.

9. **known_hosts must match Docker network host key**: `ssh-keyscan` from the host captures the host's key, not the container's key. Must generate known_hosts from within the Docker network using the service name as the hostname.

10. **SSH_ASKPASS requires DISPLAY=:0**: SSH only uses the SSH_ASKPASS mechanism when `DISPLAY` is set. Without it, SSH prompts for a password and hangs in non-interactive mode.

11. **SSH_ASKPASS script must be executable**: The askpass script needs `chmod +x` or SSH will refuse to use it.

12. **Environment variables in compose command fields get expanded**: `$SFTP_PASSWORD` in a compose `command` field may be expanded by the compose parser before the container starts. Hardcoding values in inline scripts may be necessary as a workaround.

### What worked
- Backup and restore work end-to-end when run from the test container with SSH_ASKPASS
- `atmoz/sftp` with password auth works when SSH_ASKPASS is configured correctly
- SFTP chroot paths work when you account for the `%h` mapping
- Alpine can install `restic` via `apk add` for testing

### What didn't work
- Using SSH keys with `atmoz/sftp` — it uses password auth by default and doesn't support authorized_keys without extra configuration
- Using `$VAR` in compose `command` fields — variable expansion happens before container start
- Using `ss` for healthchecks on Alpine — not available by default
- Using `ssh` for healthchecks on Alpine — not available by default
- Empty known_hosts file — SSH refuses to connect without host key verification

### What to do differently
1. Always check if the Docker image has the tools you need (nc, ssh, restic)
2. Account for SFTP chroot path mapping when creating directories
3. Generate known_hosts from within the Docker network, not from the host
4. Use SSH_ASKPASS with DISPLAY=:0 for password-based SSH in non-interactive containers
5. Avoid environment variable expansion in compose command fields — hardcode or use a mounted script file

### Dead Ends
- **SSH key auth with atmoz/sftp**: The `atmoz/sftp` image doesn't support authorized_keys by default. It uses password auth. Switching to SSH keys would require a different SFTP image or custom configuration.
- **Variable expansion in compose commands**: Tried multiple approaches to read `$SFTP_PASSWORD` from environment variables into the SSH_ASKPASS script. All failed due to premature expansion.
- **ss/ssh healthchecks**: Spent time trying to use `ss` and `ssh` for healthchecks on Alpine. Neither is available by default.

## Round 3: SSH Key Auth + Mounted Script

### Step 1: Use mounted script instead of inline command (FAILED)
The multi-line `command` field in compose gets split by podman-compose into separate arguments. The script never executes as a single unit.

**Fix**: Write `backup.sh` to disk and mount it, then use `entrypoint: ["/bin/sh", "/backup.sh"]`.

### Step 2: Restic image entrypoint overrides everything (FAILED)
The `restic/restic` image has `restic` as its default entrypoint. Any `command` field gets appended after it, resulting in `restic sh -c '...'` which fails with `unknown command "sh" for "restic"`.

**Fix**: Override the entrypoint entirely: `entrypoint: ["/bin/sh", "/backup.sh"]`.

### Step 3: SSH_ASKPASS variable expansion still broken (FAILED)
Tried SSH_ASKPASS with password auth again. The `$SFTP_PASSWORD` variable in the compose file gets expanded before the container starts, resulting in an empty or incorrect password in the askpass script.

**Fix**: Switched to SSH key authentication instead — more reliable and avoids the variable expansion problem entirely.

### Step 4: SSH key auth — authorized_keys on atmoz/sftp (SUCCESS)
Contrary to the earlier "Dead Ends" note in the timeline, `atmoz/sftp` **does** support authorized_keys. The key insight: the container's internal SSH daemon accepts SSH connections for key-based auth, even though it restricts external shell access to SFTP only.

Used `podman cp` and `podman exec` on the running SFTP container to add the public key:
```bash
podman cp ssh-config/id_rsa.pub homelab-sftp:/tmp/id_rsa.pub
podman exec homelab-sftp sh -c '
    mkdir -p /home/labratorian/.ssh && chmod 700 /home/labratorian/.ssh
    cat /tmp/id_rsa.pub >> /home/labratorian/.ssh/authorized_keys && chmod 600 /home/labratorian/.ssh/authorized_keys
    rm -f /tmp/id_rsa.pub
'
```

### Step 5: SSH config in container (FAILED)
Tried using `SSH_CONFIG` environment variable to point SSH to a custom config file. This is not a standard SSH environment variable — SSH only reads `$HOME/.ssh/config` or `/etc/ssh/ssh_config`.

Also tried overriding `HOME=/tmp` to make SSH read from `/tmp/.ssh/config`. This didn't work because the SSH subprocess spawned by restic doesn't inherit the HOME override.

**Fix**: Write SSH config directly to `/root/.ssh/config` inside the container.

### Step 6: Stale known_hosts in bind mount (FAILED)
The `ssh-config/known_hosts` file from a previous run was being bind-mounted into the container. It contained an old host key for the SFTP server, causing "REMOTE HOST IDENTIFICATION HAS CHANGED" errors. Even with `StrictHostKeyChecking no` in the SSH config, the stale known_hosts file was being used.

**Fix**: Remove the `known_hosts` file from the bind mount. Let SSH create a fresh one on each run.

### Step 7: SSH config file being overwritten by bind mount (FAILED)
The compose file had `./ssh-config:/root/.ssh:ro` — a read-only bind mount of the entire ssh-config directory. This overwrote the SSH config file that backup.sh created inside the container at runtime.

**Fix**: Mount only the private key file instead: `./ssh-config/id_rsa:/root/.ssh/id_rsa:ro`. Don't mount the directory.

### Step 8: Backup script still failing — host key verification (IN PROGRESS)
After all the fixes above, the backup script runs and sets up SSH config with `StrictHostKeyChecking no`, but restic still fails with "Host key verification failed". The SSH subprocess spawned by restic may be ignoring the `/root/.ssh/config` file.

Need to investigate whether restic's SSH subprocess respects the SSH config, or if it needs additional flags passed through environment variables.

## Issues Encountered

### New issues from Round 3
13. **Multi-line compose `command` gets split by podman-compose**: The YAML multi-line `command` field is parsed as separate arguments by podman-compose, so the shell script never executes as a single unit. Use a mounted script file instead.

14. **Restic image entrypoint overrides compose command**: The `restic/restic` image has `restic` as its entrypoint. Must override with `entrypoint: ["/bin/sh", "/backup.sh"]`.

15. **SSH_CONFIG is not a standard environment variable**: SSH only reads `$HOME/.ssh/config`. Environment variable overrides for SSH config paths don't work.

16. **HOME override doesn't propagate to SSH subprocess**: Setting `HOME=/tmp` in the shell script doesn't cause the SSH subprocess spawned by restic to read from `/tmp/.ssh/config`.

17. **Stale known_hosts in bind mount causes conflicts**: A `known_hosts` file from a previous run, when bind-mounted into the container, overrides runtime SSH config. Remove it before running.

18. **Directory bind mount overwrites runtime files**: Mounting `./ssh-config:/root/.ssh:ro` overwrites any SSH config files created at runtime inside the container. Mount individual files instead.

19. **atmoz/sftp does support authorized_keys**: Contrary to earlier belief, the `atmoz/sftp` container accepts SSH key authentication. The "sftp connections only" message only applies to external SSH connections — internal SSH key auth works fine.

### What worked
- Mounted script file with custom entrypoint correctly runs the backup script
- SSH key auth via authorized_keys on atmoz/sftp works when key is added via `podman exec`
- `StrictHostKeyChecking no` in SSH config should bypass host key verification

### What didn't work
- Multi-line `command` fields in compose — they get split into separate arguments
- `SSH_CONFIG` environment variable — not recognized by SSH
- `HOME` override — doesn't propagate to subprocesses
- Directory bind mounts for SSH config — overwrite runtime files
- SSH_ASKPASS with variable expansion — premature expansion in compose files

### What to do differently
1. Always use mounted script files for complex shell logic in containers
2. Override the entrypoint when the Docker image has a non-shell default entrypoint
3. Mount individual files, not directories, to avoid overwriting runtime files
4. Don't include `known_hosts` in bind mounts — let SSH manage it
5. SSH key auth is more reliable than SSH_ASKPASS for container-to-container connections
6. The `atmoz/sftp` image supports authorized_keys — don't assume it doesn't

### Dead Ends
- **SSH_ASKPASS with variable expansion**: The `$VAR` in compose `command` fields gets expanded before the container starts. This is a fundamental limitation of how compose parses environment variables.
- **SSH_CONFIG env var**: Tried using this to point SSH to a custom config. Not a standard SSH variable.
- **HOME override**: Tried to shift SSH config location by overriding HOME. Doesn't propagate to subprocesses.
- **Directory bind mount for SSH config**: Thought mounting the whole directory would work. It overwrites runtime files.

## Round 4: Fix authorized_keys Ownership + Verify Full Integration

### Step 1: authorized_keys ownership issue (FIXED)
The SSH key was added to authorized_keys but the file was owned by `root` instead of the `labratorian` user (UID 1000). SSH requires the authorized_keys file to be owned by the connecting user.

**Fix:**
```bash
podman exec homelab-sftp sh -c '
    chown 1000:1000 /home/labratorian/.ssh/authorized_keys
    chown 1000:1000 /home/labratorian/.ssh
'
```

### Step 2: backups/repo directory missing (FIXED)
The SFTP container's `/home/labratorian/backups/repo` directory didn't exist. The named volume was mounted at `/home/labratorian` but no backups directory was created.

**Fix:**
```bash
podman exec homelab-sftp sh -c '
    mkdir -p /home/labratorian/backups/repo
    chown -R 1000:1000 /home/labratorian/backups
    chmod -R 755 /home/labratorian/backups
'
```

### Step 3: Repository initialization (FIXED)
The restic repository needed to be initialized before backup. The `init` command requires SSH config with `StrictHostKeyChecking no` to be set up first.

**Fix:**
```bash
podman run --rm --net homelab-restic-network \
    -v ./ssh-config/id_rsa:/root/.ssh/id_rsa:ro \
    -e RESTIC_REPOSITORY=sftp://labratorian@sftp:22/backups/repo \
    -e RESTIC_PASSWORD='ResticBackup2026!Secure' \
    --entrypoint /bin/sh \
    docker.io/restic/restic:latest -c '
        mkdir -p /root/.ssh
        printf "Host *\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null\n" > /root/.ssh/config
        chmod 600 /root/.ssh/config
        restic init
    '
```

### Step 4: First backup via backup.sh (SUCCESS)
The backup.sh script correctly sets up SSH config and runs the backup. It worked end-to-end:

```
Setting up SSH to skip host key verification...
SSH config ready.
Running restic backup...
subprocess ssh: Warning: Permanently added 'sftp' (ED25519) to the list of known hosts.
no parent snapshot found, will read all files

Files:           1 new,     0 changed,     0 unmodified
Dirs:            1 new,     0 changed,     0 unmodified
Added to the repository: 867 B (820 B stored)

processed 1 files, 146 B in 0:01
snapshot 6ac4e43c saved
```

### Step 5: Restore test (SUCCESS)
```bash
restic restore latest --target /restore
```
Verified restored file content: `This is a sample file for testing the Restic backup experiment.`

### Step 6: Docker compose integration (SUCCESS)
Ran `podman compose up -d restic-backup` and it worked. The container:
- Created a second snapshot (aba9c368)
- Both snapshots visible in `podman logs homelab-restic-backup`
- Container exited cleanly after backup completed (restart: "no")

### Root cause of Round 3 Step 8 failure
The Round 3 Step 8 failure ("Host key verification failed") was caused by TWO issues:
1. **authorized_keys ownership**: The file was owned by root, not the labratorian user (UID 1000). SSH rejected the key.
2. **Missing backups/repo directory**: The directory structure didn't exist in the SFTP container.

Once both were fixed, the backup.sh script worked correctly because it already had `StrictHostKeyChecking no` and `UserKnownHostsFile /dev/null` in the SSH config it creates at runtime.

## Issues Encountered

### New issues from Round 4
20. **authorized_keys must be owned by the connecting user**: The `atmoz/sftp` container creates users with UID 1000. The authorized_keys file must be owned by that UID, not root. Use `chown 1000:1000` (numeric IDs work when username:groupname doesn't).
21. **backups/repo directory must exist in SFTP container**: The named volume is mounted at `/home/labratorian` but subdirectories must be created manually. Use `podman exec` to create them.
22. **restic init requires SSH config setup**: The `init` command runs SSH internally. Must set up `StrictHostKeyChecking no` before running init, same as backup.

### What worked
- SSH key auth with atmoz/sftp works when authorized_keys ownership is correct
- backup.sh script correctly sets up SSH config at runtime
- Docker compose integration works with mounted script + custom entrypoint
- Restic backup and restore work end-to-end
- Container exits cleanly after backup (restart: "no" behavior)

### What to do differently
1. Always check authorized_keys ownership when setting up SSH key auth in containers
2. Create all required directory structures in SFTP containers before initializing repos
3. The backup.sh approach (SSH config + mounted script) is the correct pattern
4. No need for known_hosts in bind mount — let SSH manage it at runtime

## Simplification Cleanup (April 24, 2026)

Applied the per-experiment simplification plan phases:

### Phase 1 - Trivial Cleanup
- Removed `version: '3.8'` line
- Pinned `restic/restic:latest` → `restic/restic:0.18.0`
- Pinned `alpine:latest` → `alpine:3.21`

### Phase 2 - Test-Client Standardization
- Renamed `backup-test` service to `test-client`
- Changed container_name from `homelab-restic-test` to `homelab-restic-backup-test`

### Phase 3 - Secret Hygiene
- `.env` already existed with `RESTIC_PASSWORD`
- Added `SFTP_USERS` and `SFTP_PASSWORD` to `.env` (were hardcoded in compose)
- Updated `.env.example` with all three variables
- Replaced hardcoded secrets in compose with `${VAR}` references:
  - `SFTP_USERS=labratorian:ChangeMe:1000:1000` → `${SFTP_USERS}`
  - `RESTIC_PASSWORD=ResticBackup2026!Secure` → `${RESTIC_PASSWORD}`
  - `SFTP_PASSWORD=ChangeMe` → `${SFTP_PASSWORD}`

### Phase 4 - Network Naming
- Renamed network key from `restic-network` to `homelab-restic-backup`
- Removed redundant `name: homelab-restic-network` field

### Phase 5 - Volume Naming
- Renamed named volume from `sftp-data` to `restic-backup_sftp_data`

### Phase 6 - Port Conflicts
- Changed SFTP host port from `2222` to `2223` (conflict with `infrastructure/sftp` experiment)
- Updated `setup.sh` to use port 2223
- Updated README troubleshooting section with new port

### Phase 8 - README Consistency
- Added Overview section (1-2 sentences)
- Added Services table (Service | Port | Purpose)
- Added Testing section with updated container name
- Added Troubleshooting section (renamed from "Common Pitfalls")
- Added Cleanup section
- Updated all port references from 2222 to 2223
- Updated container name references from `homelab-restic-test` to `homelab-restic-backup-test`

### Test-Client SSH Config Fix
During verification, discovered the test client had `DISPLAY=:0` and `SSH_ASKPASS_REQUIRE=force` environment variables that triggered SSH_ASKPASS lookups, causing failures when ssh-askpass binary wasn't installed. Since we're using SSH key auth, these variables were removed. Additionally, the test client's entrypoint was updated to automatically set up the system-wide SSH config (`/etc/ssh/ssh_config`) with `StrictHostKeyChecking no` and `UserKnownHostsFile /dev/null`, matching the pattern used by `backup.sh` in the restic-backup container.

### Verification Results
- All three containers start successfully: `homelab-sftp`, `homelab-restic-backup`, `homelab-restic-backup-test`
- DNS resolution works: test client can ping `sftp` by service name
- Port mapping correct: `22/tcp -> 0.0.0.0:2223`
- Restic backup runs successfully from `homelab-restic-backup` container
- Restic snapshots accessible from `homelab-restic-backup-test` container

## Next Steps

1. Test multiple backups to verify deduplication (run backup again with same data)
2. Test restore from the test container using the compose setup
3. Add retention policy with `restic forget`
4. Consider cron scheduling (restic container exits after one run since `restart: "no"`)
5. Test with larger source data to measure deduplication and compression
6. Add healthcheck for SFTP server monitoring
7. Document UFW rules if exposing to network (currently only accessible via Docker network)
