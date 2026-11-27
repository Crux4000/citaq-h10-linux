# Roadmap

Each rung is meant to be one or two sittings. Hardware facts come from the vendor 3.10
device tree, the Android 10 port, and the stock U-Boot disassembly.

| # | Rung | Status | Notes |
|---|---|---|---|
| 0 | Linux 5.4 to busybox on serial | ✅ 16 Nov 2026 | 8 cores, 2 GB, eMMC (no partitions), PSCI, round trip to Android |
| 1 | **Modern kernels on stock U-Boot** | 🟡 QEMU pass, hardware next | `stub/` + 6.18.65 LTS. See below |
| 2 | eMMC partitions, read-only | ⬜ | `blkdevparts=` built from the parameter partition (CONFIG_CMDLINE_PARTITION) |
| 3 | USB host + RTL8152 Ethernet | ⬜ | Gives a network shell, so no more serial-only work |
| 4 | Dumb screen via `simple-framebuffer` | ⬜ | U-Boot already lights the LVDS panel for the logo. Point a simple-framebuffer node at its buffer |
| 5 | Real display: VOP + LVDS | ⬜ | Mainline `rockchip_vop_reg.c` has RK3368 VOP data. `rockchip_lvds.c` only knows rk3288/px30, so RK3368 LVDS needs adding. Panel 1024×768, 65 MHz, JEIDA |
| 6 | Touch (Ilitek @ i2c2 0x41) | ⬜ | Check the mainline `ilitek_ts_i2c` driver against our `ilits.c` findings |
| 7 | Printer on UART1 (ttyS1) | ⬜ | Plain serial ESC/POS, so python-escpos works |
| 8 | RK818 PMIC | ⬜ | Mainline `rk8xx` knows the RK818. **Careful**: stock firmware shuts the board off with no backup LiPo |
| 9 | Wi-Fi/BT via brcmfmac | ⬜ | The Android port uses bcmdhd. Need the chip ID and nvram |
| 10 | Audio (rt5651) | ⬜ | |
| 11 | GPU: G6110 on drm/imagination + Mesa | ⬜ | See below |
| 12 | Real distro userspace (Debian/Alpine) + kiosk browser | ⬜ | Root on eMMC userdata or an SD card |

## Rung 1: modern kernels

The stock U-Boot (2017.02-RK3368-06) copies the kernel to `0x280000`, ignoring the Image
header. That suited old kernels, which carried TEXT_OFFSET 0x80000. Kernels from 5.8 on have
TEXT_OFFSET 0, and the boot protocol wants them on a 2 MB boundary.

QEMU tests with a fake U-Boot that copies the real hand-off showed:

- **The plain 6.18 Image does boot unaligned** (it's always RELOCATABLE on 6.x arm64), but
  logs `[Firmware Bug]: Kernel image misaligned at boot` and is outside the protocol.
- **The stubbed Image boots cleanly**: moved to `0x200000`, on 1 and 8 cores, including
  the case where U-Boot's DTB sits where the kernel needs to go.

On hardware, test the stub image first and keep the plain one as plan B.

## Rung 11: GPU notes

- Firmware `rogue_5.9.1.46_v1.fw` is published in Imagination's linux-firmware tree, and Mesa
  has G6110 device info listed as "unsupported, not under active development".
- Alex Bee (knaerzche) got the firmware loading on an RK3368: jobs complete and the SoC side
  is fine. Output was garbled until he traced it to `VK_FORMAT_B8G8R8A8_UNORM`, since
  `_SRGB` renders correctly (vkmark). That bug is still open. Thread:
  gitlab.freedesktop.org/frankbinns/linux-firmware/-/issues/1
- The 6.18 driver has no `exp_hw_support` parameter. The MT8173 (GX6250) testers used
  `powervr.exp_hw_support=1` on a newer kernel, so this rung probably wants a 7.x kernel.
  The stub works with any version.
- It also needs a GPU node in the DT (clocks, power domain, `img,img-rogue`), and Zink
  for GL.
