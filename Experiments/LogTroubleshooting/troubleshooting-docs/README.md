# System Freeze Troubleshooting Guide

## System Information
- **OS**: Bazzite (Fedora-based)
- **Issue**: System freezes completely, progressive loss of responsiveness
- **Affected Activities**: File copying, gaming (game save write failures)
- **Duration**: ~1 month old system
- **GPU**: AMD RX 9070/9070 XT + Radeon Graphics (dedicated GPU only)
- **Temperature**: No thermal warnings (temps < 80°C during freeze)

## Key Observations
- Freeze occurs during high CPU/GPU load (file copy, gaming)
- Progressive behavior: interface freezes first, then mouse stops responding
- Temperatures remain within safe limits
- USB filesystem wasn't properly unmounted in some logs
- PipeWire/DRI connection errors detected

---

## Monitoring Setup

### 1. Install Monitoring Tools
```bash
sudo dnf install lm_sensors htop
```

### 2. Configure Sensors
```bash
sudo sensors-detect  # Answer YES to all questions
```

### 3. Continuous Log Script
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
    cat /sys/class/drm/card0/device/gsub_power 2>/dev/null || echo "N/A"
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

### 4. Run Monitoring
```bash
# Run continuously, logging every 30 seconds
sudo nohup /usr/local/bin/sys-monitor.sh > /dev/null 2>&1 &
echo $! > /var/run/sys-monitor.pid

# Stop later: sudo kill $(cat /var/run/sys-monitor.pid)
```

### 5. Quick Terminal Monitors
```bash
# Terminal 1: Temperature
sensors --allow-no-sensors

# Terminal 2: Process activity
htop

# Terminal 3: Load
watch -n 1 'uptime && free -h'

# Terminal 4: Disk
watch -n 1 'df -h && iostat -x 1'
```

### 6. Analyze Logs After Freeze
```bash
grep -E "=== |=== GPU Power ===" /var/log/sys-monitor.log
```

---

## Concern: GPU Driver Issues

### 1. Check Driver Status
```bash
journalctl -k -b | grep -E "amdgpu|dri"
```

### 2. Check PipeWire/DRI Errors
```bash
journalctl -k -b | grep -E "dri|pipewire|sddm"
```

### 3. Check for Connection Errors
```bash
dmesg -T | grep -iE "connection|open|drm"
```

### 4. Try Xorg Session
```bash
# Install Xorg session
sudo dnf install plasma-x11

# Reboot and select Xorg session in SDDM
```

### 5. Reinstall AMDGPU Driver
```bash
sudo dnf remove amdgpu
sudo dnf install linux-firmware
sudo update-initramfs -u
sudo reboot
```

### 6. Check for Kernel Panics
```bash
journalctl -k -b | grep -iE "panic|warning|hung|lockup"
dmesg -T | grep -iE "bad_page|memory|corrupt"
```

---

## Concern: Power Delivery

### 1. Check for ACPI Errors
```bash
journalctl -k -b | grep -iE "acpi|power|dc"
```

### 2. Check Battery/Power Status
```bash
# In Bazzite
tuxedo-clx-control --status
tuxedo-keyboard --get
```

### 3. Check for Power Supply Issues
```bash
# Check if PSU fan is spinning during load
# Use a multimeter if available
```

---

## Concern: Memory (RAM)

### 1. Run Memtest86+
```bash
# Install memtest
sudo dnf install memtest86-plus

# Boot from memtest86 USB drive
# Run and wait for errors to appear
```

### 2. Check for Memory Warnings
```bash
dmesg -T | grep -iE "bad_page|memory|corrupt|oom"
journalctl -k -b | grep -iE "memory|oom|kill"
```

---

## Concern: Disk I/O

### 1. Check Filesystem Health
```bash
# Check for bad blocks
sudo badblocks -v /dev/sdX

# Check filesystem
sudo fsck -n /dev/sdX1
```

### 2. Check for USB Mount Errors
```bash
journalctl -k -b | grep -E "FAT-fs|sd 7:0:0"
```

### 3. Check Disk Usage
```bash
df -h
df -iT
```

### 4. Check for Disk Errors
```bash
journalctl -k -b | grep -E "ata|sda|sd7|block"
```

---

## Concern: Thermal Issues (Unlikely but worth checking)

### 1. Check Temperature Readings
```bash
sensors
```

### 2. Check GPU Power
```bash
cat /sys/class/drm/card0/device/gsub_temp
cat /sys/class/drm/card0/device/gsub_power
```

### 3. Check Fan Speeds
```bash
watch -n 1 'sensors | grep -E "fan|temp"'
```

---

## Concern: USB Issues

### 1. Check USB Hub Status
```bash
journalctl -k -b | grep -E "hub|usb"
```

### 2. Check for USB Errors
```bash
dmesg -T | grep -iE "usb|hub|usbcore"
```

### 3. Reboot and Remount
```bash
# If issues persist, try:
sudo umount /dev/sdX1
sudo mount /dev/sdX1 /mnt
```

---

## Concern: System Updates

### 1. Check for Pending Updates
```bash
sudo dnf check-update
sudo dnf upgrade
```

### 2. Rollback Recent Updates
```bash
# Check recent kernel versions
rpm -q kernel

# Reboot into older kernel if needed
```

### 3. Check for Bazzite Updates
```bash
# Bazzite specific
sudo bazzite upgrade
```

---

## Pre-Freeze Capture Commands

```bash
# Run these when you notice the system starting to freeze:
journalctl -k --since today -p err > /tmp/freeze-logs.txt
dmesg > /tmp/freeze-dmesg.txt
sensors --allow-no-sensors > /tmp/freeze-sensors.txt
free -h > /tmp/freeze-memory.txt
top -b -n 1 > /tmp/freeze-top.txt
```

---

## After Freeze - Analysis Commands

```bash
# Kernel logs
journalctl -k --since today | grep -iE "warn|err|panic|crash|freeze|hang"

# Driver logs
journalctl -u sddm -b
journalctl -u pipewire -b

# Memory logs
journalctl -k | grep -iE "oom|kill|memory"

# GPU logs
journalctl -k | grep -iE "amdgpu|drm"
```