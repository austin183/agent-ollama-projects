# System Freeze Troubleshooting Guide

## System Info
- **OS**: Bazzite (Fedora-based)
- **GPUs**: AMD RX 9070/9070 XT + Radeon Graphics (integrated)
- **Issue**: Progressive system freeze (interface first, then mouse stops responding)
- **Triggers**: File copying, gaming (save file write failures)
- **Timeline**: New PC (~1 month old)

---

## Log Gathering Commands

> **Note**: Run these commands when investigating a freeze. Save the output to files for analysis.

### After Reboot - Kernel Logs
```bash
# Find the boot ID for the freeze (if not today)
journalctl --list-boots

# Get dmesg logs from specific boot
journalctl -b -2 --system > /tmp/freeze-logs.txt

# Get kernel logs with date range for yesterday
journalctl -k -b -2 | grep -iE "amdgpu|dri|err|warn" > /tmp/kernel-logs-yesterday.txt

# Get kernel logs from specific date (e.g., Jan 31, 2026)
journalctl -k -b --since="2026-01-31" --until="2026-02-01" | grep -iE "amdgpu|dri|err|warn" > /tmp/kernel-logs-jan31.txt
```

### Current Session Logs
```bash
# Get kernel logs for current boot session
journalctl -k --since today -p err > /tmp/freeze-logs.txt

# Get full dmesg output
dmesg > /tmp/freeze-dmesg.txt

# Get amdgpu-specific logs
journalctl -k -b | grep -i amdgpu > /tmp/amdgpu-logs.txt

# Get DRI/PipeWire/SDDM errors
journalctl -k -b | grep -E "dri|pipewire|sddm" > /tmp/display-logs.txt

# Get ACPI/Power errors
journalctl -k -b | grep -iE "acpi|power|dc" > /tmp/power-logs.txt
```

### GPU Monitoring
```bash
# GPU Power readings
cat /sys/class/drm/card0/device/gsub_power

# GPU Temp
sensors --allow-no-sensors | grep -A 5 "amdgpu"
```

### Monitoring Script Logs
```bash
# Check monitoring logs
grep -E "=== |=== GPU Power ===" /var/log/sys-monitor.log

# View full monitoring log
cat /var/log/sys-monitor.log
```

---

## Research & Analysis Steps

> **Note**: Use these commands to analyze the log files you've captured. Run them against the saved log files, not directly against journalctl.

### Kernel/Driver Analysis
```bash
# Check amdgpu status from logs
grep -i amdgpu /tmp/freeze-logs.txt

# Check for DRI/PipeWire errors
grep -E "dri|pipewire|sddm" /tmp/freeze-logs.txt

# Check for KDSO issues
grep -E "kdsb|kpatch|patch" /tmp/freeze-dmesg.txt

# Check kernel warnings and errors
grep -iE "warn|err" /tmp/freeze-dmesg.txt

# Check for memory issues
grep -E "bad_page|memory|corrupt|oom" /tmp/freeze-dmesg.txt

# Check for ACPI/Power errors
grep -iE "acpi|power|dc" /tmp/freeze-logs.txt
```

### Disk/Storage Analysis
```bash
# Check filesystem errors
grep -E "FAT|usb|sd" /tmp/freeze-dmesg.txt

# Check disk health (run separately with appropriate device)
# sudo smartctl -a /dev/sdX
```

---

## 1. Thermal Monitoring

### Install Tools
```bash
sudo dnf install lm_sensors htop
sudo sensors-detect  # Answer YES to all questions
```

### Monitor Temperatures
```bash
sensors --allow-no-sensors
```

### Expected Results
Temperatures should remain below 80°C during load. If they exceed this, investigate cooling.

---

## 2. Continuous Monitoring Setup

