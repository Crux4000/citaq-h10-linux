# Testing without the terminal (QEMU)

`test/qemu-test.sh` copies the Citaq U-Boot hand-off inside `qemu-system-aarch64 -M virt`:
a fake U-Boot (`test/fakeuboot.S`) jumps to the blob at RAM + 0x280000 with x0 = DTB and the
MMU off.

The board kernel prints on the RK3368 UART, so QEMU needs a variant with a PL011 console.
Build it once by copying the kernel build dir and changing only the cmdline (the rebuild
is incremental, about 40 s):

```sh
cp -a out/work/kernel out/work/kernel-qemu
sed -i 's#^CONFIG_CMDLINE=.*#CONFIG_CMDLINE="console=ttyAMA0 earlycon=pl011,0x09000000 rdinit=/init panic=-1"#' out/work/kernel-qemu/.config
make -C linux-6.18 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=$PWD/out/work/kernel-qemu Image
test/qemu-test.sh out/work/kernel-qemu/arch/arm64/boot/Image
```

Expected (27 Nov 2026, 6.18.65):

```
PASS  stub-at-0x280000
PASS  stub-dtb-under-kernel
PASS  stub-8-cores
PASS  plain-image-unaligned
      plain image: [Firmware Bug]: Kernel image misaligned at boot, please fix your bootloader!
      [citaq-stub] DTB overlaps kernel, moved to 0x0000000040a00000
```

Notes:

- With the raw `-device loader` hand-off, QEMU doesn't park secondary cores the way ATF does,
  so the fake-U-Boot runs use `-smp 1`. The 8-core run loads the stubbed image with QEMU's
  own `-kernel` instead. It still lands unaligned (RAM + 0x80000), which tests the same
  copy-down path.
- QEMU doesn't model caches or Device-memory alignment rules. The stub uses only aligned
  accesses with the MMU off, but real hardware is the final word.
