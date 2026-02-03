

Pastebin Service
Create
API
About
UNTITLED
From WebUI, 5 Minutes ago, written in Plain Text.
This paste will perish in 23 Hours.
URL https://paste.centos.org/view/a5c704a7
Embed Show code
Download Paste or View Raw
##############################################################################
### file 1 of 3: 63
##############################################################################
State: idle
Deployments:
● ostree-image-signed:docker://ghcr.io/ublue-os/bazzite:stable
                   Digest: sha256:4a03ff61db88c7e4a414e3d77fb2378aaa3c9b626d36448c63ac7d1267701761
                  Version: 43.20260126 (2026-01-26T05:15:38Z)
 
  ostree-image-signed:docker://ghcr.io/ublue-os/bazzite:stable
                   Digest: sha256:fdc77a8b5a08b3bf89063cb02ba8b1e3cb61a09ad776fcfb3c657314e55af729
                  Version: 43.20260118 (2026-01-19T05:13:02Z)
##############################################################################
### file 2 of 3: 62
##############################################################################
=== fpaste 0.5.0.0 System Information ===
* OS Release (lsb_release -ds):
     "Bazzite"
     
* CPU Model (grep 'model name' /proc/cpuinfo | awk -F: '{print $2}' | uniq -c |
     sed -re 's/^ +//' ):
     16  AMD Ryzen 7 9800X3D 8-Core Processor
     
* 64-bit Support (grep -q ' lm ' /proc/cpuinfo && echo Yes || echo No):
     Yes
     
* Hardware Virtualization Support (grep -Eq '(vmx|svm)' /proc/cpuinfo && echo Yes || echo No):
     Yes
     
* Kernel (uname -r):
     6.17.7-ba25.fc43.x86_64
     
* Kernel cmdline (cat /proc/cmdline):
     BOOT_IMAGE=(hd0,gpt3)/ostree/default-374696162330b925549cee64679444d2440b032ade6a444374bbbc9dc43853ec/vmlinuz-6.17.7-ba25.fc43.x86_64 ostree=/ostree/boot.0/default/374696162330b925549cee64679444d2440b032ade6a444374bbbc9dc43853ec/0 rhgb quiet root=UUID=23c09f1d-5446-49d1-a5cf-a50a020c9e64 vconsole.keymap=us rootflags=subvol=root rw bluetooth.disable_ertm=1
     
* Desktop(s) Running (without results: "ps -eo comm= | grep -E '(gnome-session|startkde|startactive|xfce.?-session|fluxbox|blackbox|hackedbox|ratpoison|enlightenment|icewm-session|od-session|wmaker|wmx|openbox-lxde|openbox-gnome-session|openbox-kde-session|mwm|e16|fvwm|xmonad|sugar-session|mate-session|lxqt-session|cinnamon|lxdm-session|awesome|phosh|sway|Hyperland)' "):
     N/A
 
* Desktop(s) Installed (ls -m /usr/share/{xsessions,wayland-sessions}/ | sed 's/\.desktop//g' ):
     /usr/share/wayland-sessions/:
     plasma
     
     /usr/share/xsessions/:
     
* Session Type (env | grep 'XDG_SESSION_TYPE' | sed 's/.*=//' ):
     wayland
     
* SELinux Status (sestatus):
     SELinux status:                 enabled
     SELinuxfs mount:                /sys/fs/selinux
     SELinux root directory:         /etc/selinux
     Loaded policy name:             targeted
     Current mode:                   enforcing
     Mode from config file:          enforcing
     Policy MLS status:              enabled
     Policy deny_unknown status:     allowed
     Memory protection checking:     actual (secure)
     Max kernel policy version:      35
     
* SELinux Errors (without results: "selinuxenabled && journalctl --no-hostname --since yesterday |grep avc: | grep -Eo comm="[^ ]+" | sort |uniq -c |sort -rn"):
     N/A
 
* Memory usage (free -hm):
                    total        used        free      shared  buff/cache   available
     Mem:            30Gi       4.0Gi        22Gi        76Mi       5.2Gi        26Gi
     Swap:           15Gi          0B        15Gi
     
* ZRAM usage (zramctl --output-all):
     NAME       DISKSIZE DATA COMPR ALGORITHM STREAMS ZERO-PAGES TOTAL MEM-LIMIT MEM-USED MIGRATED COMP-RATIO MOUNTPOINT
     /dev/zram0    15.3G   4K   64B zstd                       0   20K        0B      20K       0B     0.2000 [SWAP]
     
* Load average (uptime):
      18:27:39 up 12 min,  2 users,  load average: 0.13, 0.17, 0.09
     
* Pressure Stall Information (grep -R . /proc/pressure/):
     /proc/pressure/io:some avg10=0.07 avg60=0.52 avg300=0.24 total=2696513
     /proc/pressure/io:full avg10=0.07 avg60=0.52 avg300=0.24 total=2618003
     /proc/pressure/cpu:some avg10=0.00 avg60=0.00 avg300=0.00 total=1166013
     /proc/pressure/cpu:full avg10=0.00 avg60=0.00 avg300=0.00 total=0
     /proc/pressure/irq:full avg10=0.00 avg60=0.00 avg300=0.00 total=782343
     /proc/pressure/memory:some avg10=0.00 avg60=0.00 avg300=0.00 total=1097
     /proc/pressure/memory:full avg10=0.00 avg60=0.00 avg300=0.00 total=1091
     
* Top 5 CPU hogs (ps axuScnh | awk '$2!=6240' | sort -rnk3 | head -5):
         1000    6238 23.8  0.0 232028  3828 pts/1    S+   18:27   0:00 device-info
         1000    6242  9.5  0.0 258864 23368 pts/1    S+   18:27   0:00 fpaste
         1000    2127  8.4  0.0  24784 16004 ?        Ss   18:15   1:00 systemd
            0    6269  5.5  0.0 643148 29540 ?        Ssl  18:27   0:00 rpm-ostree
            0     866  3.6  0.0  42584 17636 ?        Ss   18:15   0:26 systemd-udevd
     
* Top 5 Memory hogs (ps axuScnh | sort -rnk4 | head -5):
         1000    2683  0.6  1.6 6789504 515148 ?      Ssl  18:15   0:04 plasmashell
         1000    5371  3.4  0.9 7614604 288412 ?      SLsl 18:23   0:09 bazaar
         1000    2373  2.1  0.7 2224488 237404 ?      Sl   18:15   0:15 kwin_wayland
         1000    2495  0.0  0.5 2174360 178828 ?      Sl   18:15   0:00 maliit-keyboard
         1000    3055  0.0  0.4 1358324 141436 ?      Ssl  18:15   0:00 xwaylandvideobr
     
* block devices (lsblk -o NAME,FSTYPE,SIZE,FSUSE%,MOUNTPOINT,UUID,MIN-IO,SCHED,DISC-GRAN,MODEL):
     NAME        FSTYPE   SIZE FSUSE% MOUNTPOINT UUID                                 MIN-IO SCHED DISC-GRAN MODEL
     zram0       swap    15.3G        [SWAP]     f7ceb212-6aae-4d7f-b96b-4ff5eb3857c4   4096              4K
     nvme0n1            953.9G                                                           512 kyber      512B SLEG-860-1TBI-S58
     ├─nvme0n1p1 vfat     260M    29% /boot/efi  E64A-4585                               512 kyber      512B
     ├─nvme0n1p2           16M                                                           512 kyber      512B
     ├─nvme0n1p3 ext4       1G    53% /boot      c395bbee-04a7-42fe-8a67-afbeab9ef796    512 kyber      512B
     ├─nvme0n1p4 ntfs     650M                   A87A0A377A0A02B4                        512 kyber      512B
     ├─nvme0n1p5 ntfs      24G                   54E27498E2747FD2                        512 kyber      512B
     └─nvme0n1p6 btrfs    928G    13% /var/home  23c09f1d-5446-49d1-a5cf-a50a020c9e64    512 kyber      512B
     
* PCI devices (lspci -nn):
     00:00.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Root Complex [1022:14d8]
     00:00.2 IOMMU [0806]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge IOMMU [1022:14d9]
     00:01.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Dummy Host Bridge [1022:14da]
     00:01.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge GPP Bridge [1022:14db]
     00:01.2 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge GPP Bridge [1022:14db]
     00:02.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Dummy Host Bridge [1022:14da]
     00:02.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge GPP Bridge [1022:14db]
     00:03.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Dummy Host Bridge [1022:14da]
     00:04.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Dummy Host Bridge [1022:14da]
     00:08.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Dummy Host Bridge [1022:14da]
     00:08.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Internal GPP Bridge to Bus [C:A] [1022:14dd]
     00:08.3 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Internal GPP Bridge to Bus [C:A] [1022:14dd]
     00:14.0 SMBus [0c05]: Advanced Micro Devices, Inc. [AMD] FCH SMBus Controller [1022:790b] (rev 71)
     00:14.3 ISA bridge [0601]: Advanced Micro Devices, Inc. [AMD] FCH LPC Bridge [1022:790e] (rev 51)
     00:18.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 0 [1022:14e0]
     00:18.1 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 1 [1022:14e1]
     00:18.2 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 2 [1022:14e2]
     00:18.3 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 3 [1022:14e3]
     00:18.4 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 4 [1022:14e4]
     00:18.5 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 5 [1022:14e5]
     00:18.6 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 6 [1022:14e6]
     00:18.7 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 7 [1022:14e7]
     01:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Upstream Port of PCI Express Switch [1002:1478] (rev 24)
     02:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Downstream Port of PCI Express Switch [1002:1479] (rev 24)
     03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 [Radeon RX 9070/9070 XT/9070 GRE] [1002:7550] (rev c0)
     03:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 HDMI/DP Audio Controller [1002:ab40]
     04:00.0 Non-Volatile memory controller [0108]: ADATA Technology Co., Ltd. LEGEND 860 NVMe SSD (DRAM-less) [1cc1:648a] (rev 03)
     05:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Upstream Port [1022:43f4] (rev 01)
     06:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
     06:08.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
     06:0a.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
     06:0b.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
     06:0c.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
     06:0d.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
     09:00.0 Ethernet controller [0200]: Realtek Semiconductor Co., Ltd. RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller [10ec:8168] (rev 15)
     0a:00.0 Network controller [0280]: Realtek Semiconductor Co., Ltd. RTL8851BE PCIe 802.11ax Wireless Network Controller [10ec:b851]
     0b:00.0 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset USB 3.2 Controller [1022:43f7] (rev 01)
     0c:00.0 SATA controller [0106]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset SATA Controller [1022:43f6] (rev 01)
     0d:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Granite Ridge [Radeon Graphics] [1002:13c0] (rev cb)
     0d:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Radeon High Definition Audio Controller [1002:1640]
     0d:00.2 Encryption controller [1080]: Advanced Micro Devices, Inc. [AMD] Family 19h PSP/CCP [1022:1649]
     0d:00.3 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge USB 3.1 xHCI [1022:15b6]
     0d:00.4 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge USB 3.1 xHCI [1022:15b7]
     0d:00.6 Audio device [0403]: Advanced Micro Devices, Inc. [AMD] Ryzen HD Audio Controller [1022:15e3]
     0e:00.0 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge USB 2.0 xHCI [1022:15b8]
     
