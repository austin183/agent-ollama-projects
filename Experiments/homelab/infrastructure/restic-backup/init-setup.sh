#!/bin/sh
set -e

echo "=== Restic Init ==="

# Wait for SFTP server to be ready
echo "Waiting for SFTP server..."
for i in $(seq 1 60); do
  if nc -z sftp 22 2>/dev/null; then
    echo "SFTP server is ready"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERROR: SFTP server did not become ready in time"
    exit 1
  fi
  sleep 2
done

# Setup SSH to skip host key verification
echo "Setting up SSH config..."
mkdir -p /root/.ssh
cat > /root/.ssh/config <<SSHEOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
SSHEOF
chmod 600 /root/.ssh/config

# Initialize restic repository (skip if already initialized)
echo "Initializing restic repository..."
restic -r sftp://labratorian@sftp:22/backups/repo snapshots 2>/dev/null || restic -r sftp://labratorian@sftp:22/backups/repo init

echo "=== Init Complete ==="
