# Time Shift Investigation

## Observation
The journalctl system logs show a 6-hour time jump from `11:31:04` to `17:31:05`:

```
Jan 31 11:31:04 bazzite systemd-journald[318]: Journal stopped
Jan 31 17:31:05 bazzite systemd-journald[318]: Received SIGTERM from PID 1 (systemd).
```

## Root Cause Analysis

The time jump is explained by this systemd log entry:

```
Jan 31 17:31:05 bazzite systemd[1]: RTC configured in localtime, applying delta of -360 minutes to system time.
```

### What Happened
1. The system's hardware RTC was set to UTC, but systemd was treating it as **localtime**
2. At boot (17:31:05), systemd detected the mismatch
3. It applied a correction of `-360 minutes` (6 hours) to fix the system time
4. The journal detected the clock jump and rotated the journal file

## Related Journal Message
```
Jan 31 17:31:07 bazzite systemd-journald[813]: Realtime clock jumped backwards relative to last journal entry, rotating.
```

## Implications
This is not related to the freeze/freeze issues - it's a time synchronization configuration issue.

## Recommended Fix
Set the RTC to UTC in `/etc/systemd/timesyncd.conf` or via `timedatectl`:

```bash
# Check current status
timedatectl status

# Set RTC to UTC (if it's currently set to local time)
sudo timedatectl set-local-rtc 0
```

## Notes
- The "boot" around 13:15 mentioned by the user may have been affected by this time correction
- No reboot log entry was found at 13:15 in the captured logs
- The time correction is normal behavior when systemd detects RTC/timezone mismatch