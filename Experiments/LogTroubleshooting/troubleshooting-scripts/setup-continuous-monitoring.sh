#!/bin/bash
# setup-continuous-monitoring.sh - Set up continuous system monitoring
# Usage: sudo ./setup-continuous-monitoring.sh

set -e

MONITOR_SCRIPT="/usr/local/bin/sys-monitor.sh"
LOG_FILE="/var/log/sys-monitor.log"
PID_FILE="/var/run/sys-monitor.pid"

# Create monitoring script
echo "Creating monitoring script..."
sudo tee "$MONITOR_SCRIPT" << 'EOF' > /dev/null
#!/bin/bash
LOG_FILE="/var/log/sys-monitor.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

{
    echo "=== $TIMESTAMP ==="
    echo "--- CPU/GPU Temps ---"
    sensors --no-thermal 2>/dev/null || echo "sensors command not available"
    echo "--- GPU Power ---"
    cat /sys/class/drm/card0/device/gsub_power 2>/dev/null || echo "N/A"
    echo "--- Memory ---"
    free -h
    echo "--- Disk I/O ---"
    iostat -x 1 3 2>/dev/null || echo "iostat command not available"
    echo "--- Top Processes ---"
    top -b -n 1 | head -20
    echo "--- Kernel Warnings ---"
    dmesg -T | grep -iE "warn|err" | tail -10
    echo "--- Load Average ---"
    uptime
    echo ""
} >> "$LOG_FILE"
EOF

# Make executable
sudo chmod +x "$MONITOR_SCRIPT"

# Stop existing instance if any
if [ -f "$PID_FILE" ]; then
    echo "Stopping existing monitoring process..."
    sudo kill $(cat "$PID_FILE") 2>/dev/null || true
    rm -f "$PID_FILE"
fi

# Create log directory if it doesn't exist
sudo mkdir -p /var/log

# Start monitoring in background
echo "Starting monitoring..."
sudo nohup "$MONITOR_SCRIPT" > /dev/null 2>&1 &
echo $! > "$PID_FILE"

echo "✓ Monitoring started (PID: $(cat $PID_FILE))"
echo ""
echo "To check logs:"
echo "  tail -f $LOG_FILE"
echo ""
echo "To stop monitoring:"
echo "  sudo kill $(cat $PID_FILE)"
echo ""
echo "To view full history:"
echo "  grep -E '=== |=== GPU Power ===' $LOG_FILE"