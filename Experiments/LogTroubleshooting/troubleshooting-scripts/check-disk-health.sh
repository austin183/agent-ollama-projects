#!/bin/bash
# check-disk-health.sh - Check disk health and filesystem errors
# Usage: ./check-disk-health.sh

echo "=== Disk Health Check ==="
echo ""

# Check filesystem errors
echo "--- Last Filesystem Errors ---"
journalctl -k -b --since "24 hours ago" | grep -E "FAT|usb|sd" | tail -15

echo ""
echo "--- Filesystem Mount Info ---"
df -h

echo ""
echo "--- Disk Usage ---"
du -sh /var/log/* 2>/dev/null | sort -h | tail -10

echo ""
echo "--- Mount Points ---"
findmnt -t ext4,xfs,vfat -l

echo ""
echo "--- Disk Statistics ---"
iostat -x 1 2 | tail -n +4

echo ""
echo "--- SMART Status (if available) ---"
for disk in /dev/sd* /dev/nvme*; do
    if [ -b "$disk" ]; then
        echo "--- $disk ---"
        smartctl -H "$disk" 2>/dev/null | grep -E "SMART overall-health|PASSED|FAILED"
    fi
done