* USB devices (lsusb):
     Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
     Bus 001 Device 002: ID 0b05:19af ASUSTek Computer, Inc. AURA LED Controller
     Bus 001 Device 003: ID 05e3:0608 Genesys Logic, Inc. Hub
     Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
     Bus 003 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
     Bus 003 Device 002: ID 0489:e112 Foxconn / Hon Hai Bluetooth Radio
     Bus 004 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
     Bus 005 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
     Bus 005 Device 002: ID 05e3:0610 Genesys Logic, Inc. Hub
     Bus 005 Device 003: ID 1532:005c Razer USA, Ltd DeathAdder Elite
     Bus 005 Device 004: ID 1a2c:2124 China Resource Semico Co., Ltd Keyboard
     Bus 006 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
     Bus 007 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
     Bus 008 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
     
* PCI Video Card (lspci |  grep -i -E 'vga' | cut -b1-7 | xargs -i lspci -vnnks {} | grep -v "<access denied>"):
     03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 [Radeon RX 9070/9070 XT/9070 GRE] [1002:7550] (rev c0) (prog-if 00 [VGA controller])
        Subsystem: ASUSTeK Computer Inc. Device [1043:0633]
        Flags: bus master, fast devsel, latency 0, IRQ 97, IOMMU group 14
        Memory at f800000000 (64-bit, prefetchable) [size=16G]
        Memory at fc00000000 (64-bit, prefetchable) [size=256M]
        I/O ports at f000 [size=256]
        Memory at f6c00000 (32-bit, non-prefetchable) [size=512K]
        Expansion ROM at f6c80000 [disabled] [size=128K]
        Kernel driver in use: amdgpu
        Kernel modules: amdgpu
     
     0d:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Granite Ridge [Radeon Graphics] [1002:13c0] (rev cb) (prog-if 00 [VGA controller])
        Subsystem: ASUSTeK Computer Inc. Device [1043:8877]
        Flags: bus master, fast devsel, latency 0, IRQ 59, IOMMU group 24
        Memory at fc20000000 (64-bit, prefetchable) [size=256M]
        Memory at f6200000 (64-bit, prefetchable) [size=2M]
        I/O ports at e000 [size=256]
        Memory at f6700000 (32-bit, non-prefetchable) [size=512K]
        Kernel driver in use: amdgpu
        Kernel modules: amdgpu
     
     
* GL Support (glxinfo -B | grep -E "OpenGL version|OpenGL renderer"):
     OpenGL renderer string: AMD Radeon RX 9070 XT (radeonsi, gfx1201, LLVM 21.1.8, DRM 3.64, 6.17.7-ba25.fc43.x86_64)
     OpenGL version string: 4.6 (Compatibility Profile) Mesa 25.3.3
     
* DRM Information (journalctl -k -b --no-hostname | grep -o 'kernel:.*drm.*$' | cut -d ' ' -f 2- ):
     ACPI: bus type drm_connector registered
     simple-framebuffer simple-framebuffer.0: [drm] Registered 1 planes with drm panic
     [drm] Initialized simpledrm 1.0.0 for simple-framebuffer.0 on minor 0
     simple-framebuffer simple-framebuffer.0: [drm] fb0: simpledrmdrmfb frame buffer device
     [drm] amdgpu kernel modesetting enabled.
     [drm] Detected VRAM RAM=16304M, BAR=16384M
     [drm] RAM width 256bits GDDR6
     [drm] GART: num cpu pages 131072, num gpu pages 131072
     amdgpu 0000:03:00.0: amdgpu: [drm] Loading DMUB firmware via PSP: version=0x0A000700
     amdgpu 0000:03:00.0: amdgpu: [drm] Display Core v3.2.340 initialized on DCN 4.0.1
     amdgpu 0000:03:00.0: amdgpu: [drm] DP-HDMI FRL PCON supported
     amdgpu 0000:03:00.0: amdgpu: [drm] DMUB hardware initialized: version=0x0A000700
     amdgpu 0000:03:00.0: [drm] REG_WAIT timeout 1us * 150000 tries - optc401_disable_crtc line:230
     amdgpu 0000:03:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
     amdgpu 0000:03:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
     amdgpu 0000:03:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
     amdgpu 0000:03:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
     amdgpu 0000:03:00.0: [drm] Registered 4 planes with drm panic
     [drm] Initialized amdgpu 3.64.0 for 0000:03:00.0 on minor 1
     fbcon: amdgpudrmfb (fb0) is primary device
     amdgpu 0000:03:00.0: [drm] fb0: amdgpudrmfb frame buffer device
     [drm] Detected VRAM RAM=512M, BAR=512M
     [drm] RAM width 128bits DDR5
     [drm] GART: num cpu pages 262144, num gpu pages 262144
     [drm] PCIE GART of 1024M enabled (table at 0x000000F41FC00000).
     amdgpu 0000:0d:00.0: amdgpu: [drm] Loading DMUB firmware via PSP: version=0x05002E00
     [drm] use_doorbell being set to: [false]
     amdgpu 0000:0d:00.0: amdgpu: [drm] Display Core v3.2.340 initialized on DCN 3.1.5
     amdgpu 0000:0d:00.0: amdgpu: [drm] DP-HDMI FRL PCON supported
     amdgpu 0000:0d:00.0: amdgpu: [drm] DMUB hardware initialized: version=0x05002E00
     amdgpu 0000:0d:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
     amdgpu 0000:0d:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
     amdgpu 0000:0d:00.0: [drm] Registered 4 planes with drm panic
     [drm] Initialized amdgpu 3.64.0 for 0000:0d:00.0 on minor 0
     amdgpu 0000:0d:00.0: [drm] Cannot find any crtc or sizes
     [drm] pre_validate_dsc:1628 MST_DSC dsc precompute is not needed
     amdgpu 0000:03:00.0: [drm] REG_WAIT timeout 1us * 150000 tries - optc401_disable_crtc line:230
     
