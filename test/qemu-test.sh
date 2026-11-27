#!/bin/sh
# Smoke-test the relocation stub in qemu-system-aarch64 -M virt, the way the
# Citaq's U-Boot hands over: blob at RAM+0x280000, x0 = DTB, MMU off.
#
# usage: qemu-test.sh <qemu-console Image> [workdir]
#   The Image must be built with a PL011 console cmdline (see docs/testing.md);
#   the board Image prints on the RK3368 UART and is silent in QEMU.
set -e
IMG=$1; W=${2:-$(mktemp -d)}; mkdir -p "$W"; D=$(cd "$(dirname "$0")" && pwd)
Q="qemu-system-aarch64 -M virt,gic-version=2 -cpu cortex-a53 -m 2048 -nographic -no-reboot -monitor none -display none"
make -s -C "$D/../stub"
python3 "$D/../stub/mkstub.py" "$D/../stub/reloc.bin" "$IMG" "$W/stubbed.img" \
    --ram-base 0x40000000 --uart 0x09000000 --uart-type 2 >/dev/null
$Q -machine dumpdtb="$W/virt.dtb" >/dev/null 2>&1
fake() {  # $1 = DTB address
    sed "s/0x48000000/$1/" "$D/fakeuboot.S" > "$W/fu.S"
    aarch64-linux-gnu-as -o "$W/fu.o" "$W/fu.S"
    aarch64-linux-gnu-objcopy -O binary "$W/fu.o" "$W/fu.bin"
}
check() {  # $1 = name, $2 = log
    if tr -d '\r' < "$2" | grep -q "Citaq H10-3: mainline"; then echo "PASS  $1"
    else echo "FAIL  $1 (log: $2)"; fi
}
boot() {  # $1 = name, $2 = DTB address, $3 = blob
    fake "$2"
    timeout 30 $Q -smp 1 -device loader,file="$W/fu.bin",addr=0x47000000 \
        -device loader,file="$W/virt.dtb",addr="$2",force-raw=on \
        -device loader,file="$3",addr=0x40280000,force-raw=on \
        -device loader,addr=0x47000000,cpu-num=0 -serial file:"$W/$1.log" >/dev/null 2>&1 || true
    check "$1" "$W/$1.log"
}
boot stub-at-0x280000        0x48000000 "$W/stubbed.img"
boot stub-dtb-under-kernel   0x40100000 "$W/stubbed.img"
timeout 30 $Q -smp 8 -kernel "$W/stubbed.img" -serial file:"$W/smp8.log" >/dev/null 2>&1 || true
check stub-8-cores "$W/smp8.log"
boot plain-image-unaligned   0x48000000 "$IMG"
grep -h "Firmware Bug" "$W/plain-image-unaligned.log" | tr -d '\r' | sed 's/^/      plain image: /' || true
grep -h "citaq-stub" "$W/stub-dtb-under-kernel.log" | tr -d '\r' | sed 's/^/      /'
