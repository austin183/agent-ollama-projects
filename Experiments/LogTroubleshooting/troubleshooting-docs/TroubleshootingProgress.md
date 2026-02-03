# System Freeze Troubleshooting Progress Log

**Date**: 2026-02-01
**System**: Bazzite (Fedora-based)
**Issue**: Progressive system freeze (interface freezes first, then mouse stops responding)
**System Age**: ~1 month

---

## Investigation Log

### Session 1 - Initial Setup

#### ✅ Completed: Monitor Tools Installation
- **Date**: 2026-02-01
- **Actions**:
  - Installed `lm_sensors` and `htop`
  - Ran `sudo sensors-detect` and answered YES to all questions
  - Attempted `sensors --no-thermal` (incorrect flag)

#### ✅ Found: Correct sensors Usage
- **Date**: 2026-02-01
- **Discovery**: The correct flag is `--allow-no-sensors`, not `--no-thermal`
- **Command**: `sensors --allow-no-sensors`

#### ✅ Completed: Temperature & Power Check
- **Date**: 2026-02-01
- **Readings**:
  - CPU/SoC Temp: 30°C (well below 80°C threshold)
  - Ecore00X High: 167 J
  - GPU (amdgpu-pci-0300): PPT 21W / 317W cap, vddgfx 207 mV
- **Conclusion**: Thermal issues are UNLIKELY to be causing freezes

---

## Next Steps (To Do)

### Priority 1: Driver/Display Server Issues
- [ x ] Check PipeWire/DRI connection errors: `journalctl -k --since today -p err | grep -E "dri|pipewire|sddm"`
- [ ] Try Xorg session for comparison: `sudo dnf install plasma-x11`
- [ ] Reinstall AMDGPU driver if needed

### Priority 2: RAM Diagnostics
- [ in progress ] Run Memtest86+: `sudo dnf install memtest86-plus`

### Priority 3: Disk I/O
- [ x ] Check for USB mount errors after freeze: `journalctl -k --since today | grep -E "FAT-fs|sd 7:0:0"`
- [ ] Check disk health: `sudo smartctl -a /dev/sdX`

### Priority 4: Power Supply
- [ x ] Check ACPI/Power errors: `journalctl -k --since today | grep -iE "acpi|power|dc"`

---

Observations documented in `*-analysis.md` files and `LogAnalysis.md`