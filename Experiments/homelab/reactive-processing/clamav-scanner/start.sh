#!/bin/bash
set -e

echo "[STARTUP] Updating ClamAV virus definitions..."
freshclam || echo "[WARN] freshclam failed, starting with existing definitions"

echo "[STARTUP] Configuring ClamAV daemon..."
# Replace 'User clamav' with 'User root' since clamav user doesn't exist in container
sed -i 's/^User clamav/User root/' /etc/clamav/clamd.conf
# Ensure socket directory exists with proper permissions
mkdir -p /var/run/clamav
chmod 755 /var/run/clamav

echo "[STARTUP] Starting ClamAV daemon in background..."
clamd --config-file=/etc/clamav/clamd.conf &
CLAMD_PID=$!

echo "[STARTUP] Waiting for ClamAV daemon socket..."
for i in $(seq 1 30); do
    if [ -S /var/run/clamav/clamd.ctl ]; then
        echo "[STARTUP] ClamAV daemon is ready"
        break
    fi
    sleep 1
done

if [ ! -S /var/run/clamav/clamd.ctl ]; then
    echo "[ERROR] ClamAV daemon failed to start"
    exit 1
fi

echo "[STARTUP] Starting scanner..."
exec python3 /app/scanner.py
