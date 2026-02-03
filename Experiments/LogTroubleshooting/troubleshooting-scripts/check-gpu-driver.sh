#!/bin/bash
# check-gpu-driver.sh - Check GPU driver status and logs
# Usage: ./check-gpu-driver.sh

echo "=== GPU Driver Status ==="
echo ""

# Check amdgpu status
echo "--- amdgpu Kernel Logs ---"
journalctl -k -b --since "24 hours ago" | grep -i "amdgpu" | tail -20

echo ""
echo "--- DRI/PipeWire Errors ---"
journalctl -k -b --since "24 hours ago" | grep -E "dri|pipewire|sddm" | tail -20

echo ""
echo "--- GPU Status ---"
if command -v radeontop &> /dev/null; then
    radeontop -b -d 1
else
    echo "radeontop not installed. Run: sudo dnf install radeontop"
fi

echo ""
echo "--- AMDGPU Module Info ---"
lsmod | grep amdgpu
modinfo amdgpu | head -5

echo ""
echo "--- Xorg/Wayland Session ---"
echo "Current session type: $(loginctl show-session $(loginctl session-id $USER) -p Type)"