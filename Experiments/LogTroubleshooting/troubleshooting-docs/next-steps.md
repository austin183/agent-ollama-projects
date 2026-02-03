# Next Steps - System Freeze Troubleshooting

**Last Updated**: 2026-02-01
**Status**: MemTest86+ ✅ PASSED | NVMe SMART ✅ PASSED

---

## Completed Tests

### 1. MemTest86+ ✅ COMPLETE
**Result**: **PASSED**
**Conclusion**: RAM module is likely fine. No RMA needed.

---

### 2. NVMe SMART Health Check ✅ COMPLETE
**Result**: **PASSED**
**Conclusion**: NVMe drive is healthy. No RMA needed.

| Metric | Value | Status |
|--------|-------|--------|
| SMART Health Assessment | PASSED | ✅ |
| Critical Warning | 0x00 | ✅ |
| Temperature | 27°C | ✅ |
| Available Spare | 100% | ✅ |
| Percentage Used | 0% | ✅ |
| Media/Integrity Errors | 0 | ✅ |
| Error Log Entries | 0 | ✅ |
| Unsafe Shutdowns | 13 | ⚠️ Likely from freeze-related shutdowns |

---

## High Priority Tests

### 3. Xorg vs Wayland Testing 🔴
**Why**: Multiple logs showed GPU/DRI issues, missing depth buffer support, and SDDM crashes on Wayland.

**Steps**:
```bash
# Install Xorg session
sudo dnf install plasma-x11

# Alternative: Disable Wayland temporarily
sudo tee /etc/gdm3/custom.conf << 'EOF'
[Daemon]
WaylandEnable=false
EOF
sudo systemctl daemon-reload
sudo reboot
```

**Success Criteria**:
- Freeze does not occur on Xorg → GPU/DRI driver issue
- Freeze still occurs → Hardware or power supply issue

**If freeze stops on Xorg**:
- Investigate AMDGPU driver versions, Mesa packages
- Check if firmware updates are needed
- Consider downgrading problematic driver components

---

### 4. Update AMDGPU Driver & Firmware 🟡
**Why**: Log analysis found SMU firmware version mismatch:
```
smu driver if version = 0x0000002e, smu fw if version = 0x00000032
```

**Steps**:
```bash
# Update system (Bazzite)
sudo dnf upgrade

# Check for AMDGPU updates
sudo dnf check-update | grep amdgpu
sudo dnf install --enablerepo=updates-testing amdgpu*

# Reboot and test
sudo reboot
```

**If no updates available**:
- Check BIOS/UEFI for GPU firmware updates
- Verify BIOS version matches GPU specifications

---

### 5. USB Storage Stability Test 🟢
**Why**: USB drive was improperly unmounted and UAS driver may be unstable.

**Steps**:
```bash
# Test with different USB ports
# Test with different controllers if available

# Try disabling UAS driver (temporary)
sudo modprobe -r uas usb-storage
sudo modprobe usb-storage
# Remove and re-insert USB drive

# Or force UAS for specific device
echo "options usb-storage quirks=18a5:0243:u" | sudo tee /etc/modprobe.d/usb-storage.conf
sudo update-initramfs -u
sudo reboot
```

---

## Medium Priority Investigations

### 6. GPU Power Limiting 🔵
**Why**: If driver issues are suspected but MemTest passes, limiting GPU power may help.

**Steps**:
```bash
# Create AMDGPU configuration
echo "options amdgpu power_profile=auto" | sudo tee /etc/modprobe.d/amdgpu.conf
echo "options amdgpu dpm=1" | sudo tee -a /etc/modprobe.d/amdgpu.conf
echo "options amdgpu lockup_timeout=10000" | sudo tee -a /etc/modprobe.d/amdgpu.conf
echo "options amdgpu.gpu_recovery=1" | sudo tee -a /etc/modprobe.d/amdgpu.conf

# Reboot and test
sudo update-initramfs -u
sudo reboot
```

---

### 7. Kernel Parameter Tuning 🔵
**Why**: NVMe controller may benefit from tuning.

**Steps**:
```bash
# Create NVMe configuration
echo "options nvme_core.default_ps_max_latency_us=0" | sudo tee /etc/modprobe.d/nvme.conf
echo "options nvme_core.poll_queues=4" | sudo tee -a /etc/modprobe.d/nvme.conf

# Reboot and test
sudo update-initramfs -u
sudo reboot
```

---

### 8. Disable BTRFS Async Discard 🔵
**Why**: Async discard can cause latency spikes on flash storage.

**Steps**:
```bash
# Disable async discard for BTRFS
sudo mount -o remount,flushoncompletewrite /
# Or for persistent config, edit /etc/fstab and add "nodiscard"
```

---

## Low Priority / Documentation

### 9. Gather Pre-Freeze Monitoring Data 📊
**Before next freeze attempt**, run these continuously:

```bash
# Terminal 1: GPU logs
journalctl -k --follow -p err --grep "amdgpu|drm|gpu"

# Terminal 2: Memory checks
watch -n 5 'free -h && journalctl -k -1 | grep -iE "bad_page|memory|corrupt"'

# Terminal 3: Storage
watch -n 5 'iostat -x 1'

# Terminal 4: Power
watch -n 5 'sensors --allow-no-sensors'
```

---

### 10. Check for Pending System Updates 🔵
```bash
# Bazzite specific
sudo bazzite upgrade

# Fedora/Kernel updates
sudo dnf check-update
sudo dnf upgrade

# Kernel downgrade options (if newer kernels cause issues)
sudo dnf list --installed | grep kernel
```

---

## Decision Tree

```
MemTest86+ Results
├── PASS (0 errors) → Continue with other tests
└── FAIL (>0 errors) → RMA RAM module

NVMe SMART Results
├── PASS → Continue with other tests
└── FAIL → RMA NVMe drive

If freeze persists:
├── Xorg test → Freeze stops?
│   ├── Yes → GPU/DRI driver issue → Update AMDGPU/Mesa
│   └── No → Hardware/Power issue
├── GPU Power Limiting → Freeze stops?
│   ├── Yes → GPU driver tuning needed
│   └── No → Power supply or motherboard
└── System updates available?
    └── Yes → Apply and test
```

---

## RMA Decision Matrix

| Symptom | RMA Component | Reason |
|---------|---------------|--------|
| MemTest fails | RAM module | Direct memory errors |
| NVMe SMART critical errors | SSD/NVMe drive | Hardware failure |
| Freeze only on Wayland | GPU driver | Software issue |
| Freeze only on Xorg | GPU/Motherboard | Hardware |
| ACPI errors persist | Motherboard/BIOS | Power delivery |
| PSU fan doesn't spin under load | Power Supply | Voltage instability |
| All tests pass | Warranty/Return | Unresolved hardware issue |

---

## Summary of Pending Actions

1. **Xorg vs Wayland test** - HIGH PRIORITY (isolate GPU/DRI issue)
2. **Update AMDGPU driver/firmware** - HIGH PRIORITY (address SMU version mismatch)
3. **USB stability test** - MEDIUM PRIORITY
4. **GPU power limiting** - MEDIUM PRIORITY
5. **Kernel parameter tuning** - MEDIUM PRIORITY
6. **Gather pre-freeze monitoring data** - CRITICAL for next analysis

---

## Files to Review

- `/var/log/sys-monitor.log` - Temperature/power during load
- `nvme_smartctl_all.log` - NVMe health
- Kernel logs after next freeze attempt
- Any new error logs from MemTest86+