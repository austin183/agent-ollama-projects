# Restic Backup Experiment

## Overview

Restic is a fast, secure, deduplicating backup program. This experiment demonstrates encrypted, deduplicated backups from a local directory to an SFTP server using a self-contained SFTP + Restic setup.

## Quick Start

```bash
cd ~/homelab/infrastructure/restic-backup
cp .env.example .env
# Edit .env — replace CHANGE_ME values with your SFTP username/password
mkdir -p ssh-config
ssh-keygen -t rsa -b 4096 -f ssh-config/id_rsa -N "" -q
podman compose up -d
```

This generates an SSH key pair for restic-to-SFTP authentication and starts all services. The `restic-init` container automatically sets up SSH configuration, creates the backup directory on the SFTP server, and initializes the restic repository. On subsequent runs, it detects the existing repository and skips initialization.

```bash
# Check init logs
podman logs homelab-restic-init

# Check backup logs
podman logs -f homelab-restic-backup
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| sftp | 2223/tcp | SFTP server for backup storage |
| restic-init | - | One-shot init: SSH setup + restic repo init |
| restic-backup | - | Runs backup on startup (restart: "no") |
| test-client | - | Alpine container with restic/ssh tools for testing |

## Architecture

```
[source-data/] → [restic container] → [SFTP server:2223/backups/repo/]
                      │                        │
                  encrypted               encrypted
                  deduplicated             deduplicated
```

Key features:
- **Deduplication**: Only changed blocks are stored
- **Encryption**: AES-256 encryption with your password
- **Compression**: Automatic compression based on content
- **Incremental**: Each backup only stores differences
- **SFTP transport**: Uses SSH for secure transfer

## Testing

### Test connectivity from test container

```bash
# Test SFTP connectivity (the atmoz/sftp image forces SFTP-only, so SSH shell commands are rejected)
podman exec homelab-restic-backup-test nc -z sftp 22 && echo "SFTP server reachable"

# Or test with an actual SFTP command
podman exec homelab-restic-backup-test sshpass -p "$SFTP_PASSWORD" sftp -o StrictHostKeyChecking=no -P 22 labratorian@sftp <<< "ls /backups"

# Test restic snapshots from test-client
podman exec homelab-restic-backup-test restic -r sftp://labratorian@sftp:22/backups/repo snapshots
```

### Check backup logs

```bash
# View init logs (repository setup)
podman logs homelab-restic-init

# View backup logs
podman logs homelab-restic-backup
```

### Check source data

```bash
# Verify source files are visible to container
podman exec homelab-restic-backup-test ls -la /source
```

## Manual Commands

Use the test-client container for ad-hoc restic commands (the restic-backup container exits after running):

### Check backup status

```bash
# List all snapshots
podman exec homelab-restic-backup-test restic -r sftp://labratorian@sftp:22/backups/repo snapshots

# Show backup size
podman exec homelab-restic-backup-test restic -r sftp://labratorian@sftp:22/backups/repo stats

# Check what would be backed up
podman exec homelab-restic-backup-test restic -r sftp://labratorian@sftp:22/backups/repo backup /source --dry-run
```

### Run a manual backup

```bash
podman exec homelab-restic-backup-test restic -r sftp://labratorian@sftp:22/backups/repo backup /source
```

### Restore from backup

```bash
# List available snapshots
podman exec homelab-restic-backup-test restic -r sftp://labratorian@sftp:22/backups/repo snapshots

