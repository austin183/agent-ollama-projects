# Storage Analysis

## Date
2026-01-31

## Summary
Analysis of storage-related kernel and systemd messages to identify potential contributors to system freezes.

## NVMe Storage (Internal)

### Log Entries
| Time | Message | Analysis |
|------|---------|----------|
| 11:31:02 | `nvme nvme0: bad crto:14 cap:8100030f00100ff` | **WARNING** - "bad crto" indicates a controller-reported time value issue. This may indicate hardware problems with the NVMe controller. |
| 11:31:02 | `nvme nvme0: allocated 64 MiB host memory buffer` | Normal initialization - 64MB host memory buffer allocated for NVMe operations. |
| 11:31:02 | `nvme nvme0: 16/0/0 default/read/poll queues` | Normal NVMe queue configuration. |
| 11:31:04 | `BTRFS: device label bazzite_bazzite devid 1 transid 5382 /dev/nvme0n1p6` | BTRFS filesystem detected. |
| 11:31:04 | `BTRFS info (device nvme0n1p6): first mount` | First mount of BTRFS filesystem 23c09f1d-5446-49d1-a5cf-a50a020c9e64. |
| 11:31:04 | `BTRFS info (device nvme0n1p6): using crc32c (crc32c-lib) checksum algorithm` | BTRFS configured with CRC32C checksums. |
| 11:31:04 | `BTRFS info (device nvme0n1p6): enabling ssd optimizations` | BTRFS SSD optimizations enabled. |
| 11:31:04 | `BTRFS info (device nvme0n1p6): turning on async discard` | Async discard enabled - may cause latency issues. |
| 11:31:04 | `BTRFS info (device nvme0n1p6): enabling free space tree` | Free space tree feature enabled for BTRFS. |
| 17:31:08 | `nvme nvme0: using unchecked data buffer` | **WARNING** - NVMe driver using unchecked data buffer mode. This could indicate potential data integrity issues. |
| 17:31:08 | `smartd[1360]: Device: /dev/nvme0, SLEG-860-1TBI-S58` | SMART monitoring enabled for the NVMe drive (SLEG-860-1TBI-S58). |
| 17:31:08 | `smartd[1360]: Monitoring 1 NVMe devices` | Smartd actively monitoring the drive. |
| 17:31:08 | `block nvme0n1: No UUID available providing old NGUID` | Device identifier via NGUID instead of UUID. |

### Issues Identified

1. **bad crto warning** - The "bad crto" message indicates a problem with the controller-reported timeout value. This can lead to unpredictable NVMe operation behavior and potential hangs.

2. **unchecked data buffer** - Using unchecked data buffer mode may expose the system to data corruption issues, especially during heavy I/O operations.

3. **BTRFS async discard** - Async discard operations can cause unexpected latency spikes, particularly on flash storage.

### Recommendations

- Monitor SMART status regularly using `smartctl -a /dev/nvme0`
- Consider disabling BTRFS async discard if latency issues persist
- Investigate if "bad crto" can be fixed via kernel parameters or BIOS settings
- Run `btrfs scrub` regularly to detect and correct any data corruption

---

## USB Storage (External)

### Log Entries
| Time | Message | Analysis |
|------|---------|----------|
| 17:33:52 | `usb 2-1: new SuperSpeed USB device number 2` | Verbatim STORE N GO USB drive detected on bus 2. |
| 17:33:52 | `usb-storage 2-1:1.0: USB Mass Storage device detected` | USB mass storage driver loaded. |
| 17:33:52 | `usbcore: registered new interface driver uas` | UAS (USB Attached SCSI) driver registered. |
| 17:33:54 | `sd 7:0:0:0: [sda] 121145344 512-byte logical blocks` | 62.0 GB Verbatim drive detected as /dev/sda. |
| 17:33:54 | `sd 7:0:0:0: [sda] Write cache: disabled` | Write cache disabled on the USB drive. |
| 17:34:10 | `FAT-fs (sda1): Volume was not properly unmounted` | **CRITICAL** - Drive was hot-plugged or not properly unmounted. Data corruption possible. |
| 17:34:24 | `sddm-helper[2108]: Signal received: SIGTERM` | Session helper crashed. No direct correlation to USB storage. |

### Issues Identified

1. **Improper unmount** - The USB drive (/dev/sda1) was not properly unmounted before being removed or before shutdown. This can lead to file system corruption and potential system instability.

2. **UAS driver** - The UAS driver was used, which can sometimes be unstable with certain USB drives or controllers.

### Recommendations