* Xorg modules (grep LoadModule /var/log/Xorg.0.log ~/.local/share/xorg/Xorg.0.log | cut -d \" -f 2 | xargs):
     
     
* Xorg errors (without results: "grep '^\[.*(EE)' /var/log/Xorg.0.log ~/.local/share/xorg/Xorg.0.log | cut -d ':' -f 2- "):
     N/A
 
* PCI Audio devices (lspci |  grep -i -E 'audio' | cut -b1-7 | xargs -i lspci -vnnks {} | grep -v "<access denied>"):
     03:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 HDMI/DP Audio Controller [1002:ab40] (prog-if 00 [HDA compatible])
        Subsystem: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 HDMI/DP Audio Controller [1002:ab40]
        Flags: bus master, fast devsel, latency 0, IRQ 103, IOMMU group 15
        Memory at f6ca0000 (32-bit, non-prefetchable) [size=16K]
        Kernel driver in use: snd_hda_intel
        Kernel modules: snd_hda_intel
     
     0d:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Radeon High Definition Audio Controller [1002:1640] (prog-if 00 [HDA compatible])
        Subsystem: ASUSTeK Computer Inc. Device [1043:8877]
        Flags: bus master, fast devsel, latency 0, IRQ 102, IOMMU group 25
        Memory at f6788000 (32-bit, non-prefetchable) [size=16K]
        Kernel driver in use: snd_hda_intel
        Kernel modules: snd_hda_intel
     
     0d:00.6 Audio device [0403]: Advanced Micro Devices, Inc. [AMD] Ryzen HD Audio Controller [1022:15e3] (prog-if 00 [HDA compatible])
        DeviceName: Realtek ALC897 Audio
        Subsystem: ASUSTeK Computer Inc. Device [1043:87fb]
        Flags: bus master, fast devsel, latency 0, IRQ 104, IOMMU group 29
        Memory at f6780000 (32-bit, non-prefetchable) [size=32K]
        Kernel driver in use: snd_hda_intel
        Kernel modules: snd_hda_intel
     
     
* Audio devices (cat /proc/asound/cards):
      0 [HDMI           ]: HDA-Intel - HDA ATI HDMI
                           HDA ATI HDMI at 0xf6ca0000 irq 103
      1 [Generic        ]: HDA-Intel - HD-Audio Generic
                           HD-Audio Generic at 0xf6788000 irq 102
      2 [Generic_1      ]: HDA-Intel - HD-Audio Generic
                           HD-Audio Generic at 0xf6780000 irq 104
     
* User audio services (systemctl --user --no-pager status wireplumber pipewire* | sed "s/$(hostname)/ahost/"):
     ● wireplumber.service - Multimedia Service Session Manager
          Loaded: loaded (/usr/lib/systemd/user/wireplumber.service; enabled; preset: enabled)
         Drop-In: /usr/lib/systemd/user/service.d
                  └─10-timeout-abort.conf
          Active: active (running) since Mon 2026-02-02 18:15:46 CST; 11min ago
      Invocation: 769032085d3f4c12abef45c9626f21b9
        Main PID: 2375 (wireplumber)
           Tasks: 9 (limit: 36984)
          Memory: 7.4M (peak: 8.6M)
             CPU: 153ms
          CGroup: /user.slice/user-1000.slice/user@1000.service/session.slice/wireplumber.service
                  └─2375 /usr/bin/wireplumber
     
     Feb 02 18:15:46 ahost systemd[2127]: Started wireplumber.service - Multimedia Service Session Manager.
     Feb 02 18:15:46 ahost wireplumber[2375]: wp-event-dispatcher: wp_event_dispatcher_unregister_hook: assertion 'already_registered_dispatcher == self' failed
     Feb 02 18:15:46 ahost wireplumber[2375]: wp-event-dispatcher: wp_event_dispatcher_unregister_hook: assertion 'already_registered_dispatcher == self' failed
     Feb 02 18:15:46 ahost wireplumber[2375]: wp-event-dispatcher: wp_event_dispatcher_unregister_hook: assertion 'already_registered_dispatcher == self' failed
     Feb 02 18:15:46 ahost wireplumber[2375]: wp-event-dispatcher: wp_event_dispatcher_unregister_hook: assertion 'already_registered_dispatcher == self' failed
     Feb 02 18:15:46 ahost wireplumber[2375]: [0:00:18.772674722] [2375]  INFO Camera camera_manager.cpp:330 libcamera v0.5.2
     
     ● pipewire.socket - PipeWire Multimedia System Sockets
          Loaded: loaded (/usr/lib/systemd/user/pipewire.socket; enabled; preset: enabled)
          Active: active (running) since Mon 2026-02-02 18:15:46 CST; 11min ago
      Invocation: 33ed2580494148f684b472cd6a2224f9
        Triggers: ● pipewire.service
          Listen: /run/user/1000/pipewire-0 (Stream)
                  /run/user/1000/pipewire-0-manager (Stream)
     
     Feb 02 18:15:46 ahost systemd[2127]: Listening on pipewire.socket - PipeWire Multimedia System Sockets.
     
     ● pipewire-pulse.socket - PipeWire PulseAudio
          Loaded: loaded (/usr/lib/systemd/user/pipewire-pulse.socket; enabled; preset: enabled)
          Active: active (running) since Mon 2026-02-02 18:15:46 CST; 11min ago
      Invocation: c67caa605cf9401baefea98bb018c996
        Triggers: ● pipewire-pulse.service
          Listen: /run/user/1000/pulse/native (Stream)
     
     Feb 02 18:15:46 ahost systemd[2127]: Listening on pipewire-pulse.socket - PipeWire PulseAudio.
     
     ● pipewire.service - PipeWire Multimedia Service
          Loaded: loaded (/usr/lib/systemd/user/pipewire.service; disabled; preset: disabled)
         Drop-In: /usr/lib/systemd/user/pipewire.service.d
                  └─00-uresourced.conf
                  /usr/lib/systemd/user/service.d
                  └─10-timeout-abort.conf
          Active: active (running) since Mon 2026-02-02 18:15:46 CST; 11min ago
      Invocation: d57755b975c64e53a5384639f876580f
     TriggeredBy: ● pipewire.socket
        Main PID: 2372 (pipewire)
           Tasks: 3 (limit: 36984)
          Memory: 6.2M (peak: 8.8M)
             CPU: 621ms
          CGroup: /user.slice/user-1000.slice/user@1000.service/session.slice/pipewire.service
                  └─2372 /usr/bin/pipewire
     
     Feb 02 18:15:46 ahost systemd[2127]: Started pipewire.service - PipeWire Multimedia Service.
     
     ● pipewire-pulse.service - PipeWire PulseAudio
          Loaded: loaded (/usr/lib/systemd/user/pipewire-pulse.service; disabled; preset: disabled)
         Drop-In: /usr/lib/systemd/user/service.d
                  └─10-timeout-abort.conf
          Active: active (running) since Mon 2026-02-02 18:15:46 CST; 11min ago
      Invocation: 907a71c1767646ce935a1132e079272e
     TriggeredBy: ● pipewire-pulse.socket
        Main PID: 2376 (pipewire-pulse)
           Tasks: 3 (limit: 36984)
          Memory: 8.6M (peak: 14.5M)
             CPU: 31ms
          CGroup: /user.slice/user-1000.slice/user@1000.service/session.slice/pipewire-pulse.service
                  └─2376 /usr/bin/pipewire-pulse
     
     Feb 02 18:15:46 ahost systemd[2127]: Started pipewire-pulse.service - PipeWire PulseAudio.
     
* PCI Network devices (lspci |  grep -i -E 'net' | cut -b1-7 | xargs -i lspci -vnnks {} | grep -v "<access denied>"):
     09:00.0 Ethernet controller [0200]: Realtek Semiconductor Co., Ltd. RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller [10ec:8168] (rev 15)
        DeviceName: Realtek RTL8125BG LAN
        Subsystem: ASUSTeK Computer Inc. Onboard RTL8111H Ethernet [1043:8677]
        Flags: bus master, fast devsel, latency 0, IRQ 36, IOMMU group 20
        I/O ports at d000 [size=256]
        Memory at f6b04000 (64-bit, non-prefetchable) [size=4K]
        Memory at f6b00000 (64-bit, non-prefetchable) [size=16K]
        Kernel driver in use: r8169
        Kernel modules: r8169
     
     0a:00.0 Network controller [0280]: Realtek Semiconductor Co., Ltd. RTL8851BE PCIe 802.11ax Wireless Network Controller [10ec:b851]
        Subsystem: Foxconn International, Inc. Device [105b:e100]
        Flags: bus master, fast devsel, latency 0, IRQ 105, IOMMU group 21
        I/O ports at c000 [size=256]
        Memory at f6a00000 (64-bit, non-prefetchable) [size=1M]
        Kernel driver in use: rtw89_8851be
        Kernel modules: rtw89_8851be
     
     
* Network status (ip -br addr | awk '{print $1" " $2}' | column -t):
     lo     UNKNOWN
     eno1   UP
     wlan0  DOWN
     
* Kernel buffer tail (journalctl --no-hostname -k --lines 50):
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:    speaker_outs=0 (0x0/0x0/0x0/0x0/0x0)
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:    hp_outs=1 (0x1b/0x0/0x0/0x0/0x0)
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:    mono: mono_out=0x0
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:    dig-out=0x11/0x0
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:    inputs:
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:      Rear Mic=0x18
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:      Front Mic=0x19
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:      Line=0x1a
     Feb 02 18:15:34 kernel: MCE: In-kernel MCE decoding enabled.
     Feb 02 18:15:34 kernel: usbcore: registered new interface driver btusb
     Feb 02 18:15:34 kernel: input: HD-Audio Generic Rear Mic as /devices/pci0000:00/0000:00:08.1/0000:0d:00.6/sound/card2/input20
     Feb 02 18:15:34 kernel: input: HD-Audio Generic Front Mic as /devices/pci0000:00/0000:00:08.1/0000:0d:00.6/sound/card2/input21
     Feb 02 18:15:34 kernel: input: HD-Audio Generic Line as /devices/pci0000:00/0000:00:08.1/0000:0d:00.6/sound/card2/input22
     Feb 02 18:15:34 kernel: input: Razer Razer DeathAdder Elite as /devices/pci0000:00/0000:00:08.1/0000:0d:00.4/usb5/5-2/5-2.2/5-2.2:1.2/0003:1532:005C.0004/input/input25
     Feb 02 18:15:34 kernel: input: HD-Audio Generic Line Out as /devices/pci0000:00/0000:00:08.1/0000:0d:00.6/sound/card2/input23
     Feb 02 18:15:34 kernel: intel_rapl_common: Found RAPL domain package
     Feb 02 18:15:34 kernel: intel_rapl_common: Found RAPL domain core
     Feb 02 18:15:34 kernel: amd_atl: AMD Address Translation Library initialized
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0: loaded firmware rtw89/rtw8851b_fw.bin
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0: enabling device (0000 -> 0003)
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0: Firmware version 0.29.41.5 (4bd6ebac), cmd version 0, type 5
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0: Firmware version 0.29.41.5 (4bd6ebac), cmd version 0, type 3
     Feb 02 18:15:34 kernel: input: HD-Audio Generic Front Headphone as /devices/pci0000:00/0000:00:08.1/0000:0d:00.6/sound/card2/input24
     Feb 02 18:15:34 kernel: razermouse 0003:1532:005C.0004: input,hidraw3: USB HID v1.11 Keyboard [Razer Razer DeathAdder Elite] on usb-0000:0d:00.4-2.2/input2
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0: chip rfe_type is 2
     Feb 02 18:15:34 kernel: EXT4-fs (nvme0n1p3): mounted filesystem c395bbee-04a7-42fe-8a67-afbeab9ef796 r/w with ordered data mode. Quota mode: none.
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0: rfkill hardware state changed to enable
     Feb 02 18:15:34 systemd-journald[818]: Received client request to flush runtime journal.
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0 wlp10s0: renamed from wlan0
     Feb 02 18:15:34 systemd-journald[818]: /var/log/journal/d88144bf0df148659bbb06c1d8254452/system.journal: Realtime clock jumped backwards relative to last journal entry, rotating.
     Feb 02 18:15:34 systemd-journald[818]: Rotating system journal.
     Feb 02 18:15:35 kernel: RPC: Registered named UNIX socket transport module.
     Feb 02 18:15:35 kernel: RPC: Registered udp transport module.
     Feb 02 18:15:35 kernel: RPC: Registered tcp transport module.
     Feb 02 18:15:35 kernel: RPC: Registered tcp-with-tls transport module.
     Feb 02 18:15:35 kernel: RPC: Registered tcp NFSv4.1 backchannel transport module.
     Feb 02 18:15:36 kernel: nvme nvme0: using unchecked data buffer
     Feb 02 18:15:36 kernel: Bluetooth: BNEP (Ethernet Emulation) ver 1.3
     Feb 02 18:15:36 kernel: Bluetooth: BNEP filters: protocol multicast
     Feb 02 18:15:36 kernel: Bluetooth: BNEP socket layer initialized
     Feb 02 18:15:36 kernel: Bluetooth: MGMT ver 1.23
     Feb 02 18:15:36 kernel: block nvme0n1: No UUID available providing old NGUID
     Feb 02 18:15:36 kernel: NET: Registered PF_QIPCRTR protocol family
     Feb 02 18:15:37 kernel: Generic FE-GE Realtek PHY r8169-0-900:00: attached PHY driver (mii_bus:phy_addr=r8169-0-900:00, irq=MAC)
     Feb 02 18:15:37 kernel: r8169 0000:09:00.0 eno1: Link is Down
     Feb 02 18:15:38 kernel: Bluetooth: RFCOMM TTY layer initialized
     Feb 02 18:15:38 kernel: Bluetooth: RFCOMM socket layer initialized
     Feb 02 18:15:38 kernel: Bluetooth: RFCOMM ver 1.11
     Feb 02 18:15:40 kernel: r8169 0000:09:00.0 eno1: Link is Up - 1Gbps/Full - flow control off
     Feb 02 18:16:33 kernel: evm: overlay not supported
     
* Last few reboots (last -x -n10 reboot runlevel):
     reboot   system boot  6.17.7-ba25.fc4* Mon Feb  2 18:15   still running
     reboot   system boot  6.17.7-ba25.fc4* Mon Feb  2 18:10 - 18:15  (00:04)
     reboot   system boot  6.17.7-ba25.fc4* Sun Feb  1 14:46 - 15:06  (00:19)
     reboot   system boot  6.17.7-ba25.fc4* Sun Feb  1 14:17 - 14:40  (00:22)
     reboot   system boot  6.17.7-ba25.fc4* Sun Feb  1 14:03 - 14:04  (00:01)
     reboot   system boot  6.17.7-ba25.fc4* Sun Feb  1 12:58 - 13:40  (00:42)
     reboot   system boot  6.17.7-ba25.fc4* Sun Feb  1 09:30 - 12:52  (03:22)
     reboot   system boot  6.17.7-ba25.fc4* Sat Jan 31 19:17 - 19:48  (00:30)
     reboot   system boot  6.17.7-ba25.fc4* Sat Jan 31 17:31 - 17:34  (00:03)
     reboot   system boot  6.17.7-ba25.fc4* Sat Jan 31 17:29 - 17:30  (00:01)
     
     wtmp begins Sat Dec 20 17:07:35 2025
     
* DNF Repositories (dnf repolist):
     repo id         repo name
     fedora          Fedora 43 - x86_64
     terra-mesa      Terra 43 (Mesa)
     updates         Fedora 43 - x86_64 - Updates
     updates-archive Fedora 43 - x86_64 - Updates Archive
     
* DNF Extras (without results: "dnf -C list extras"):
     N/A
 
* Last 20 packages installed (rpm -qa --nodigest --nosignature --last | head -20):
     ublue-os-media-automount-udev-0.19-1.fc43.noarch Sun 25 Jan 2026 11:07:42 PM CST
     vte291-gtk4-0.82.3-1.fc43.x86_64              Sun 25 Jan 2026 11:07:22 PM CST
     steamdeck-kde-presets-desktop-0.0.git.6439.5cd43c63-1.fc43.noarch Sun 25 Jan 2026 11:07:22 PM CST
     rom-properties-utils-2.3-1.fc43.x86_64        Sun 25 Jan 2026 11:07:22 PM CST
     rom-properties-thumbnailer-dbus-2.3-1.fc43.x86_64 Sun 25 Jan 2026 11:07:22 PM CST
     rom-properties-kf6-2.3-1.fc43.x86_64          Sun 25 Jan 2026 11:07:22 PM CST
     rom-properties-common-2.3-1.fc43.noarch       Sun 25 Jan 2026 11:07:22 PM CST
     rom-properties-2.3-1.fc43.x86_64              Sun 25 Jan 2026 11:07:22 PM CST
     qt-common-4.8.7-81.fc43.noarch                Sun 25 Jan 2026 11:07:22 PM CST
     qt-4.8.7-81.fc43.x86_64                       Sun 25 Jan 2026 11:07:22 PM CST
     ptyxis-49.2-1.fc43.x86_64                     Sun 25 Jan 2026 11:07:22 PM CST
     libportal-gtk4-0.9.1-3.fc43.x86_64            Sun 25 Jan 2026 11:07:22 PM CST
     libportal-0.9.1-3.fc43.x86_64                 Sun 25 Jan 2026 11:07:22 PM CST
     libhandy-1.8.3-9.fc43.x86_64                  Sun 25 Jan 2026 11:07:22 PM CST
     krunner-bazaar-1.2.2-1.fc43.x86_64            Sun 25 Jan 2026 11:07:22 PM CST
     gnome-disk-utility-46.1-3.fc43.x86_64         Sun 25 Jan 2026 11:07:22 PM CST
     gpg-pubkey-7906993ae7387311296fbac43169891d3910d935-6941fda9 Sun 25 Jan 2026 11:07:20 PM CST
     steam-1.0.0.85-3.fc43.i686                    Sun 25 Jan 2026 11:06:56 PM CST
     sdl2-compat-2.32.56-2.fc43.i686               Sun 25 Jan 2026 11:06:56 PM CST
     NetworkManager-libnm-1.54.3-1000.2.fc43.bazzite.i686 Sun 25 Jan 2026 11:06:56 PM CST
     
* EFI boot manager output (efibootmgr -v):
     BootCurrent: 0002
     Timeout: 1 seconds
     BootOrder: 0002,0000,0003,0004,0005
     Boot0000* Windows Boot Manager     HD(1,GPT,460fc9f1-8fad-46d6-accd-4b0daa4c2c0f,0x800,0x82000)/\EFI\Microsoft\Boot\bootmgfw.efi57494e444f5753000100000088000000780000004200430044004f0042004a004500430054003d007b00390064006500610038003600320063002d0035006300640064002d0034006500370030002d0061006300630031002d006600330032006200330034003400640034003700390035007d00000000000100000010000000040000007fff0400
           dp: 04 01 2a 00 01 00 00 00 00 08 00 00 00 00 00 00 00 20 08 00 00 00 00 00 f1 c9 0f 46 ad 8f d6 46 ac cd 4b 0d aa 4c 2c 0f 02 02 / 04 04 46 00 5c 00 45 00 46 00 49 00 5c 00 4d 00 69 00 63 00 72 00 6f 00 73 00 6f 00 66 00 74 00 5c 00 42 00 6f 00 6f 00 74 00 5c 00 62 00 6f 00 6f 00 74 00 6d 00 67 00 66 00 77 00 2e 00 65 00 66 00 69 00 00 00 / 7f ff 04 00
         data: 57 49 4e 44 4f 57 53 00 01 00 00 00 88 00 00 00 78 00 00 00 42 00 43 00 44 00 4f 00 42 00 4a 00 45 00 43 00 54 00 3d 00 7b 00 39 00 64 00 65 00 61 00 38 00 36 00 32 00 63 00 2d 00 35 00 63 00 64 00 64 00 2d 00 34 00 65 00 37 00 30 00 2d 00 61 00 63 00 63 00 31 00 2d 00 66 00 33 00 32 00 62 00 33 00 34 00 34 00 64 00 34 00 37 00 39 00 35 00 7d 00 00 00 00 00 01 00 00 00 10 00 00 00 04 00 00 00 7f ff 04 00
     Boot0002* Fedora   HD(1,GPT,460fc9f1-8fad-46d6-accd-4b0daa4c2c0f,0x800,0x82000)/\EFI\fedora\shimx64.efi
           dp: 04 01 2a 00 01 00 00 00 00 08 00 00 00 00 00 00 00 20 08 00 00 00 00 00 f1 c9 0f 46 ad 8f d6 46 ac cd 4b 0d aa 4c 2c 0f 02 02 / 04 04 34 00 5c 00 45 00 46 00 49 00 5c 00 66 00 65 00 64 00 6f 00 72 00 61 00 5c 00 73 00 68 00 69 00 6d 00 78 00 36 00 34 00 2e 00 65 00 66 00 69 00 00 00 / 7f ff 04 00
     Boot0003* UEFI:CD/DVD Drive        BBS(129,,0x0)
           dp: 05 01 09 00 81 00 00 00 00 / 7f ff 04 00
     Boot0004* UEFI:Removable Device    BBS(130,,0x0)
           dp: 05 01 09 00 82 00 00 00 00 / 7f ff 04 00
     Boot0005* UEFI:Network Device      BBS(131,,0x0)
           dp: 05 01 09 00 83 00 00 00 00 / 7f ff 04 00
     
 
##############################################################################
### file 3 of 3: 61
##############################################################################
com.geekbench.Geekbench6        6.4.0   system,current
com.geeks3d.furmark     2.10.2.0        system,current
com.github.Matoking.protontricks        1.13.1  system,current
com.github.tchx84.Flatseal      2.4.0   system,current
com.obsproject.Studio.Plugin.GStreamerVaapi     0.4.2   system,runtime
com.obsproject.Studio.Plugin.Gstreamer  0.4.1   system,runtime
com.obsproject.Studio.Plugin.OBSVkCapture       1.5.3   system,runtime
com.ranfdev.DistroShelf 1.3.0   system,current
com.vysp3r.ProtonPlus   0.5.15  system,current
io.github.flattool.Warehouse    2.2.0   system,current
io.github.thetumultuousunicornofdarkness.cpu-x  5.4.0   system,current
org.freedesktop.Platform        freedesktop-sdk-24.08.29        system,runtime
org.freedesktop.Platform        freedesktop-sdk-25.08.7 system,runtime
org.freedesktop.Platform.Compat.i386            system,runtime
org.freedesktop.Platform.GL.default     25.3.3  system,runtime
org.freedesktop.Platform.GL.default     25.3.3  system,runtime
org.freedesktop.Platform.GL.default     25.3.3  system,runtime
org.freedesktop.Platform.GL.default     25.3.3  system,runtime
org.freedesktop.Platform.GL32.default   25.3.3  system,runtime
org.freedesktop.Platform.GL32.default   25.3.3  system,runtime
org.freedesktop.Platform.VulkanLayer.MangoHud   0.8.1   system,runtime
org.freedesktop.Platform.VulkanLayer.OBSVkCapture       1.5.1   system,runtime
org.freedesktop.Platform.VulkanLayer.vkBasalt   0.3.2.10        system,runtime
org.freedesktop.Platform.codecs-extra           system,runtime
org.freedesktop.Platform.ffmpeg-full            system,runtime
org.freedesktop.Platform.openh264       2.5.1   system,runtime
org.gnome.Platform              system,runtime
org.kde.KStyle.Adwaita          system,runtime
org.kde.Platform                system,runtime
org.kde.filelight       25.12.1 system,current
org.kde.gwenview        25.12.1 system,current
org.kde.haruna  1.7.1   system,current
org.kde.kcalc   25.12.1 system,current
org.kde.okular  25.12.1 system,current
org.mozilla.firefox     147.0.2 system,current
 
Reply to "UNTITLED"
Author
Title
Re: UNTITLED
Language

Plain Text
Your paste - Paste your paste here
##############################################################################
### file 1 of 3: 63
##############################################################################
State: idle
Deployments:
● ostree-image-signed:docker://ghcr.io/ublue-os/bazzite:stable
                   Digest: sha256:4a03ff61db88c7e4a414e3d77fb2378aaa3c9b626d36448c63ac7d1267701761
                  Version: 43.20260126 (2026-01-26T05:15:38Z)

  ostree-image-signed:docker://ghcr.io/ublue-os/bazzite:stable
                   Digest: sha256:fdc77a8b5a08b3bf89063cb02ba8b1e3cb61a09ad776fcfb3c657314e55af729
                  Version: 43.20260118 (2026-01-19T05:13:02Z)
##############################################################################
### file 2 of 3: 62
##############################################################################
=== fpaste 0.5.0.0 System Information ===
* OS Release (lsb_release -ds):
     "Bazzite"
     
* CPU Model (grep 'model name' /proc/cpuinfo | awk -F: '{print $2}' | uniq -c |
     sed -re 's/^ +//' ):
     16  AMD Ryzen 7 9800X3D 8-Core Processor
     
* 64-bit Support (grep -q ' lm ' /proc/cpuinfo && echo Yes || echo No):
     Yes
     
* Hardware Virtualization Support (grep -Eq '(vmx|svm)' /proc/cpuinfo && echo Yes || echo No):
     Yes
     
* Kernel (uname -r):
     6.17.7-ba25.fc43.x86_64
     
* Kernel cmdline (cat /proc/cmdline):
     BOOT_IMAGE=(hd0,gpt3)/ostree/default-374696162330b925549cee64679444d2440b032ade6a444374bbbc9dc43853ec/vmlinuz-6.17.7-ba25.fc43.x86_64 ostree=/ostree/boot.0/default/374696162330b925549cee64679444d2440b032ade6a444374bbbc9dc43853ec/0 rhgb quiet root=UUID=23c09f1d-5446-49d1-a5cf-a50a020c9e64 vconsole.keymap=us rootflags=subvol=root rw bluetooth.disable_ertm=1
     
* Desktop(s) Running (without results: "ps -eo comm= | grep -E '(gnome-session|startkde|startactive|xfce.?-session|fluxbox|blackbox|hackedbox|ratpoison|enlightenment|icewm-session|od-session|wmaker|wmx|openbox-lxde|openbox-gnome-session|openbox-kde-session|mwm|e16|fvwm|xmonad|sugar-session|mate-session|lxqt-session|cinnamon|lxdm-session|awesome|phosh|sway|Hyperland)' "):
     N/A

* Desktop(s) Installed (ls -m /usr/share/{xsessions,wayland-sessions}/ | sed 's/\.desktop//g' ):
     /usr/share/wayland-sessions/:
     plasma
     
     /usr/share/xsessions/:
     
* Session Type (env | grep 'XDG_SESSION_TYPE' | sed 's/.*=//' ):
     wayland
     
* SELinux Status (sestatus):
     SELinux status:                 enabled
     SELinuxfs mount:                /sys/fs/selinux
     SELinux root directory:         /etc/selinux
     Loaded policy name:             targeted
     Current mode:                   enforcing
     Mode from config file:          enforcing
     Policy MLS status:              enabled
     Policy deny_unknown status:     allowed
     Memory protection checking:     actual (secure)
     Max kernel policy version:      35
     
* SELinux Errors (without results: "selinuxenabled && journalctl --no-hostname --since yesterday |grep avc: | grep -Eo comm="[^ ]+" | sort |uniq -c |sort -rn"):
     N/A

* Memory usage (free -hm):
                    total        used        free      shared  buff/cache   available
     Mem:            30Gi       4.0Gi        22Gi        76Mi       5.2Gi        26Gi
     Swap:           15Gi          0B        15Gi
     
* ZRAM usage (zramctl --output-all):
     NAME       DISKSIZE DATA COMPR ALGORITHM STREAMS ZERO-PAGES TOTAL MEM-LIMIT MEM-USED MIGRATED COMP-RATIO MOUNTPOINT
     /dev/zram0    15.3G   4K   64B zstd                       0   20K        0B      20K       0B     0.2000 [SWAP]
     
* Load average (uptime):
      18:27:39 up 12 min,  2 users,  load average: 0.13, 0.17, 0.09
     
* Pressure Stall Information (grep -R . /proc/pressure/):
     /proc/pressure/io:some avg10=0.07 avg60=0.52 avg300=0.24 total=2696513
     /proc/pressure/io:full avg10=0.07 avg60=0.52 avg300=0.24 total=2618003
     /proc/pressure/cpu:some avg10=0.00 avg60=0.00 avg300=0.00 total=1166013
     /proc/pressure/cpu:full avg10=0.00 avg60=0.00 avg300=0.00 total=0
     /proc/pressure/irq:full avg10=0.00 avg60=0.00 avg300=0.00 total=782343
     /proc/pressure/memory:some avg10=0.00 avg60=0.00 avg300=0.00 total=1097
     /proc/pressure/memory:full avg10=0.00 avg60=0.00 avg300=0.00 total=1091
     
* Top 5 CPU hogs (ps axuScnh | awk '$2!=6240' | sort -rnk3 | head -5):
         1000    6238 23.8  0.0 232028  3828 pts/1    S+   18:27   0:00 device-info
         1000    6242  9.5  0.0 258864 23368 pts/1    S+   18:27   0:00 fpaste
         1000    2127  8.4  0.0  24784 16004 ?        Ss   18:15   1:00 systemd
            0    6269  5.5  0.0 643148 29540 ?        Ssl  18:27   0:00 rpm-ostree
            0     866  3.6  0.0  42584 17636 ?        Ss   18:15   0:26 systemd-udevd
     
* Top 5 Memory hogs (ps axuScnh | sort -rnk4 | head -5):
         1000    2683  0.6  1.6 6789504 515148 ?      Ssl  18:15   0:04 plasmashell
         1000    5371  3.4  0.9 7614604 288412 ?      SLsl 18:23   0:09 bazaar
         1000    2373  2.1  0.7 2224488 237404 ?      Sl   18:15   0:15 kwin_wayland
         1000    2495  0.0  0.5 2174360 178828 ?      Sl   18:15   0:00 maliit-keyboard
         1000    3055  0.0  0.4 1358324 141436 ?      Ssl  18:15   0:00 xwaylandvideobr
     
* block devices (lsblk -o NAME,FSTYPE,SIZE,FSUSE%,MOUNTPOINT,UUID,MIN-IO,SCHED,DISC-GRAN,MODEL):
     NAME        FSTYPE   SIZE FSUSE% MOUNTPOINT UUID                                 MIN-IO SCHED DISC-GRAN MODEL
     zram0       swap    15.3G        [SWAP]     f7ceb212-6aae-4d7f-b96b-4ff5eb3857c4   4096              4K 
     nvme0n1            953.9G                                                           512 kyber      512B SLEG-860-1TBI-S58
     ├─nvme0n1p1 vfat     260M    29% /boot/efi  E64A-4585                               512 kyber      512B 
     ├─nvme0n1p2           16M                                                           512 kyber      512B 
     ├─nvme0n1p3 ext4       1G    53% /boot      c395bbee-04a7-42fe-8a67-afbeab9ef796    512 kyber      512B 
     ├─nvme0n1p4 ntfs     650M                   A87A0A377A0A02B4                        512 kyber      512B 
     ├─nvme0n1p5 ntfs      24G                   54E27498E2747FD2                        512 kyber      512B 
     └─nvme0n1p6 btrfs    928G    13% /var/home  23c09f1d-5446-49d1-a5cf-a50a020c9e64    512 kyber      512B 
     
* PCI devices (lspci -nn):
     00:00.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Root Complex [1022:14d8]
     00:00.2 IOMMU [0806]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge IOMMU [1022:14d9]
     00:01.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Dummy Host Bridge [1022:14da]
     00:01.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge GPP Bridge [1022:14db]
     00:01.2 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge GPP Bridge [1022:14db]
     00:02.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Dummy Host Bridge [1022:14da]
     00:02.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge GPP Bridge [1022:14db]
     00:03.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Dummy Host Bridge [1022:14da]
     00:04.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Dummy Host Bridge [1022:14da]
     00:08.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Dummy Host Bridge [1022:14da]
     00:08.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Internal GPP Bridge to Bus [C:A] [1022:14dd]
     00:08.3 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Internal GPP Bridge to Bus [C:A] [1022:14dd]
     00:14.0 SMBus [0c05]: Advanced Micro Devices, Inc. [AMD] FCH SMBus Controller [1022:790b] (rev 71)
     00:14.3 ISA bridge [0601]: Advanced Micro Devices, Inc. [AMD] FCH LPC Bridge [1022:790e] (rev 51)
     00:18.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 0 [1022:14e0]
     00:18.1 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 1 [1022:14e1]
     00:18.2 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 2 [1022:14e2]
     00:18.3 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 3 [1022:14e3]
     00:18.4 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 4 [1022:14e4]
     00:18.5 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 5 [1022:14e5]
     00:18.6 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 6 [1022:14e6]
     00:18.7 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge Data Fabric; Function 7 [1022:14e7]
     01:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Upstream Port of PCI Express Switch [1002:1478] (rev 24)
     02:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Downstream Port of PCI Express Switch [1002:1479] (rev 24)
     03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 [Radeon RX 9070/9070 XT/9070 GRE] [1002:7550] (rev c0)
     03:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 HDMI/DP Audio Controller [1002:ab40]
     04:00.0 Non-Volatile memory controller [0108]: ADATA Technology Co., Ltd. LEGEND 860 NVMe SSD (DRAM-less) [1cc1:648a] (rev 03)
     05:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Upstream Port [1022:43f4] (rev 01)
     06:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
     06:08.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
     06:0a.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
     06:0b.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
     06:0c.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
     06:0d.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset PCIe Switch Downstream Port [1022:43f5] (rev 01)
     09:00.0 Ethernet controller [0200]: Realtek Semiconductor Co., Ltd. RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller [10ec:8168] (rev 15)
     0a:00.0 Network controller [0280]: Realtek Semiconductor Co., Ltd. RTL8851BE PCIe 802.11ax Wireless Network Controller [10ec:b851]
     0b:00.0 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset USB 3.2 Controller [1022:43f7] (rev 01)
     0c:00.0 SATA controller [0106]: Advanced Micro Devices, Inc. [AMD] 600 Series Chipset SATA Controller [1022:43f6] (rev 01)
     0d:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Granite Ridge [Radeon Graphics] [1002:13c0] (rev cb)
     0d:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Radeon High Definition Audio Controller [1002:1640]
     0d:00.2 Encryption controller [1080]: Advanced Micro Devices, Inc. [AMD] Family 19h PSP/CCP [1022:1649]
     0d:00.3 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge USB 3.1 xHCI [1022:15b6]
     0d:00.4 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge USB 3.1 xHCI [1022:15b7]
     0d:00.6 Audio device [0403]: Advanced Micro Devices, Inc. [AMD] Ryzen HD Audio Controller [1022:15e3]
     0e:00.0 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] Raphael/Granite Ridge USB 2.0 xHCI [1022:15b8]
     
