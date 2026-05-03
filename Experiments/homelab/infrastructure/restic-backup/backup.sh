#!/bin/sh
echo "Setting up SSH to skip host key verification..."
mkdir -p /root/.ssh
cat > /root/.ssh/config <<SSHEOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
SSHEOF
chmod 600 /root/.ssh/config
echo "SSH config ready."

echo "Waiting for restic repository to be initialized..."
for i in $(seq 1 60); do
  if restic -r sftp://labratorian@sftp:22/backups/repo --cache-dir=/cache snapshots 2>/dev/null; then
    echo "Repository is ready"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERROR: Repository was not initialized in time"
    exit 1
  fi
  sleep 2
done

# Ensure DNS resolution is stable (podman DNS can be flaky on startup)
echo "Verifying DNS resolution..."
for i in $(seq 1 10); do
  if getent hosts sftp >/dev/null 2>&1; then
    echo "DNS is stable"
    break
  fi
  if [ "$i" -eq 10 ]; then
    echo "ERROR: DNS resolution failed"
    exit 1
  fi
  sleep 1
done

echo "Running restic backup..."
BACKUP_SUCCESS=0
for attempt in 1 2 3; do
  if restic -r sftp://labratorian@sftp:22/backups/repo \
    --cache-dir=/cache \
    backup /source; then
    BACKUP_SUCCESS=1
    break
  fi
  echo "Backup attempt $attempt failed, retrying in 5s..."
  sleep 5
done

if [ "$BACKUP_SUCCESS" -ne 1 ]; then
  echo "ERROR: Backup failed after 3 attempts"
  exit 1
fi

echo "Backup complete."
echo "Checking snapshots..."
restic -r sftp://labratorian@sftp:22/backups/repo \
  --cache-dir=/cache \
  snapshots
