#!/bin/bash
# check-kernel-issues.sh - Check for kernel panics and freeze indicators
# Usage: ./check-kernel-issues.sh

echo "=== Kernel Issues Check ==="
echo ""

# Kernel panic logs
echo "--- Kernel Panics ---"
journalctl -k -b --since "24 hours ago" | grep -i "panic" | tail -10

echo ""
echo "--- Kernel Warnings ---"
journalctl -k -b --since "24 hours ago" | grep -iE "warn|error" | tail -20

echo ""
echo "--- KDSO/Kpatch Issues ---"
journalctl -k -b --since "24 hours ago" | grep -E "kdsb|kpatch|patch" | tail -10

echo ""
echo "--- OOM Killer Activity ---"
journalctl -k -b --since "24 hours ago" | grep -i "out of memory" | tail -10

echo ""
echo "--- Memory Corruption Warnings ---"
journalctl -k -b --since "24 hours ago" | grep -iE "bad_page|corrupt|mem leak" | tail -15

echo ""
echo "--- Recent Kernel Messages ---"
journalctl -k -b --since "1 hour ago" | tail -30

echo ""
echo "--- Kernel Version ---"
uname -r
echo ""
echo "--- Kernel Modules ---"
lsmod | head -20