* USB devices (lsusb):
     Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
     Bus 001 Device 002: ID 0b05:19af ASUSTek Computer, Inc. AURA LED Controller
     Bus 001 Device 003: ID 05e3:0608 Genesys Logic, Inc. Hub
     Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
     Bus 003 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
     Bus 003 Device 002: ID 0489:e112 Foxconn / Hon Hai Bluetooth Radio
     Bus 004 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
     Bus 005 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
     Bus 005 Device 002: ID 05e3:0610 Genesys Logic, Inc. Hub
     Bus 005 Device 003: ID 1532:005c Razer USA, Ltd DeathAdder Elite
     Bus 005 Device 004: ID 1a2c:2124 China Resource Semico Co., Ltd Keyboard
     Bus 006 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
     Bus 007 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
     Bus 008 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
     
* PCI Video Card (lspci |  grep -i -E 'vga' | cut -b1-7 | xargs -i lspci -vnnks {} | grep -v "<access denied>"):
     03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 [Radeon RX 9070/9070 XT/9070 GRE] [1002:7550] (rev c0) (prog-if 00 [VGA controller])
     	Subsystem: ASUSTeK Computer Inc. Device [1043:0633]
     	Flags: bus master, fast devsel, latency 0, IRQ 97, IOMMU group 14
     	Memory at f800000000 (64-bit, prefetchable) [size=16G]
     	Memory at fc00000000 (64-bit, prefetchable) [size=256M]
     	I/O ports at f000 [size=256]
     	Memory at f6c00000 (32-bit, non-prefetchable) [size=512K]
     	Expansion ROM at f6c80000 [disabled] [size=128K]
     	Kernel driver in use: amdgpu
     	Kernel modules: amdgpu
     
     0d:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Granite Ridge [Radeon Graphics] [1002:13c0] (rev cb) (prog-if 00 [VGA controller])
     	Subsystem: ASUSTeK Computer Inc. Device [1043:8877]
     	Flags: bus master, fast devsel, latency 0, IRQ 59, IOMMU group 24
     	Memory at fc20000000 (64-bit, prefetchable) [size=256M]
     	Memory at f6200000 (64-bit, prefetchable) [size=2M]
     	I/O ports at e000 [size=256]
     	Memory at f6700000 (32-bit, non-prefetchable) [size=512K]
     	Kernel driver in use: amdgpu
     	Kernel modules: amdgpu
     
     
