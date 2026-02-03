# AMDGPU Driver Analysis
**Date:** 2026-02-01
**Log Source:** `Logs-2026-0131/greps/amdgpugrep_journalctl_system.txt`

## Summary
Analysis of AMDGPU kernel driver logs from the affected system (Bazzite Linux) to identify potential contributors to system freezes. The system has two AMD GPUs: an RX 7600 (PCIe 0:03:00.0) and an RX 6600 (PCIe 0:0d:00.0).

## Key Findings

### 1. SMU Firmware Version Mismatch Warning
```
Jan 31 11:31:03 bazzite kernel: amdgpu 0000:03:00.0: amdgpu: smu driver if version = 0x0000002e, smu fw if version = 0x00000032, smu fw program = 0, smu fw version = 0x00684b00 (104.75.0)
Jan 31 11:31:03 bazzite kernel: amdgpu 0000:03:00.0: amdgpu: SMU driver if version not matched
```
**Potential Impact:** The System Management Unit (SMU) firmware and driver versions don't match. This can cause the GPU to operate in an unstable state, especially during power transitions. SMU handles thermal management, voltage control, and power limits.

### 2. PSR Support Not Detected - Repeated Messages
```
Jan 31 11:31:04 bazzite kernel: amdgpu 0000:03:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
```
**Occurrences:** Lines 123-129, multiple times for different GPUs
**Potential Impact:** Panel Self-Refresh is a power-saving feature that reduces display refresh when idle. AMDGPU not detecting PSR support may indicate a display cable, eDP controller, or firmware issue that can affect power management stability.

### 3. REG_WAIT Timeout During Initialization
```
Jan 31 11:31:04 bazzite kernel: amdgpu 0000:03:00.0: [drm] REG_WAIT timeout 1us * 150000 tries - optc401_disable_crtc line:230
Jan 31 11:31:04 bazzite kernel: amdgpu 0000:03:00.0: [drm] REG_WAIT timeout 1us * 150000 tries - optc401_disable_crtc line:230
Jan 31 11:31:04 bazzite kernel: amdgpu 0000:0d:00.0: [drm] REG_WAIT timeout 1us * 150000 tries - optc401_disable_crtc line:230
```
**Occurrences:** Three timeout errors during initialization
**Potential Impact:** The Display Controller (DCN) hardware is not responding to register writes within the expected time. This indicates communication issues between the driver and display hardware, which can lead to hangs during display mode changes or wake-ups.

### 4. VCN Firmware Version Mismatch
```
Jan 31 11:31:03 bazzite kernel: amdgpu 0000:03:00.0: amdgpu: Found VCN firmware Version ENC: 1.11 DEC: 9 VEP: 0 Revision: 1
Jan 31 11:31:04 bazzite kernel: amdgpu 0000:0d:00.0: amdgpu: Found VCN firmware Version ENC: 1.33 DEC: 4 VEP: 0 Revision: 14
```
**Potential Impact:** VCN (Video Compression Engine) handles video decoding. Version mismatches can cause instability during video playback or transcoding tasks.

### 5. Runtime Power Management Not Available
```
Jan 31 11:31:04 bazzite kernel: amdgpu 0000:0d:00.0: amdgpu: Runtime PM not available
```
**Potential Impact:** One GPU's runtime power management is disabled. This means the GPU cannot be dynamically powered up/down, potentially causing excessive power draw during idle states.

### 6. Memory Initialization Warnings
```
Jan 31 11:31:03 bazzite kernel: amdgpu 0000:03:00.0: amdgpu: Trusted Memory Zone (TMZ) feature not supported
Jan 31 11:31:03 bazzite kernel: amdgpu 0000:03:00.0: amdgpu: MEM ECC is not presented.
Jan 31 11:31:03 bazzite kernel: amdgpu 0000:03:00.0: amdgpu: SRAM ECC is not presented.
```
**Potential Impact:** These are informational rather than warnings, but indicate that GPU memory error correction features are not available. While not directly causing freezes, this removes a safety mechanism for memory errors.

### 7. BACO (Bus-Aware Coefficient Oscillation)
```
Jan 31 11:31:04 bazzite kernel: amdgpu 0000:03:00.0: amdgpu: Using BACO for runtime pm
```
**Potential Impact:** BACO is an alternate low-power state. If this mechanism has bugs, it could cause the GPU to fail to return from power-down state.

### 8. No DPCD PSR Capabilities Reported
```
Jan 31 11:31:04 bazzite kernel: amdgpu 0000:0d:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
```
**Potential Impact:** The DisplayPort sink (monitor) is not reporting PSR capabilities. This is often due to incompatible display cable or firmware, and can affect power transition stability.

## GPU Hardware Summary

| Device | PCI Address | GPU Model | VRAM | IP Blocks |
|--------|-------------|-----------|------|-----------|
| GPU 1 | 0000:03:00.0 | RX 7600 (Red Devil) | 16GB | SOC24, GMC, IH, PSP, SMU, DM, GFX, SDMA, VCN, JPEG, MES |
| GPU 2 | 0000:0d:00.0 | RX 6600 | 512MB | NAVI10, GMC, IH, PSP, SMU, DM, GFX, SDMA, VCN, JPEG |

## Potential Contributing Factors

1. **SMU Firmware Mismatch** - Driver and firmware versions don't align, causing unstable power management
2. **Display Controller Communication** - REG_WAIT timeouts indicate display hardware communication issues
3. **PSR Feature Unsupported** - Panel Self-Refresh not detected affects power management
4. **Runtime PM Issues** - One GPU lacks runtime power management capability
5. **VCN Version Mismatch** - Video engine firmware may not be optimal

## Recommendations

1. **Update AMDGPU firmware** - Ensure both GPU firmwares are up to date via kernel updates
2. **Monitor for REG_WAIT errors during freeze** - Capture logs when freeze occurs
3. **Test with Xorg** - Switch display server to isolate GPU driver issues
4. **Check AMDGPU kernel module options** - Consider `options amdgpu power_profile=1` or `pm=no_console_suspend`
5. **Monitor GPU temperatures** - Use `sensors` or `radeontop` to check for thermal issues
6. **Verify display cable** - Try a different cable for better DPCD capability reporting
7. **Check kernel version** - Ensure Linux kernel is current and contains AMDGPU fixes

## Additional Diagnostic Commands

```bash
# Check current driver status
lsmod | grep amdgpu
modinfo amdgpu

# View detailed kernel logs for amdgpu
journalctl -k --since today | grep -i amdgpu

# Monitor GPU activity
radeontop -b

# Check GPU power usage
cat /sys/class/drm/card*/device/gsub_power

# Monitor thermal status
sensors | grep -i amdgpu
```