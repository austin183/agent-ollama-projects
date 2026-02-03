# Quick Troubleshooting Checklist

## Setup (Run Once)

- [ ] Install `lm_sensors` and `htop`
- [ ] Run `sensors-detect` (answer YES)
- [ ] Create monitoring script at `/usr/local/bin/sys-monitor.sh`
- [ ] Make script executable: `chmod +x /usr/local/bin/sys-monitor.sh`
- [ ] Start monitoring: `nohup /usr/local/bin/sys-monitor.sh &`

---

## When Freeze Occurs

- [ ] Reboot system
- [ ] Capture kernel logs: `journalctl -k --since today -p err > /tmp/freeze-logs.txt`
- [ ] Capture dmesg: `dmesg > /tmp/freeze-dmesg.txt`
- [ ] Check monitoring logs: `/var/log/sys-monitor.log`
- [ ] Take temperature readings: `sensors --no-thermal`
- [ ] Check memory status: `free -h`

---

## Testing Options

- [ ] **Switch to Xorg**: `sudo dnf install plasma-x11`, reboot, select Xorg
- [ ] **Disable Wayland**: `sudo tee /etc/gdm3/custom.conf` with `WaylandEnable=false`
- [ ] **Run Memtest86**: `sudo dnf install memtest86-plus`, boot from USB
- [ ] **Reinstall amdgpu**: `sudo dnf remove amdgpu && sudo dnf install linux-firmware`
- [ ] **Limit GPU power**: Add `options amdgpu power_profile=low` to `/etc/modprobe.d/amdgpu.conf`

---

## Diagnostic Commands

| Command | Purpose |
|---------|---------|
| `sensors` | Check temperatures |
| `htop` | Monitor CPU/Process usage |
| `uptime` | Check load average |
| `free -h` | Check memory usage |
| `iostat -x 1` | Check disk I/O |
| `journalctl -k -b | grep amdgpu` | GPU driver logs |
| `dmesg -T | grep -iE "warn|err"` | Kernel warnings |
| `cat /sys/class/drm/card0/device/gsub_power` | GPU power usage |

---

## Files to Collect

- `/tmp/freeze-logs.txt` - Kernel error logs
- `/tmp/freeze-dmesg.txt` - Kernel ring buffer
- `/var/log/sys-monitor.log` - Continuous monitoring
- Temperature screenshots
- Process list screenshots

---

## When to RMA

| Symptom | Component to RMA |
|---------|------------------|
| Temp > 80°C sustained | GPU/Thermal paste |
| Memtest errors | RAM module |
| ACPI errors, voltage drops | Power Supply |
| fsck errors, SMART errors | SSD/HDD |
| Persistent kernel panics | Motherboard/BIOS |
| Freeze only on Wayland | Graphics driver |
| Freeze only on Xorg | Hardware |

---

## Troubleshooting Concerns

| Concern | Key Indicator | Solution |
|---------|---------------|----------|
| Thermal | Temp > 80°C | Check cooling, repaste |
| Driver | DRI/PipeWire errors | Switch to Xorg, reinstall driver |
| RAM | Memtest failures | RMA RAM |
| Power | ACPI errors | Check PSU, RMA if needed |
| Disk | fsck errors | Check disk health, RMA if needed |
| Kernel | Panic/warning logs | Update kernel, check KDSO |

---

## Additional Resources

- Bazzite forum
- AMDGPU documentation
- Memtest86 manual
- TLP power management guide