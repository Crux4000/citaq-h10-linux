# Boot chain facts (stock firmware)

All from the H10-3's own firmware: serial logs, plus disassembly of
`U-Boot 2017.02-RK3368-06 (Feb 21 2019)`.

- **Boot ROM → miniloader 2.53 (DDR3 2048 MB, 32-bit) → ATF (trust) → U-Boot**, all from eMMC.
  Secure boot is off (`SecureBootEn = 0`).
- `bootcmd=bootrk`, `bootdelay=0`. `adb reboot recovery` makes it load the **recovery**
  partition instead of boot.
- **Kernel** goes to **0x280000**, whatever the header says. **Ramdisk** goes to
  **0x05bf0000**, with the second stage right after it.
- **FDT** comes from `rk-kernel.dtb` inside the image's own **RSCE second stage**. It falls
  back to the resource partition only if that fails, so a test DTB never touches Android's.
- **Header hash is enforced** with Rockchip's recipe: SHA-1 over kernel, kernel_size,
  ramdisk, ramdisk_size, second, second_size, then header bytes 0x20–0x240, stored at 0x240.
  It's computed on the HW crypto engine in 4-byte words, so every chunk is zero-padded to
  16 bytes. On mismatch the log shows `boot or recovery image sha mismatch!` → backup →
  rockusb.
- The vendor cmdline is ignored, because test kernels use CONFIG_CMDLINE_FORCE.
- RAM for Linux: `0x200000`–`0x80000000`. Below 0x200000 belongs to ATF.
- **Debug UART2** (0xff690000, 8250/DW, reg-shift 2) is on test points
  **TP17 = TX, TP18 = RX, TP19 = GND**, 3.3 V, **115200**.
- **SD card boot**: U-Boot checks SD LBA 64 for a Rockchip IDB and boots from the card if it
  finds one (flag byte selects boot vs update). Untested, but it's a possible zero-eMMC-write
  test path later.
- Mainline doesn't parse the Rockchip `parameter` partition table, so `mmcblk0` shows no
  partitions until you pass `blkdevparts=`.
