#!/bin/sh
# Build everything for a Citaq H10-3 mainline test.
# usage: ./build.sh <linux source tree> [out dir]
#   Needs: gcc-aarch64-linux-gnu flex bison bc libssl-dev device-tree-compiler cpio git
set -e
K=$(cd "$1" && pwd); OUT=$(mkdir -p "${2:-out}" && cd "${2:-out}" && pwd)
R=$(cd "$(dirname "$0")" && pwd); W=$OUT/work; mkdir -p "$W"
X=aarch64-linux-gnu-

# 1. static arm64 busybox
if [ ! -x "$W/busybox" ]; then
    [ -d "$W/busybox-src" ] || git clone -q --depth 1 --branch 1_36_1 https://github.com/mirror/busybox "$W/busybox-src"
    make -s -C "$W/busybox-src" defconfig >/dev/null
    sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/; s/^CONFIG_TC=y/# CONFIG_TC is not set/' "$W/busybox-src/.config"
    make -s -C "$W/busybox-src" -j"$(nproc)" CROSS_COMPILE=$X
    cp "$W/busybox-src/busybox" "$W/busybox"
fi

# 2. initramfs list with absolute paths
sed "s#@BUSYBOX@#$W/busybox#; s#@INIT@#$R/initramfs/init#" "$R/initramfs/initramfs.list.in" > "$W/initramfs.list"

# 3. kernel
sed "s#^CONFIG_INITRAMFS_SOURCE=.*#CONFIG_INITRAMFS_SOURCE=\"$W/initramfs.list\"#" "$R/kernel/citaq.config" > "$W/citaq.config"
make -s -C "$K" ARCH=arm64 CROSS_COMPILE=$X O="$W/kernel" allnoconfig
"$K/scripts/kconfig/merge_config.sh" -m -O "$W/kernel" "$W/kernel/.config" "$W/citaq.config" >/dev/null
make -s -C "$K" ARCH=arm64 CROSS_COMPILE=$X O="$W/kernel" olddefconfig
make -s -C "$K" ARCH=arm64 CROSS_COMPILE=$X O="$W/kernel" -j"$(nproc)" Image
cp "$W/kernel/arch/arm64/boot/Image" "$OUT/Image-plain"

# 4. DTB
"$R/dts/build_dtb.sh" "$K" "$OUT/rk3368-citaq-h10.dtb"

# 5. stub
make -s -C "$R/stub"
python3 "$R/stub/mkstub.py" "$R/stub/reloc.bin" "$OUT/Image-plain" "$OUT/Image-stub"

cd "$OUT" && md5sum Image-plain Image-stub rk3368-citaq-h10.dtb | tee MD5SUMS
echo "next: python3 $R/tools/build_mainline.py <stock recovery.img> $OUT/Image-stub $OUT/rk3368-citaq-h10.dtb linux-a-stub.img"