* GL Support (glxinfo -B | grep -E "OpenGL version|OpenGL renderer"):
     OpenGL renderer string: AMD Radeon RX 9070 XT (radeonsi, gfx1201, LLVM 21.1.8, DRM 3.64, 6.17.7-ba25.fc43.x86_64)
     OpenGL version string: 4.6 (Compatibility Profile) Mesa 25.3.3
     
* DRM Information (journalctl -k -b --no-hostname | grep -o 'kernel:.*drm.*$' | cut -d ' ' -f 2- ):
     ACPI: bus type drm_connector registered
     simple-framebuffer simple-framebuffer.0: [drm] Registered 1 planes with drm panic
     [drm] Initialized simpledrm 1.0.0 for simple-framebuffer.0 on minor 0
     simple-framebuffer simple-framebuffer.0: [drm] fb0: simpledrmdrmfb frame buffer device
     [drm] amdgpu kernel modesetting enabled.
     [drm] Detected VRAM RAM=16304M, BAR=16384M
     [drm] RAM width 256bits GDDR6
     [drm] GART: num cpu pages 131072, num gpu pages 131072
     amdgpu 0000:03:00.0: amdgpu: [drm] Loading DMUB firmware via PSP: version=0x0A000700
     amdgpu 0000:03:00.0: amdgpu: [drm] Display Core v3.2.340 initialized on DCN 4.0.1
     amdgpu 0000:03:00.0: amdgpu: [drm] DP-HDMI FRL PCON supported
     amdgpu 0000:03:00.0: amdgpu: [drm] DMUB hardware initialized: version=0x0A000700
     amdgpu 0000:03:00.0: [drm] REG_WAIT timeout 1us * 150000 tries - optc401_disable_crtc line:230
     amdgpu 0000:03:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
     amdgpu 0000:03:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
     amdgpu 0000:03:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
     amdgpu 0000:03:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
     amdgpu 0000:03:00.0: [drm] Registered 4 planes with drm panic
     [drm] Initialized amdgpu 3.64.0 for 0000:03:00.0 on minor 1
     fbcon: amdgpudrmfb (fb0) is primary device
     amdgpu 0000:03:00.0: [drm] fb0: amdgpudrmfb frame buffer device
     [drm] Detected VRAM RAM=512M, BAR=512M
     [drm] RAM width 128bits DDR5
     [drm] GART: num cpu pages 262144, num gpu pages 262144
     [drm] PCIE GART of 1024M enabled (table at 0x000000F41FC00000).
     amdgpu 0000:0d:00.0: amdgpu: [drm] Loading DMUB firmware via PSP: version=0x05002E00
     [drm] use_doorbell being set to: [false]
     amdgpu 0000:0d:00.0: amdgpu: [drm] Display Core v3.2.340 initialized on DCN 3.1.5
     amdgpu 0000:0d:00.0: amdgpu: [drm] DP-HDMI FRL PCON supported
     amdgpu 0000:0d:00.0: amdgpu: [drm] DMUB hardware initialized: version=0x05002E00
     amdgpu 0000:0d:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
     amdgpu 0000:0d:00.0: amdgpu: [drm] PSR support 0, DC PSR ver -1, sink PSR ver 0 DPCD caps 0x0 su_y_granularity 0
     amdgpu 0000:0d:00.0: [drm] Registered 4 planes with drm panic
     [drm] Initialized amdgpu 3.64.0 for 0000:0d:00.0 on minor 0
     amdgpu 0000:0d:00.0: [drm] Cannot find any crtc or sizes
     [drm] pre_validate_dsc:1628 MST_DSC dsc precompute is not needed
     amdgpu 0000:03:00.0: [drm] REG_WAIT timeout 1us * 150000 tries - optc401_disable_crtc line:230
     
