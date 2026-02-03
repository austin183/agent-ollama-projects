#!/bin/bash
# capture-freeze-logs.sh - Capture logs after a system freeze
# Usage: ./capture-freeze-logs.sh

set -e

OUTPUT_DIR="/tmp/freeze-logs-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo "Capturing freeze logs to: $OUTPUT_DIR"
echo "======================================"
echo ""

# Capture kernel logs
echo "--- Capturing kernel logs ---"
journalctl -k --since today -p err > "$OUTPUT_DIR/kernel-logs.txt"
journalctl -k --since today -p warn > "$OUTPUT_DIR/kernel-warnings.txt"

# Capture dmesg
echo "--- Capturing dmesg ---"
dmesg > "$OUTPUT_DIR/dmesg.txt"

# Capture recent system logs
echo "--- Capturing system logs ---"
journalctl --since today > "$OUTPUT_DIR/system-logs.txt"

# Capture GPU driver logs
echo "--- Capturing GPU logs ---"
journalctl -k -b --since "24 hours ago" | grep -E "amdgpu|dri|pipewire|sddm" > "$OUTPUT_DIR/gpu-logs.txt"

# Capture memory info
echo "--- Capturing memory info ---"
free -h > "$OUTPUT_DIR/mem-info.txt"
cat /proc/meminfo > "$OUTPUT_DIR/proc-meminfo.txt"

# Capture temperature readings
echo "--- Capturing temperatures ---"
sensors --no-thermal > "$OUTPUT_DIR/temperatures.txt"

# Capture disk info
echo "--- Capturing disk info ---"
df -h > "$OUTPUT_DIR/disk-info.txt"
lsblk -f > "$OUTPUT_DIR/lsblk.txt"

# Capture power info
echo "--- Capturing power info ---"
journalctl -k -b --since "24 hours ago" | grep -iE "acpi|power|dc" > "$OUTPUT_DIR/power-info.txt"

echo ""
echo "Capture complete!"
echo ""
echo "Files created:"
ls -lh "$OUTPUT_DIR"
echo ""
echo "To view a specific file:"
echo "  cat $OUTPUT_DIR/kernel-logs.txt"
echo ""
echo "To share all logs:"
echo "  tar czf freeze-logs.tar.gz $OUTPUT_DIR"
echo "  ls -lh freeze-logs.tar.gz"