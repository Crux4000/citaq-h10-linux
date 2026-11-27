#!/usr/bin/env python3
"""Build a Citaq H10-3 recovery-slot image that boots a mainline kernel.

usage: build_mainline.py <stock recovery.img> <Image> <board.dtb> <out.img>

- Header fields (addresses, page size 16384, tags, empty cmdline) are copied from
  the stock recovery so the vendor U-Boot 2017.02-RK3368 treats it the same way.
- kernel  = arm64 Image. U-Boot copies it to 0x280000 regardless of the header.
            Kernels <= 5.7 (TEXT_OFFSET 0x80000) can go in as-is. For 5.8+ pass
            the output of stub/mkstub.py, which relocates the kernel to the
            2 MB-aligned 0x200000 the boot protocol wants.
- ramdisk = tiny empty gzip cpio (the real initramfs is built into the kernel)
- second  = RSCE resource package: our DTB as rk-kernel.dtb + the stock logos.
            U-Boot loads the kernel FDT from here when second_size != 0.
- Every hashed chunk is zero-padded to 16 bytes (U-Boot hashes on the HW crypto
  engine in 4-byte words) and the header id is the Rockchip SHA-1 recipe
  (standard parts + header bytes 0x20..0x240).
"""
import sys, struct, hashlib, gzip


def pad16(b):
    return b + b'\0' * ((-len(b)) % 16)


def rsce_unpack(r):
    assert r[:4] == b'RSCE', 'stock recovery has no RSCE second stage'
    n = struct.unpack('<I', r[12:16])[0]
    out = []
    for i in range(n):
        e = r[512 * (1 + i):512 * (2 + i)]
        assert e[:4] == b'ENTR'
        name = e[4:260].split(b'\0')[0].decode()
        off, size = struct.unpack('<II', e[260:268])
        out.append((name, r[off * 512:off * 512 + size]))
    return out


def rsce_pack(entries):
    n = len(entries)
    hdr = bytearray(512)
    hdr[0:4] = b'RSCE'
    hdr[8:12] = bytes([1, 1, 1, 0])          # header blks, tbl offset blks, entry blks
    struct.pack_into('<I', hdr, 12, n)
    table = b''
    data = b''
    blk = 1 + n
    for name, body in entries:
        e = bytearray(512)
        e[0:4] = b'ENTR'
        nb = name.encode(); e[4:4 + len(nb)] = nb
        struct.pack_into('<II', e, 260, blk, len(body))
        table += bytes(e)
        chunk = body + b'\0' * ((-len(body)) % 512)
        data += chunk
        blk += len(chunk) // 512
    return bytes(hdr) + table + data


def empty_cpio_gz():
    f = [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 11, 0]
    h = b'070701' + b''.join(b'%08X' % x for x in f) + b'TRAILER!!!\0'
    h += b'\0' * ((-len(h)) % 4)
    return gzip.compress(h, 9, mtime=0)


def main(stock, image, dtb, out):
    r = open(stock, 'rb').read()
    assert r[:8] == b'ANDROID!', 'not an Android boot image'
    ks, ka, rs, ra, ss, sa, ta, ps = struct.unpack('<8I', r[8:40])
    pg = lambda n: (n + ps - 1) // ps * ps
    stock_second = r[ps + pg(ks) + pg(rs):ps + pg(ks) + pg(rs) + ss]
    ents = rsce_unpack(stock_second)
    new_ents = []
    for name, body in ents:
        if name == 'rk-kernel.dtb':
            body = open(dtb, 'rb').read()
        new_ents.append((name, body))
    kimg = open(image, 'rb').read()
    assert kimg[0x38:0x3c] == b'ARMd', 'kernel is not an arm64 Image'
    text_off = struct.unpack_from('<Q', kimg, 8)[0]
    if text_off != 0x80000:
        print(f'WARNING: kernel TEXT_OFFSET is {text_off:#x}; U-Boot loads it at '
              '0x280000. Wrap it with stub/mkstub.py first (kernel 5.8+).')
    K = pad16(kimg)
    R = pad16(empty_cpio_gz())
    S = pad16(rsce_pack(new_ents))
    hd = bytearray(r[:ps])
    struct.pack_into('<I', hd, 8, len(K))
    struct.pack_into('<I', hd, 16, len(R))
    struct.pack_into('<I', hd, 24, len(S))
    h = hashlib.sha1()
    for b in (K, R, S):
        h.update(b); h.update(struct.pack('<I', len(b)))
    h.update(bytes(hd[0x20:0x240]))
    hd[576:608] = h.digest() + b'\0' * 12
    img = bytes(hd)
    for b in (K, R, S):
        img += b + b'\0' * (pg(len(b)) - len(b))
    assert len(img) <= 32 * 1024 * 1024, 'too big for the 32 MB recovery partition'
    img += b'\0' * ((-len(img)) % 16384)
    open(out, 'wb').write(img)
    print(f'kernel {len(K)}  ramdisk {len(R)}  second {len(S)}  image {len(img)} bytes '
          f'({len(img)//16384} x 16384)')
    print('resource entries:', [(n, len(b)) for n, b in new_ents])
    print('md5', hashlib.md5(img).hexdigest())


if __name__ == '__main__':
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(*sys.argv[1:5])