* Xorg modules (grep LoadModule /var/log/Xorg.0.log ~/.local/share/xorg/Xorg.0.log | cut -d \" -f 2 | xargs):
     
     
* Xorg errors (without results: "grep '^\[.*(EE)' /var/log/Xorg.0.log ~/.local/share/xorg/Xorg.0.log | cut -d ':' -f 2- "):
     N/A

* PCI Audio devices (lspci |  grep -i -E 'audio' | cut -b1-7 | xargs -i lspci -vnnks {} | grep -v "<access denied>"):
     03:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 HDMI/DP Audio Controller [1002:ab40] (prog-if 00 [HDA compatible])
     	Subsystem: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 HDMI/DP Audio Controller [1002:ab40]
     	Flags: bus master, fast devsel, latency 0, IRQ 103, IOMMU group 15
     	Memory at f6ca0000 (32-bit, non-prefetchable) [size=16K]
     	Kernel driver in use: snd_hda_intel
     	Kernel modules: snd_hda_intel
     
     0d:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Radeon High Definition Audio Controller [1002:1640] (prog-if 00 [HDA compatible])
     	Subsystem: ASUSTeK Computer Inc. Device [1043:8877]
     	Flags: bus master, fast devsel, latency 0, IRQ 102, IOMMU group 25
     	Memory at f6788000 (32-bit, non-prefetchable) [size=16K]
     	Kernel driver in use: snd_hda_intel
     	Kernel modules: snd_hda_intel
     
     0d:00.6 Audio device [0403]: Advanced Micro Devices, Inc. [AMD] Ryzen HD Audio Controller [1022:15e3] (prog-if 00 [HDA compatible])
     	DeviceName: Realtek ALC897 Audio
     	Subsystem: ASUSTeK Computer Inc. Device [1043:87fb]
     	Flags: bus master, fast devsel, latency 0, IRQ 104, IOMMU group 29
     	Memory at f6780000 (32-bit, non-prefetchable) [size=32K]
     	Kernel driver in use: snd_hda_intel
     	Kernel modules: snd_hda_intel
     
     
* Audio devices (cat /proc/asound/cards):
      0 [HDMI           ]: HDA-Intel - HDA ATI HDMI
                           HDA ATI HDMI at 0xf6ca0000 irq 103
      1 [Generic        ]: HDA-Intel - HD-Audio Generic
                           HD-Audio Generic at 0xf6788000 irq 102
      2 [Generic_1      ]: HDA-Intel - HD-Audio Generic
                           HD-Audio Generic at 0xf6780000 irq 104
     
* User audio services (systemctl --user --no-pager status wireplumber pipewire* | sed "s/$(hostname)/ahost/"):
     ● wireplumber.service - Multimedia Service Session Manager
          Loaded: loaded (/usr/lib/systemd/user/wireplumber.service; enabled; preset: enabled)
         Drop-In: /usr/lib/systemd/user/service.d
                  └─10-timeout-abort.conf
          Active: active (running) since Mon 2026-02-02 18:15:46 CST; 11min ago
      Invocation: 769032085d3f4c12abef45c9626f21b9
        Main PID: 2375 (wireplumber)
           Tasks: 9 (limit: 36984)
          Memory: 7.4M (peak: 8.6M)
             CPU: 153ms
          CGroup: /user.slice/user-1000.slice/user@1000.service/session.slice/wireplumber.service
                  └─2375 /usr/bin/wireplumber
     
     Feb 02 18:15:46 ahost systemd[2127]: Started wireplumber.service - Multimedia Service Session Manager.
     Feb 02 18:15:46 ahost wireplumber[2375]: wp-event-dispatcher: wp_event_dispatcher_unregister_hook: assertion 'already_registered_dispatcher == self' failed
     Feb 02 18:15:46 ahost wireplumber[2375]: wp-event-dispatcher: wp_event_dispatcher_unregister_hook: assertion 'already_registered_dispatcher == self' failed
     Feb 02 18:15:46 ahost wireplumber[2375]: wp-event-dispatcher: wp_event_dispatcher_unregister_hook: assertion 'already_registered_dispatcher == self' failed
     Feb 02 18:15:46 ahost wireplumber[2375]: wp-event-dispatcher: wp_event_dispatcher_unregister_hook: assertion 'already_registered_dispatcher == self' failed
     Feb 02 18:15:46 ahost wireplumber[2375]: [0:00:18.772674722] [2375]  INFO Camera camera_manager.cpp:330 libcamera v0.5.2
     
     ● pipewire.socket - PipeWire Multimedia System Sockets
          Loaded: loaded (/usr/lib/systemd/user/pipewire.socket; enabled; preset: enabled)
          Active: active (running) since Mon 2026-02-02 18:15:46 CST; 11min ago
      Invocation: 33ed2580494148f684b472cd6a2224f9
        Triggers: ● pipewire.service
          Listen: /run/user/1000/pipewire-0 (Stream)
                  /run/user/1000/pipewire-0-manager (Stream)
     
     Feb 02 18:15:46 ahost systemd[2127]: Listening on pipewire.socket - PipeWire Multimedia System Sockets.
     
     ● pipewire-pulse.socket - PipeWire PulseAudio
          Loaded: loaded (/usr/lib/systemd/user/pipewire-pulse.socket; enabled; preset: enabled)
          Active: active (running) since Mon 2026-02-02 18:15:46 CST; 11min ago
      Invocation: c67caa605cf9401baefea98bb018c996
        Triggers: ● pipewire-pulse.service
          Listen: /run/user/1000/pulse/native (Stream)
     
     Feb 02 18:15:46 ahost systemd[2127]: Listening on pipewire-pulse.socket - PipeWire PulseAudio.
     
     ● pipewire.service - PipeWire Multimedia Service
          Loaded: loaded (/usr/lib/systemd/user/pipewire.service; disabled; preset: disabled)
         Drop-In: /usr/lib/systemd/user/pipewire.service.d
                  └─00-uresourced.conf
                  /usr/lib/systemd/user/service.d
                  └─10-timeout-abort.conf
          Active: active (running) since Mon 2026-02-02 18:15:46 CST; 11min ago
      Invocation: d57755b975c64e53a5384639f876580f
     TriggeredBy: ● pipewire.socket
        Main PID: 2372 (pipewire)
           Tasks: 3 (limit: 36984)
          Memory: 6.2M (peak: 8.8M)
             CPU: 621ms
          CGroup: /user.slice/user-1000.slice/user@1000.service/session.slice/pipewire.service
                  └─2372 /usr/bin/pipewire
     
     Feb 02 18:15:46 ahost systemd[2127]: Started pipewire.service - PipeWire Multimedia Service.
     
     ● pipewire-pulse.service - PipeWire PulseAudio
          Loaded: loaded (/usr/lib/systemd/user/pipewire-pulse.service; disabled; preset: disabled)
         Drop-In: /usr/lib/systemd/user/service.d
                  └─10-timeout-abort.conf
          Active: active (running) since Mon 2026-02-02 18:15:46 CST; 11min ago
      Invocation: 907a71c1767646ce935a1132e079272e
     TriggeredBy: ● pipewire-pulse.socket
        Main PID: 2376 (pipewire-pulse)
           Tasks: 3 (limit: 36984)
          Memory: 8.6M (peak: 14.5M)
             CPU: 31ms
          CGroup: /user.slice/user-1000.slice/user@1000.service/session.slice/pipewire-pulse.service
                  └─2376 /usr/bin/pipewire-pulse
     
     Feb 02 18:15:46 ahost systemd[2127]: Started pipewire-pulse.service - PipeWire PulseAudio.
     
* PCI Network devices (lspci |  grep -i -E 'net' | cut -b1-7 | xargs -i lspci -vnnks {} | grep -v "<access denied>"):
     09:00.0 Ethernet controller [0200]: Realtek Semiconductor Co., Ltd. RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller [10ec:8168] (rev 15)
     	DeviceName: Realtek RTL8125BG LAN
     	Subsystem: ASUSTeK Computer Inc. Onboard RTL8111H Ethernet [1043:8677]
     	Flags: bus master, fast devsel, latency 0, IRQ 36, IOMMU group 20
     	I/O ports at d000 [size=256]
     	Memory at f6b04000 (64-bit, non-prefetchable) [size=4K]
     	Memory at f6b00000 (64-bit, non-prefetchable) [size=16K]
     	Kernel driver in use: r8169
     	Kernel modules: r8169
     
     0a:00.0 Network controller [0280]: Realtek Semiconductor Co., Ltd. RTL8851BE PCIe 802.11ax Wireless Network Controller [10ec:b851]
     	Subsystem: Foxconn International, Inc. Device [105b:e100]
     	Flags: bus master, fast devsel, latency 0, IRQ 105, IOMMU group 21
     	I/O ports at c000 [size=256]
     	Memory at f6a00000 (64-bit, non-prefetchable) [size=1M]
     	Kernel driver in use: rtw89_8851be
     	Kernel modules: rtw89_8851be
     
     
* Network status (ip -br addr | awk '{print $1" " $2}' | column -t):
     lo     UNKNOWN
     eno1   UP
     wlan0  DOWN
     
* Kernel buffer tail (journalctl --no-hostname -k --lines 50):
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:    speaker_outs=0 (0x0/0x0/0x0/0x0/0x0)
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:    hp_outs=1 (0x1b/0x0/0x0/0x0/0x0)
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:    mono: mono_out=0x0
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:    dig-out=0x11/0x0
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:    inputs:
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:      Rear Mic=0x18
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:      Front Mic=0x19
     Feb 02 18:15:34 kernel: snd_hda_codec_alc662 hdaudioC2D0:      Line=0x1a
     Feb 02 18:15:34 kernel: MCE: In-kernel MCE decoding enabled.
     Feb 02 18:15:34 kernel: usbcore: registered new interface driver btusb
     Feb 02 18:15:34 kernel: input: HD-Audio Generic Rear Mic as /devices/pci0000:00/0000:00:08.1/0000:0d:00.6/sound/card2/input20
     Feb 02 18:15:34 kernel: input: HD-Audio Generic Front Mic as /devices/pci0000:00/0000:00:08.1/0000:0d:00.6/sound/card2/input21
     Feb 02 18:15:34 kernel: input: HD-Audio Generic Line as /devices/pci0000:00/0000:00:08.1/0000:0d:00.6/sound/card2/input22
     Feb 02 18:15:34 kernel: input: Razer Razer DeathAdder Elite as /devices/pci0000:00/0000:00:08.1/0000:0d:00.4/usb5/5-2/5-2.2/5-2.2:1.2/0003:1532:005C.0004/input/input25
     Feb 02 18:15:34 kernel: input: HD-Audio Generic Line Out as /devices/pci0000:00/0000:00:08.1/0000:0d:00.6/sound/card2/input23
     Feb 02 18:15:34 kernel: intel_rapl_common: Found RAPL domain package
     Feb 02 18:15:34 kernel: intel_rapl_common: Found RAPL domain core
     Feb 02 18:15:34 kernel: amd_atl: AMD Address Translation Library initialized
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0: loaded firmware rtw89/rtw8851b_fw.bin
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0: enabling device (0000 -> 0003)
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0: Firmware version 0.29.41.5 (4bd6ebac), cmd version 0, type 5
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0: Firmware version 0.29.41.5 (4bd6ebac), cmd version 0, type 3
     Feb 02 18:15:34 kernel: input: HD-Audio Generic Front Headphone as /devices/pci0000:00/0000:00:08.1/0000:0d:00.6/sound/card2/input24
     Feb 02 18:15:34 kernel: razermouse 0003:1532:005C.0004: input,hidraw3: USB HID v1.11 Keyboard [Razer Razer DeathAdder Elite] on usb-0000:0d:00.4-2.2/input2
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0: chip rfe_type is 2
     Feb 02 18:15:34 kernel: EXT4-fs (nvme0n1p3): mounted filesystem c395bbee-04a7-42fe-8a67-afbeab9ef796 r/w with ordered data mode. Quota mode: none.
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0: rfkill hardware state changed to enable
     Feb 02 18:15:34 systemd-journald[818]: Received client request to flush runtime journal.
     Feb 02 18:15:34 kernel: rtw89_8851be 0000:0a:00.0 wlp10s0: renamed from wlan0
     Feb 02 18:15:34 systemd-journald[818]: /var/log/journal/d88144bf0df148659bbb06c1d8254452/system.journal: Realtime clock jumped backwards relative to last journal entry, rotating.
     Feb 02 18:15:34 systemd-journald[818]: Rotating system journal.
     Feb 02 18:15:35 kernel: RPC: Registered named UNIX socket transport module.
     Feb 02 18:15:35 kernel: RPC: Registered udp transport module.
     Feb 02 18:15:35 kernel: RPC: Registered tcp transport module.
     Feb 02 18:15:35 kernel: RPC: Registered tcp-with-tls transport module.
     Feb 02 18:15:35 kernel: RPC: Registered tcp NFSv4.1 backchannel transport module.
     Feb 02 18:15:36 kernel: nvme nvme0: using unchecked data buffer
     Feb 02 18:15:36 kernel: Bluetooth: BNEP (Ethernet Emulation) ver 1.3
     Feb 02 18:15:36 kernel: Bluetooth: BNEP filters: protocol multicast
     Feb 02 18:15:36 kernel: Bluetooth: BNEP socket layer initialized
     Feb 02 18:15:36 kernel: Bluetooth: MGMT ver 1.23
     Feb 02 18:15:36 kernel: block nvme0n1: No UUID available providing old NGUID
     Feb 02 18:15:36 kernel: NET: Registered PF_QIPCRTR protocol family
     Feb 02 18:15:37 kernel: Generic FE-GE Realtek PHY r8169-0-900:00: attached PHY driver (mii_bus:phy_addr=r8169-0-900:00, irq=MAC)
     Feb 02 18:15:37 kernel: r8169 0000:09:00.0 eno1: Link is Down
     Feb 02 18:15:38 kernel: Bluetooth: RFCOMM TTY layer initialized
     Feb 02 18:15:38 kernel: Bluetooth: RFCOMM socket layer initialized
     Feb 02 18:15:38 kernel: Bluetooth: RFCOMM ver 1.11
     Feb 02 18:15:40 kernel: r8169 0000:09:00.0 eno1: Link is Up - 1Gbps/Full - flow control off
     Feb 02 18:16:33 kernel: evm: overlay not supported
     
* Last few reboots (last -x -n10 reboot runlevel):
     reboot   system boot  6.17.7-ba25.fc4* Mon Feb  2 18:15   still running
     reboot   system boot  6.17.7-ba25.fc4* Mon Feb  2 18:10 - 18:15  (00:04)
     reboot   system boot  6.17.7-ba25.fc4* Sun Feb  1 14:46 - 15:06  (00:19)
     reboot   system boot  6.17.7-ba25.fc4* Sun Feb  1 14:17 - 14:40  (00:22)
     reboot   system boot  6.17.7-ba25.fc4* Sun Feb  1 14:03 - 14:04  (00:01)
     reboot   system boot  6.17.7-ba25.fc4* Sun Feb  1 12:58 - 13:40  (00:42)
     reboot   system boot  6.17.7-ba25.fc4* Sun Feb  1 09:30 - 12:52  (03:22)
     reboot   system boot  6.17.7-ba25.fc4* Sat Jan 31 19:17 - 19:48  (00:30)
     reboot   system boot  6.17.7-ba25.fc4* Sat Jan 31 17:31 - 17:34  (00:03)
     reboot   system boot  6.17.7-ba25.fc4* Sat Jan 31 17:29 - 17:30  (00:01)
     
     wtmp begins Sat Dec 20 17:07:35 2025
     
* DNF Repositories (dnf repolist):
     repo id         repo name
     fedora          Fedora 43 - x86_64
     terra-mesa      Terra 43 (Mesa)
     updates         Fedora 43 - x86_64 - Updates
     updates-archive Fedora 43 - x86_64 - Updates Archive
     
* DNF Extras (without results: "dnf -C list extras"):
     N/A

* Last 20 packages installed (rpm -qa --nodigest --nosignature --last | head -20):
     ublue-os-media-automount-udev-0.19-1.fc43.noarch Sun 25 Jan 2026 11:07:42 PM CST
     vte291-gtk4-0.82.3-1.fc43.x86_64              Sun 25 Jan 2026 11:07:22 PM CST
     steamdeck-kde-presets-desktop-0.0.git.6439.5cd43c63-1.fc43.noarch Sun 25 Jan 2026 11:07:22 PM CST
     rom-properties-utils-2.3-1.fc43.x86_64        Sun 25 Jan 2026 11:07:22 PM CST
     rom-properties-thumbnailer-dbus-2.3-1.fc43.x86_64 Sun 25 Jan 2026 11:07:22 PM CST
     rom-properties-kf6-2.3-1.fc43.x86_64          Sun 25 Jan 2026 11:07:22 PM CST
     rom-properties-common-2.3-1.fc43.noarch       Sun 25 Jan 2026 11:07:22 PM CST
     rom-properties-2.3-1.fc43.x86_64              Sun 25 Jan 2026 11:07:22 PM CST
     qt-common-4.8.7-81.fc43.noarch                Sun 25 Jan 2026 11:07:22 PM CST
     qt-4.8.7-81.fc43.x86_64                       Sun 25 Jan 2026 11:07:22 PM CST
     ptyxis-49.2-1.fc43.x86_64                     Sun 25 Jan 2026 11:07:22 PM CST
     libportal-gtk4-0.9.1-3.fc43.x86_64            Sun 25 Jan 2026 11:07:22 PM CST
     libportal-0.9.1-3.fc43.x86_64                 Sun 25 Jan 2026 11:07:22 PM CST
     libhandy-1.8.3-9.fc43.x86_64                  Sun 25 Jan 2026 11:07:22 PM CST
     krunner-bazaar-1.2.2-1.fc43.x86_64            Sun 25 Jan 2026 11:07:22 PM CST
     gnome-disk-utility-46.1-3.fc43.x86_64         Sun 25 Jan 2026 11:07:22 PM CST
     gpg-pubkey-7906993ae7387311296fbac43169891d3910d935-6941fda9 Sun 25 Jan 2026 11:07:20 PM CST
     steam-1.0.0.85-3.fc43.i686                    Sun 25 Jan 2026 11:06:56 PM CST
     sdl2-compat-2.32.56-2.fc43.i686               Sun 25 Jan 2026 11:06:56 PM CST
     NetworkManager-libnm-1.54.3-1000.2.fc43.bazzite.i686 Sun 25 Jan 2026 11:06:56 PM CST
     
* EFI boot manager output (efibootmgr -v):
     BootCurrent: 0002
     Timeout: 1 seconds
     BootOrder: 0002,0000,0003,0004,0005
     Boot0000* Windows Boot Manager	HD(1,GPT,460fc9f1-8fad-46d6-accd-4b0daa4c2c0f,0x800,0x82000)/\EFI\Microsoft\Boot\bootmgfw.efi57494e444f5753000100000088000000780000004200430044004f0042004a004500430054003d007b00390064006500610038003600320063002d0035006300640064002d0034006500370030002d0061006300630031002d006600330032006200330034003400640034003700390035007d00000000000100000010000000040000007fff0400
           dp: 04 01 2a 00 01 00 00 00 00 08 00 00 00 00 00 00 00 20 08 00 00 00 00 00 f1 c9 0f 46 ad 8f d6 46 ac cd 4b 0d aa 4c 2c 0f 02 02 / 04 04 46 00 5c 00 45 00 46 00 49 00 5c 00 4d 00 69 00 63 00 72 00 6f 00 73 00 6f 00 66 00 74 00 5c 00 42 00 6f 00 6f 00 74 00 5c 00 62 00 6f 00 6f 00 74 00 6d 00 67 00 66 00 77 00 2e 00 65 00 66 00 69 00 00 00 / 7f ff 04 00
         data: 57 49 4e 44 4f 57 53 00 01 00 00 00 88 00 00 00 78 00 00 00 42 00 43 00 44 00 4f 00 42 00 4a 00 45 00 43 00 54 00 3d 00 7b 00 39 00 64 00 65 00 61 00 38 00 36 00 32 00 63 00 2d 00 35 00 63 00 64 00 64 00 2d 00 34 00 65 00 37 00 30 00 2d 00 61 00 63 00 63 00 31 00 2d 00 66 00 33 00 32 00 62 00 33 00 34 00 34 00 64 00 34 00 37 00 39 00 35 00 7d 00 00 00 00 00 01 00 00 00 10 00 00 00 04 00 00 00 7f ff 04 00
     Boot0002* Fedora	HD(1,GPT,460fc9f1-8fad-46d6-accd-4b0daa4c2c0f,0x800,0x82000)/\EFI\fedora\shimx64.efi
           dp: 04 01 2a 00 01 00 00 00 00 08 00 00 00 00 00 00 00 20 08 00 00 00 00 00 f1 c9 0f 46 ad 8f d6 46 ac cd 4b 0d aa 4c 2c 0f 02 02 / 04 04 34 00 5c 00 45 00 46 00 49 00 5c 00 66 00 65 00 64 00 6f 00 72 00 61 00 5c 00 73 00 68 00 69 00 6d 00 78 00 36 00 34 00 2e 00 65 00 66 00 69 00 00 00 / 7f ff 04 00
     Boot0003* UEFI:CD/DVD Drive	BBS(129,,0x0)
           dp: 05 01 09 00 81 00 00 00 00 / 7f ff 04 00
     Boot0004* UEFI:Removable Device	BBS(130,,0x0)
           dp: 05 01 09 00 82 00 00 00 00 / 7f ff 04 00
     Boot0005* UEFI:Network Device	BBS(131,,0x0)
           dp: 05 01 09 00 83 00 00 00 00 / 7f ff 04 00
     

##############################################################################
### file 3 of 3: 61
##############################################################################
com.geekbench.Geekbench6	6.4.0	system,current
com.geeks3d.furmark	2.10.2.0	system,current
com.github.Matoking.protontricks	1.13.1	system,current
com.github.tchx84.Flatseal	2.4.0	system,current
com.obsproject.Studio.Plugin.GStreamerVaapi	0.4.2	system,runtime
com.obsproject.Studio.Plugin.Gstreamer	0.4.1	system,runtime
com.obsproject.Studio.Plugin.OBSVkCapture	1.5.3	system,runtime
com.ranfdev.DistroShelf	1.3.0	system,current
com.vysp3r.ProtonPlus	0.5.15	system,current
io.github.flattool.Warehouse	2.2.0	system,current
io.github.thetumultuousunicornofdarkness.cpu-x	5.4.0	system,current
org.freedesktop.Platform	freedesktop-sdk-24.08.29	system,runtime
org.freedesktop.Platform	freedesktop-sdk-25.08.7	system,runtime
org.freedesktop.Platform.Compat.i386		system,runtime
org.freedesktop.Platform.GL.default	25.3.3	system,runtime
org.freedesktop.Platform.GL.default	25.3.3	system,runtime
org.freedesktop.Platform.GL.default	25.3.3	system,runtime
org.freedesktop.Platform.GL.default	25.3.3	system,runtime
org.freedesktop.Platform.GL32.default	25.3.3	system,runtime
org.freedesktop.Platform.GL32.default	25.3.3	system,runtime
org.freedesktop.Platform.VulkanLayer.MangoHud	0.8.1	system,runtime
org.freedesktop.Platform.VulkanLayer.OBSVkCapture	1.5.1	system,runtime
org.freedesktop.Platform.VulkanLayer.vkBasalt	0.3.2.10	system,runtime
org.freedesktop.Platform.codecs-extra		system,runtime
org.freedesktop.Platform.ffmpeg-full		system,runtime
org.freedesktop.Platform.openh264	2.5.1	system,runtime
org.gnome.Platform		system,runtime
org.kde.KStyle.Adwaita		system,runtime
org.kde.Platform		system,runtime
org.kde.filelight	25.12.1	system,current
org.kde.gwenview	25.12.1	system,current
org.kde.haruna	1.7.1	system,current
org.kde.kcalc	25.12.1	system,current
org.kde.okular	25.12.1	system,current
org.mozilla.firefox	147.0.2	system,current

Create Shorturl - Create a shorter url that redirects to your paste?
Private - Private paste aren't shown in recent listings.
Delete After - When should we delete your paste?

1 Day
 Create
Powered by Stikked