- Always use `sync` and `umount` before removing USB drives
- Consider testing with `usb-storage` driver instead of UAS (`options usb-storage quirks=18a5:0243:u`) if UAS causes issues
- Check filesystem integrity with `fsck.vfat /dev/sda1` after improper removal

---

## FAT Filesystem (Internal /dev/nvme0n1p1)

### Log Entries
| Time | Message | Analysis |
|------|---------|----------|
| 17:31:06 | `systemd-fsck[970]: fsck.fat 4.2 (2021-01-31)` | FAT filesystem check running. |
| 17:31:06 | `/dev/nvme0n1p1: 215 files, 19306/65536 clusters` | 215 files, 19306 of 65536 clusters used on internal FAT partition. |
| 17:31:08 | `ublue-os-media-automount.py[1368]: Skipping /dev/nvme0n1p1: unsupported filesystem type 'vfat'` | Automount script skipping the FAT partition. |

### Analysis
- The FAT partition on nvme0n1p1 appears healthy (fsck passed successfully)
- No issues found in this log entry

---

## EXT4 Filesystem (Internal /dev/nvme0n1p3)

### Log Entries
| Time | Message | Analysis |
|------|---------|----------|
| 17:31:06 | `EXT4-fs (nvme0n1p3): mounted filesystem r/w with ordered data mode` | EXT4 filesystem mounted successfully. |
| 17:31:06 | `EXT4-fs (nvme0n1p3): Quota mode: none` | Quotas disabled. |
| 17:31:08 | `ublue-os-media-automount.py[1368]: Skipping /dev/nvme0n1p3: already in fstab` | Already mounted via fstab. |

### Analysis
- EXT4 filesystem mounted successfully with no errors
- No issues found in this log entry

---

## BTRFS Filesystem (Internal /dev/nvme0n1p6)

### Log Entries
| Time | Message | Analysis |
|------|---------|----------|
| 11:31:04 | `BTRFS: device label bazzite_bazzite devid 1 transid 5382 /dev/nvme0n1p6` | BTRFS root filesystem detected. |
| 11:31:04 | `BTRFS info (device nvme0n1p6): first mount` | First mount of BTRFS root filesystem. |
| 11:31:04 | `BTRFS info (device nvme0n1p6): enabling ssd optimizations` | SSD optimizations enabled for BTRFS. |
| 11:31:04 | `BTRFS info (device nvme0n1p6): turning on async discard` | Async discard enabled. |
| 11:31:04 | `BTRFS info (device nvme0n1p6): enabling free space tree` | Free space tree enabled. |

### Analysis
- BTRFS root filesystem mounted successfully
- Standard BTRFS configuration for SSD

---

## Potential Freeze Contributors

### High Priority

1. **NVMe "bad crto" warning** - This controller timeout issue could cause NVMe operations to hang, especially under heavy load.

2. **NVMe unchecked data buffer** - May indicate firmware or driver issues that could lead to data corruption and system instability.

3. **Improper USB drive unmount** - File system corruption could potentially affect the system if the drive was still mounted during shutdown.

### Medium Priority

4. **BTRFS async discard** - Can cause latency spikes during background operations.

5. **UAS driver instability** - USB Attached SCSI driver can be problematic with certain USB drives/controllers.

### Low Priority

6. **Multiple USB hubs** - The system has multiple USB controllers and hubs, which can occasionally cause enumeration issues.

---

## Recommended Testing Steps

1. **NVMe Diagnostics**
   ```bash
   smartctl -a /dev/nvme0
   smartctl -i /dev/nvme0
   btrfs scrub start -B -R /mnt
   ```

2. **USB Storage Stability**
   - Test with different USB ports/controllers
   - Try disabling UAS: `sudo modprobe -r usb-storage uas && sudo modprobe usb-storage`

3. **BTRFS Tuning**
   ```bash
   # Check if async discard causes issues
   sudo findmnt -T / | grep discard
   ```

4. **Kernel Parameter Investigation**
   - Research `nvme_core.poll_queues` and other NVMe tuning parameters
   - Consider adding `nvme_core.default_ps_max_latency_us=0` if needed

---

## Related Issues

This analysis should be considered alongside:
- `amdgpu_analysis.md` - GPU-related freeze issues
- `dri_pipewire_sddm_analysis.md` - Display/DRI/PipeWire related issues
- `memory_analysis.md` - Memory subsystem issues

## Conclusion

The most likely storage-related contributors to system freezes are:
1. NVMe controller timeout issues ("bad crto")
2. NVMe unchecked data buffer mode
3. Improper USB drive handling

Further investigation of SMART status and testing NVMe/USB configurations is recommended.