# Restore to a directory
podman exec homelab-restic-backup-test restic -r sftp://labratorian@sftp:22/backups/repo restore latest --target /restore
```

### Forget old backups

```bash
# Keep last 7 daily backups, 4 weekly, 12 monthly
podman exec homelab-restic-backup-test restic -r sftp://labratorian@sftp:22/backups/repo forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
```

### Check repository health

```bash
podman exec homelab-restic-backup-test restic -r sftp://labratorian@sftp:22/backups/repo check
```

## Scheduling

The `restic-backup` container runs once on startup and exits. To schedule recurring backups, use a system cron job:

```bash
# Add to crontab (e.g., daily at 2 AM)
crontab -e
0 2 * * * cd ~/homelab/infrastructure/restic-backup && podman compose up restic-backup 2>&1 | tail -5 >> /var/log/restic-backup.log
```

Or use the test-client for manual backups at any time:
```bash
podman exec homelab-restic-backup-test restic -r sftp://labratorian@sftp:22/backups/repo backup /source
```

## Troubleshooting

- **Wrong SFTP password**: The SFTP server password must match what's in the container's SSH config. Default is `ChangeMe`.
- **SSH host key mismatch**: The init and backup containers use `StrictHostKeyChecking=no` to avoid host key issues. If you need strict verification, add a `known_hosts` file to `ssh-config/`.
- **RESTIC_PASSWORD mismatch**: The password in `.env` must be used for all restic commands. Losing this password means losing access to backups.
- **SFTP repository not initialized**: The `restic-init` container handles this automatically. If it fails, check its logs with `podman logs homelab-restic-init`. You can also run `./setup.sh` as a manual fallback.
- **Source data permissions**: The container runs as root, so it should have read access to source files. If using bind mounts, ensure the host files are readable.
- **Network connectivity**: Containers communicate on the `homelab-restic-backup` bridge network. The restic containers reach the SFTP server via the `sftp` service name on port 22. Verify with `podman logs homelab-restic-init`.
- **Disk space on SFTP server**: Ensure the SFTP server has enough space for backups. Check with:
  ```bash
  ssh labratorian@<YOUR_INTERNAL_IP> -p 2223 "df -h backups/"
  ```
- **Port conflict**: Port 2223 is used by restic-backup to avoid conflict with the `infrastructure/sftp` experiment on port 2222.
- **DNS resolution failures**: Podman's internal DNS can be flaky on container startup. The backup script includes retry logic to handle this. If you see "Could not resolve hostname sftp", wait a few seconds and retry.

## Cleanup

```bash
podman compose down -v
```

## Resource Usage

| Metric | Expected |
|--------|----------|
| RAM | ~50-100MB during backup, ~10MB idle |
| CPU | Spikes during backup, idle otherwise |
| Storage | ~10-50MB for restic image |
| Network | Depends on source data size |
| Disk I/O | During backup window only |

## Backup Retention

Restic stores all backups indefinitely by default. To manage storage:

```bash
# Keep last N snapshots
podman exec homelab-restic-backup-test restic -r sftp://labratorian@sftp:22/backups/repo forget --keep-last 5 --prune

# Keep daily for 7 days, weekly for 4 weeks, monthly for 12 months
podman exec homelab-restic-backup-test restic -r sftp://labratorian@sftp:22/backups/repo forget \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
```

## Design Decisions

1. **SFTP as backup target**: Reuses existing SFTP infrastructure, no additional services needed
2. **SSH key authentication**: RSA key pair auto-configured via SFTP entrypoint wrapper; restic containers use key-based auth
3. **Init container pattern**: `restic-init` handles repository setup on first run; idempotent (skips if repo exists)
4. **Wait loops over depends_on**: Podman-compose has unreliable dependency ordering; init and backup scripts use wait loops for SFTP/repository readiness
5. **restic/restic image**: Lightweight, includes SSH client and restic binary
6. **Dedicated network**: Isolates backup traffic from other services
7. **One-shot backup container**: `restic-backup` runs once and exits; use cron or test-client for recurring backups

## Next Steps

1. Add more files to `source-data/` to back up
2. Adjust backup schedule based on your needs
3. Set up retention policy with `restic forget`
4. Test restore procedure periodically
5. Consider backing up additional volumes (AdGuard config, etc.)
6. Monitor backup success with logs