### Create Monitoring Script
```bash
sudo tee /usr/local/bin/sys-monitor.sh << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/sys-monitor.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

{
    echo "=== $TIMESTAMP ==="
    echo "--- CPU/GPU Temps ---"
    sensors --allow-no-sensors
    echo "--- GPU Power ---"
    cat /sys/class/drm/card0/device/gsub_power
    echo "--- Memory ---"
    free -h
    echo "--- Disk I/O ---"
    iostat -x 1 3
    echo "--- Top Processes ---"
    top -b -n 1 | head -20
    echo "--- Kernel Warnings ---"
    dmesg -T | grep -iE "warn|err" | tail -10
    echo "--- Load Average ---"
    uptime
    echo ""
} >> "$LOG_FILE"
EOF

sudo chmod +x /usr/local/bin/sys-monitor.sh
```

### Run in Background
```bash
sudo nohup /usr/local/bin/sys-monitor.sh > /dev/null 2>&1 &
echo $! > /var/run/sys-monitor.pid
```

### Stop Monitoring
```bash
sudo kill $(cat /var/run/sys-monitor.pid)
```

---

## 3. GPU/Driver Issues

### Switch Display Server (Xorg)
```bash
sudo dnf install plasma-x11
# Reboot and select Xorg session in SDDM
```

### Disable Wayland for Testing
```bash
sudo tee /etc/gdm3/custom.conf << 'EOF'
[Daemon]
WaylandEnable=false
EOF
sudo systemctl daemon-reload
sudo reboot
```

### Reinstall AMDGPU Driver
```bash
sudo dnf remove amdgpu
sudo dnf install linux-firmware
sudo update-initramfs -u
sudo reboot
```

### Limit GPU Power
```bash
echo "options amdgpu dgpu=0" | sudo tee /etc/modprobe.d/amdgpu.conf
echo "options amdgpu power_profile=low" | sudo tee -a /etc/modprobe.d/amdgpu.conf
sudo update-initramfs -u
sudo reboot
```

---

## 5. Power Supply Issues

### Monitor Power Usage
```bash
# Check if PSU fan is spinning during load
# Use a multimeter to verify voltage stability
# Check for voltage drops under load
```

---

## 6. Disk I/O Issues

### Check Filesystem Health
```bash
# Check disk health
sudo smartctl -a /dev/sdX
```

### Check Disk Errors
```bash
# Run fsck if needed
sudo fsck -A -V
```

---

## 7. Kernel Panics/Freezes

### Enable Kdump (if not active)
```bash
# Check if kdump is enabled
systemctl status kdump

# Enable if needed
sudo systemctl enable kdump
```

---

## 8. Quick Monitor Commands

### Terminal 1: Temperatures
```bash
sensors --allow-no-sensors
```

### Terminal 2: Process Activity
```bash
htop
```

### Terminal 3: Load
```bash
watch -n 1 'uptime && free -h'
```

### Terminal 4: Disk
```bash
watch -n 1 'df -h && iostat -x 1'
```

---

## 9. RAM Diagnostics

### Run Memtest86
```bash
sudo dnf install memtest86-plus
# Boot from memtest86 USB drive
# Run for at least 1 pass
```

---

## Capture Checklist

When a freeze occurs:

1. Reboot the system
2. **Gather logs** (see Log Gathering Commands section above)
3. Check monitoring logs: `/var/log/sys-monitor.log`
4. Collect temperature readings
5. Share logs with Little Light for analysis

---

## Expected Results for Each Concern

| Concern | Indicator | Action |
|---------|-----------|--------|
| Thermal | Temp > 80°C | Check cooling, repaste GPU |
| Driver | DRI/PipeWire errors | Switch to Xorg, reinstall driver |
| Power | ACPI errors, voltage drops | Check PSU, RMA if defective |
| Disk | fsck errors | Check disk health, RMA if needed |
| Kernel | Panic/warning logs | Update kernel, check KDSO |
| RAM | Memtest failures | RMA RAM, run memtest |

---

## Next Steps

1. Set up continuous monitoring before next freeze
2. Monitor temperatures during load
3. Check kernel logs for errors
4. Switch to Xorg session for comparison
5. Collect logs when freeze occurs
6. Run memory test (memtest86) if other troubleshooting doesn't identify the issue
7. Share results for further analysis