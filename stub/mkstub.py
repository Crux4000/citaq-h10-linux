#!/usr/bin/env python3
"""Wrap an arm64 kernel Image with the Citaq relocation stub.

usage: mkstub.py <reloc.bin> <Image> <out> [options]

  --ram-base  ADDR   start of usable RAM, 2 MB aligned   (default 0x200000)
  --uart      ADDR   debug UART base                     (default 0xff690000)
  --uart-type N      0 = silent, 1 = 8250/DW, 2 = PL011  (default 1)

The output is itself an arm64 Image (valid header, TEXT_OFFSET 0x80000), so
the stock U-Boot can load it at 0x280000 exactly as it did the 5.4 kernel.
Feed it to build_mainline.py in place of the plain Image.
"""
import argparse, struct

PAYLOAD_OFF = 0x1000
MAGIC = 0x644d5241                  # "ARM\x64"


def pad(b, n):
    return b + b'\0' * ((-len(b)) % n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('tail')
    ap.add_argument('image')
    ap.add_argument('out')
    ap.add_argument('--ram-base', type=lambda s: int(s, 0), default=0x200000)
    ap.add_argument('--uart', type=lambda s: int(s, 0), default=0xff690000)
    ap.add_argument('--uart-type', type=int, default=1)
    a = ap.parse_args()

    assert a.ram_base % 0x200000 == 0, 'ram base must be 2 MB aligned'
    tail = bytearray(open(a.tail, 'rb').read())
    img = open(a.image, 'rb').read()
    magic = struct.unpack_from('<I', img, 0x38)[0]
    assert magic == MAGIC, 'payload is not an arm64 Image'
    text_off, image_size = struct.unpack_from('<QQ', img, 8)

    payload = pad(img, 16)
    tail_off = PAYLOAD_OFF + len(payload)
    blob_len = tail_off + len(pad(bytes(tail), 16))

    # Patch the tail's parameter block (words after the first branch).
    assert struct.unpack_from('<I', tail, 0)[0] >> 26 == 0b000101, 'tail must start with b'
    struct.pack_into('<QQQQQQ', tail, 8,
                     len(payload),          # p_payload_back (tail_off - PAYLOAD_OFF)
                     len(payload),          # p_payload_len
                     a.ram_base,
                     a.uart,
                     a.uart_type,
                     blob_len - tail_off)   # p_blob_end

    # Our own arm64 Image header.
    hdr = bytearray(64)
    struct.pack_into('<I', hdr, 0, 0x14000000 | (tail_off // 4))   # b tail
    struct.pack_into('<QQQ', hdr, 8,
                     0x80000,                                   # text_offset
                     max(blob_len, PAYLOAD_OFF + max(image_size, len(img))),
                     0x2)                                       # LE, 4K pages
    struct.pack_into('<I', hdr, 0x38, MAGIC)

    blob = pad(bytes(hdr), PAYLOAD_OFF) + payload + pad(bytes(tail), 16)
    assert len(blob) == blob_len
    open(a.out, 'wb').write(blob)
    print(f'payload text_offset {text_off:#x} image_size {image_size:#x} '
          f'len {len(img):#x}')
    print(f'stub blob {len(blob)} bytes, tail at {tail_off:#x}, '
          f'ram_base {a.ram_base:#x}, kernel will run at {a.ram_base + text_off:#x}')


if __name__ == '__main__':
    main()
