#!/bin/bash
# check-all.sh - Run all troubleshooting checks
# Usage: ./check-all.sh

set -e

OUTPUT_DIR="/tmp/troubleshooting-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo "Running all troubleshooting checks..."
echo "Output directory: $OUTPUT_DIR"
echo "======================================"
echo ""

# Run each check and save output
echo "[1/6] Checking temperatures..."
sensors --no-thermal > "$OUTPUT_DIR/01-temperatures.txt" 2>/dev/null || true

echo "[2/6] Checking GPU driver..."
journalctl -k -b --since "24 hours ago" | grep -iE "amdgpu|dri|pipewire|sddm" > "$OUTPUT_DIR/02-gpu-logs.txt"

echo "[3/6] Checking disk health..."
journalctl -k -b --since "24 hours ago" | grep -E "FAT|usb|sd" > "$OUTPUT_DIR/03-disk-logs.txt"
df -h > "$OUTPUT_DIR/03-disk-info.txt"

echo "[4/6] Checking power system..."
journalctl -k -b --since "24 hours ago" | grep -iE "acpi|power|dc|charger" > "$OUTPUT_DIR/04-power-logs.txt"

echo "[5/6] Checking kernel issues..."
journalctl -k -b --since "24 hours ago" | grep -iE "panic|warn|error|kdsb|kpatch|bad_page|corrupt|oom" > "$OUTPUT_DIR/05-kernel-logs.txt"

echo "[6/6] Capturing system info..."
free -h > "$OUTPUT_DIR/06-mem-info.txt"
uptime > "$OUTPUT_DIR/06-system-info.txt"
lsblk -f > "$OUTPUT_DIR/06-disk-block.txt"

echo ""
echo "✓ All checks complete!"
echo ""
echo "Summary of findings:"
echo ""

for file in "$OUTPUT_DIR"/*.txt; do
    count=$(wc -l < "$file" | tr -d ' ')
    size=$(du -h "$file" | cut -f1)
    echo "  $(basename "$file"): $size ($count lines)"
done

echo ""
echo "View individual reports:"
echo "  cat $OUTPUT_DIR/01-temperatures.txt"
echo ""
echo "Share all logs:"
echo "  tar czf troubleshooting-logs.tar.gz $OUTPUT_DIR"
echo "  ls -lh troubleshooting-logs.tar.gz"