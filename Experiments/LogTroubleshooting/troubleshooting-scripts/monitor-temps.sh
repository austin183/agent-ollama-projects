#!/bin/bash
# monitor-temps.sh - Monitor system temperatures continuously
# Usage: ./monitor-temps.sh [interval_seconds]

set -e

INTERVAL=${1:-5}

echo "Monitoring temperatures every $INTERVAL seconds (Ctrl+C to stop)..."
echo "================================"

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "\n[$TIMESTAMP]"
    sensors --no-thermal
    echo "--- GPU Power ---"
    cat /sys/class/drm/card0/device/gsub_power 2>/dev/null || echo "N/A"
    echo "--- Load Average ---"
    uptime
    sleep "$INTERVAL"
done