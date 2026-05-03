#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SFTP_HOST="127.0.0.1"
SFTP_PORT="2223"
SFTP_USER="labratorian"
SFTP_PASSWORD="ChangeMe"

echo "=== Restic Backup Setup ==="
echo ""

# Step 1: Create known_hosts file for the container
echo "[1/3] Creating known_hosts file..."
ssh-keyscan -p "${SFTP_PORT}" "${SFTP_HOST}" 2>/dev/null > "${SCRIPT_DIR}/ssh-config/known_hosts"
echo "  known_hosts created"

# Step 2: Create backup directory on SFTP server
echo "[2/3] Creating backup repository directory..."
sshpass -p "${SFTP_PASSWORD}" sftp -o StrictHostKeyChecking=no -P "${SFTP_PORT}" "${SFTP_USER}@${SFTP_HOST}" <<EOF
mkdir -p backups/repo
bye
EOF
echo "  Backup directory created"

# Step 3: Initialize restic repository
echo "[3/3] Initializing restic repository on SFTP server..."
if [ ! -f "${SCRIPT_DIR}/data/backups/repo/README" ]; then
    RESTIC_PASSWORD=$(grep RESTIC_PASSWORD "${SCRIPT_DIR}/.env" | cut -d'=' -f2-)
    podman run --rm \
        -e RESTIC_REPOSITORY=sftp://${SFTP_USER}:${SFTP_PASSWORD}@${SFTP_HOST}:${SFTP_PORT}/backups/repo \
        -e RESTIC_PASSWORD="${RESTIC_PASSWORD}" \
        -e RESTIC_CACHE_DIR=/cache \
        -v "${SCRIPT_DIR}/ssh-config":/root/.ssh:ro \
        docker.io/restic/restic:0.18.0 \
        init

    echo "  Restic repository initialized"
else
    echo "  Restic repository already initialized, skipping"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Add files to source-data/ that you want to back up"
echo "  2. Run: podman compose -f docker-compose.yml up -d"
echo "  3. Run: podman compose -f docker-compose.yml up -d  (restic runs on startup)"
echo ""
echo "To run a manual backup after containers are running:"
echo "  podman compose -f docker-compose.yml exec restic-backup restic backup /source"
