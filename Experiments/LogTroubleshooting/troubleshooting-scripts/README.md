# Troubleshooting Scripts

This directory contains helper scripts to automate the diagnostic commands described in the Troubleshooting Guide.

## Usage

Make sure the scripts are in your PATH or run them from this directory:

```bash
cd /path/to/troubleshooting-scripts
./check-all.sh
```

## Available Scripts

### `check-all.sh`
Run all troubleshooting checks at once. Captures temperatures, GPU logs, disk health, power info, and kernel issues into timestamped files.

### `check-gpu-driver.sh`
Check amdgpu driver status, DRI/PipeWire errors, and GPU performance.

### `check-disk-health.sh`
Check filesystem errors, disk usage, and SMART health status.

### `check-power-system.sh`
Check ACPI logs, power supply status, and battery information.

### `check-kernel-issues.sh`
Check for kernel panics, warnings, OOM events, and memory corruption.

### `capture-freeze-logs.sh`
Capture comprehensive logs after a system freeze for analysis.

### `monitor-temps.sh`
Monitor temperatures continuously (default: every 5 seconds). Press Ctrl+C to stop.

### `setup-continuous-monitoring.sh`
Set up the continuous monitoring script described in the troubleshooting guide. Must run with sudo.

### `run-memtest.sh`
Display information about memory diagnostics and how to run Memtest86.

## Example Workflows

### After a Freeze Occurs
```bash
./capture-freeze-logs.sh
```

### Before a Freeze (Proactive)
```bash
./check-all.sh
```

### Continuous Monitoring During Load
```bash
./monitor-temps.sh  # In terminal 1
htop                # In terminal 2
```

### Setup Continuous Monitoring
```bash
sudo ./setup-continuous-monitoring.sh
tail -f /var/log/sys-monitor.log
```