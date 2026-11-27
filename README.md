# citaq-h10-linux

[![Support on Ko-fi](https://img.shields.io/badge/Ko--fi-Buy%20me%20a%20coffee-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/crux40000)

Mainline Linux on the Citaq H10-3 POS terminal (Rockchip RK3368, board CTE-RK3368-V1.0),
booting from the **stock** U-Boot with no bootloader swap.

This is the long-game sibling of
[citaq-h10-android10](https://github.com/Crux4000/citaq-h10-android10), which gives you a
working Android 10 kiosk today. This project chases mainline Linux instead: a kernel and
browser that keep getting updates after Android 10 drops off the Chrome support list.

> **Status: early bring-up.** Serial console, 8 cores, RAM and eMMC work on Linux 5.4.
> A relocation stub now lets modern kernels (6.18 LTS tested in QEMU) boot on the stock
> U-Boot. There is no display, touch, network or GPU support yet. See
> [docs/ROADMAP.md](docs/ROADMAP.md).

## What's here

| Path | What it is |
|---|---|
| `stub/` | Relocation stub. U-Boot always drops the kernel at `0x280000`, but kernels 5.8+ want a 2 MB-aligned address. The stub moves the kernel to `0x200000` (and the DTB too, if it's in the way), then jumps. |
| `tools/build_mainline.py` | Packs a kernel and DTB into a recovery-slot image the stock U-Boot accepts (Rockchip SHA-1 header recipe, RSCE second stage). |
| `kernel/citaq.config` | Minimal kernel config fragment, merged onto `allnoconfig`. |
| `dts/` | Board device tree (CPUs, memory, UART2, eMMC so far) and a build script. |
| `initramfs/` | Tiny busybox init that drops to a shell on the serial console. |
| `test/` | QEMU test harness that mimics the Citaq U-Boot hand-off. |
| `docs/` | Roadmap, boot-chain notes, hardware test procedure. |

## Quick start (build)

You need an Ubuntu/Debian box (WSL works) with `gcc-aarch64-linux-gnu`, `flex`, `bison`,
`bc`, `libssl-dev`, `device-tree-compiler`, `cpio` and `qemu-system-arm` for testing.

```sh
git clone --depth 1 --branch v6.18.65 https://github.com/gregkh/linux linux-6.18
./build.sh linux-6.18 out/          # busybox, kernel, DTB, stubbed Image
python3 tools/build_mainline.py recovery.img out/Image-stub out/rk3368-citaq-h10.dtb linux-recovery.img
```

`recovery.img` is your terminal's **stock** recovery image. It's used as a template for
the header fields and boot logos, and nothing from its kernel is kept.

Then follow [docs/hardware-test.md](docs/hardware-test.md). Everything goes into the
recovery slot, so stock Android or the Android 10 port keeps booting normally.

## Safety

- Only the **recovery** partition is written, and you back it up first.
- `reboot -f` from the Linux shell goes straight back to normal boot.
- A kernel that hangs before init needs a full power cycle, which means the backup LiPo
  as well as the 24 V supply. Keep the inline switch on the LiPo lead.

## Support

This project is free and always will be. If it saved a terminal from landfill or saved you some time, you can [buy me a coffee](https://ko-fi.com/crux40000). It goes towards test hardware and late-night debugging.

## Licence

Tools, stub and scripts: GPL-3.0-or-later. The device tree is GPL-2.0 so it can go
upstream into the kernel. Copyright Crux4000.
