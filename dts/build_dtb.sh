#!/bin/sh
# usage: build_dtb.sh <linux source tree> [out.dtb]
set -e
K=$1; OUT=${2:-rk3368-citaq-h10.dtb}; D=$(dirname "$0")
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
    -I "$K/include" -I "$K/arch/arm64/boot/dts/rockchip" -I "$K/scripts/dtc/include-prefixes" \
    "$D/rk3368-citaq-h10.dts" | dtc -I dts -O dtb -q -o "$OUT" -
echo "wrote $OUT ($(wc -c < "$OUT") bytes)"
