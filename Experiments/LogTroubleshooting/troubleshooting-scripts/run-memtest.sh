#!/bin/bash
# run-memtest.sh - Run memory diagnostics
# Usage: sudo ./run-memtest.sh

set -e

echo "=== Memory Diagnostics ==="
echo ""
echo "This script helps you prepare for Memtest86"
echo ""

# Check if Memtest86 is installed
if command -v memtest86-plus &> /dev/null; then
    echo "✓ memtest86-plus is installed"
    echo "  Location: $(which memtest86-plus)"
else
    echo "✗ memtest86-plus is NOT installed"
    echo ""
    echo "Install Memtest86:"
    echo "  sudo dnf install memtest86-plus"
    echo ""
    echo "Then boot from a USB drive with memtest86 on it"
fi

echo ""
echo "=== RAM Information ==="
echo ""
echo "--- Installed RAM ---"
free -h
echo ""
echo "--- Memory Channels ---"
cat /proc/meminfo | grep -E "MemTotal|MemAvailable|MemFree"
echo ""
echo "--- NUMA Info (if available) ---"
cat /proc/cpuinfo | grep -E "numa_node|physical id" | head -20
echo ""

echo "=== Next Steps ==="
echo ""
echo "1. Create a bootable Memtest86 USB drive"
echo "2. Boot from the USB drive"
echo "3. Let it run for at least 1 complete pass"
echo "4. Check for any errors (E=Errors)"
echo ""
echo "For further analysis, collect these logs after Memtest:"
echo "  dmesg -T | grep -E 'bad_page|memory|corrupt|oom'"