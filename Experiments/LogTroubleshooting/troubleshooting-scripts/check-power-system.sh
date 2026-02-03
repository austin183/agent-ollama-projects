#!/bin/bash
# check-power-system.sh - Check power supply and ACPI issues
# Usage: ./check-power-system.sh

echo "=== Power System Check ==="
echo ""

# Check ACPI logs
echo "--- ACPI/Power Kernel Logs ---"
journalctl -k -b --since "24 hours ago" | grep -iE "acpi|power|dc|charger" | tail -20

echo ""
echo "--- Power Supply Status ---"
cat /sys/class/power_supply/AC*/online 2>/dev/null || echo "AC info not available"
cat /sys/class/power_supply/AC*/capacity_level 2>/dev/null || echo "AC capacity not available"

echo ""
echo "--- Battery Status (if applicable) ---"
cat /sys/class/power_supply/BAT*/status 2>/dev/null || echo "No battery detected"
cat /sys/class/power_supply/BAT*/capacity 2>/dev/null || echo "No battery detected"

echo ""
echo "--- System Power State ---"
cat /sys/power/state
cat /sys/power/pm_async

echo ""
echo "--- Power Usage Estimate ---"
echo "Current CPU load: $(awk '{print $1}' /proc/loadavg)"
echo "CPU cores: $(nproc)"
echo "System uptime: $(uptime -p)"

echo ""
echo "--- PM / Hibernation Status ---"
systemctl status suspend.target 2>/dev/null || echo "suspend target not found"
systemctl status hibernate.target 2>/dev/null || echo "hibernate target not found"

echo ""
echo "--- Recent Reboots ---"
last reboot | head -5