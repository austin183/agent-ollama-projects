# ACPI & Power Analysis
**Date:** 2026-02-01
**Log Source:** `Logs-2026-0131/greps/acpi_power_dc_journalctl_system.txt`

## Summary
Analysis of ACPI-related entries and power management logs from the affected system (Bazzite Linux) to identify potential contributors to system freezes.

## Key Findings

### 1. Battery Service Initialization Issue
```
Jan 31 11:31:02 bazzite systemd[1]: systemd-battery-check.service - Check battery level during early boot was skipped because of an unmet condition check (ConditionDirectoryNotEmpty=/sys/class/power_supply).
```
**Potential Impact:** The battery subsystem may not have been fully initialized before the power check service tried to run. This could indicate issues with power supply detection.

### 2. Power Resource Initialization
Multiple power resources were registered during boot:
```
Jan 31 11:31:01 bazzite kernel: ACPI: \_SB_.PCI0.GPP0.M237: New power resource
Jan 31 11:31:01 bazzite kernel: ACPI: \_SB_.PCI0.GPP0.SWUS.M237: New power resource
Jan 31 11:31:01 bazzite kernel: ACPI: \_SB_.PCI0.GPP0.SWUS.SWDS.M237: New power resource
```
**Potential Impact:** These resources control PCIe lanes and potentially other hardware functions. Issues with power state transitions can cause freezes.

### 3. Panel Self-Refresh (PSR) Support - Repeated Messages
```
Jan 31 11:31:04 bazzite kernel: amdgpu 0000:03:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
```
**Occurrences:** Lines 123-129, multiple times for different GPUs
**Potential Impact:** PSR is a power-saving feature for displays. AMDGPU not reporting PSR support may indicate a display/driver configuration issue that could affect system stability, especially during power transitions.

### 4. KDE Power Devil Services
```
Jan 31 17:31:22 bazzite.something.smwhre systemd[1]: Started dbus-:1.3-org.kde.powerdevil.discretegpuhelper@0.service.
Jan 31 17:31:32 bazzite.something.smwhre systemd[1]: dbus-:1.3-org.kde.powerdevil.discretegpuhelper@0.service: Deactivated successfully.
```
**Observation:** KDE power management services started and immediately deactivated.
**Potential Impact:** Power management conflicts with desktop environment could contribute to instability.

### 5. SDDM Crash During Power Off
```
Jan 31 17:34:24 bazzite.something.smwhre sddm[1789]: Auth: sddm-helper (--socket /tmp/sddm-auth-fa820e0e-dc06-430f-9256-5f742d7fd8b0 --id 1 --start /usr/libexec/plasma-dbus-run-session-if-needed /usr/bin/startplasma-wayland --user projectUser) crashed (exit code 1)
```
**Timing:** Occurred just before system poweroff
**Potential Impact:** Session manager crash during power transition may indicate memory or process handling issues during shutdown.

### 6. ACPI Interpreter
```
Jan 31 11:31:01 bazzite kernel: ACPI: Interpreter enabled
Jan 31 11:31:01 bazzite kernel: ACPI: Core revision 20250404
```
**Observation:** ACPI interpreter is enabled and running.
**Potential Impact:** Generally normal, but complex ACPI tables (15 tables loaded) can sometimes cause issues if they have bugs or if hardware responds unpredictably to AML code.

## System Shutdown Sequence
```
Jan 31 17:34:24 bazzite.something.smwhre systemd-logind[1389]: The system will power off now!
Jan 31 17:34:24 bazzite.something.smwhre systemd-logind[1389]: System is powering down.
Jan 31 17:34:24 bazzite.something.smwhre systemd[1]: Stopping upower.service
```
**Potential Impact:** The system shutdown appears clean in this log, which suggests the freeze may have occurred during different power states (suspend/standby) rather than shutdown.

## Potential Contributing Factors

1. **Display Driver Issues** - AMDGPU PSR not being reported
2. **Power Management Conflicts** - KDE Power Devil services starting/stopping rapidly
3. **Battery Subsystem** - Battery service skipped due to directory not existing
4. **Session Management** - SDDM crash during power transition
5. **ACPI Table Issues** - 15 ACPI AML tables loaded, potential for edge cases

## Recommendations
1. Monitor display driver logs (`journalctl -k --grep amdgpu`)
2. Check `journalctl -u upower -u systemd-battery-check`
3. Verify AMDGPU firmware is up to date
4. Monitor KDE Power Devil behavior
5. Check for ACPI warnings in kernel logs during suspend/resume cycles