// SPDX-License-Identifier: GPL-3.0-or-later
//
// Citaq H10-3 relocation stub.
//
// The stock U-Boot 2017.02-RK3368 always copies the "kernel" part of a boot
// image to 0x280000 and jumps there with x0 = DTB. That suits kernels <= 5.7
// (TEXT_OFFSET 0x80000 from a 2 MB-aligned base). Kernels 5.8+ have
// TEXT_OFFSET 0 and must start on a 2 MB boundary, so they hang there.
//
// mkstub.py wraps a kernel Image like this:
//
//   +0x0000  64-byte arm64 Image header, code0 = branch to the tail below
//   +0x1000  the real kernel Image (payload)
//   +N       this code (the "tail"), after the payload so the copy never
//            overwrites the code that is doing the copying
//
// The tail then:
//   1. prints what it sees on the debug UART (optional)
//   2. checks the payload is an arm64 Image
//   3. picks dest = ram_base + payload text_offset (0x200000 for 5.8+)
//   4. moves the DTB out of the way if the kernel would land on top of it
//   5. copies the payload down to dest (ascending, dest < src, so it is safe)
//   6. invalidates the I-cache and jumps to dest with x0 = DTB, x1-x3 = 0
//
// Runs with the MMU off (per the arm64 boot protocol), so every access is
// Device memory: all loads/stores here are naturally aligned. Position
// independent: it only uses adr and pc-relative literals.

	.text
	.global _start
_start:
	b	entry

	.balign 8
	// Patched by mkstub.py. Offsets are relative to _start (the tail).
p_payload_back:	.quad 0			// bytes from _start back to payload
p_payload_len:	.quad 0			// payload length, multiple of 16
p_ram_base:	.quad 0x200000		// start of usable RAM (2 MB aligned)
p_uart_base:	.quad 0xff690000	// debug UART (UART2 on the H10-3)
p_uart_type:	.quad 1			// 0 = silent, 1 = 8250/DW, 2 = PL011
p_blob_end:	.quad 0			// bytes from _start to the end of the blob

entry:
	mov	x21, x0				// DTB from U-Boot
	adr	x22, _start
	ldr	x1, p_payload_back
	sub	x23, x22, x1			// x23 = payload source
	ldr	x24, p_payload_len		// x24 = payload length
	ldr	x26, p_ram_base
	ldr	x1, p_blob_end
	add	x27, x22, x1			// x27 = end of everything U-Boot loaded

	adr	x0, s_banner
	bl	puts
	adr	x0, s_dtb
	bl	puts
	mov	x0, x21
	bl	puthex
	adr	x0, s_src
	bl	puts
	mov	x0, x23
	bl	puthex
	adr	x0, s_len
	bl	puts
	mov	x0, x24
	bl	puthex
	bl	newline

	// 2. arm64 Image magic "ARM\x64" at +0x38
	ldr	w1, [x23, #0x38]
	movz	w2, #0x5241
	movk	w2, #0x644d, lsl #16
	cmp	w1, w2
	b.eq	1f
	adr	x0, s_badmagic
	b	die
1:
	// 3. dest = ram_base + text_offset, size = image_size (or file length)
	ldr	x2, [x23, #8]			// text_offset
	add	x25, x26, x2			// x25 = dest
	ldr	x28, [x23, #16]			// image_size (includes BSS)
	cbnz	x28, 2f
	mov	x28, x24
2:	cmp	x28, x24
	b.hs	3f
	mov	x28, x24
3:
	adr	x0, s_dest
	bl	puts
	mov	x0, x25
	bl	puthex
	adr	x0, s_isize
	bl	puts
	mov	x0, x28
	bl	puthex
	bl	newline

	cmp	x25, x23
	b.ls	4f
	adr	x0, s_destabove			// would need a descending copy
	b	die
4:
	// 4. does [dest, dest+image_size) overlap the DTB?
	cbz	x21, 6f				// no DTB: nothing to protect
	ldr	w1, [x21, #4]			// fdt totalsize, big-endian
	rev	w1, w1
	add	x1, x1, #7
	and	x1, x1, #~7			// round up to 8 bytes
	mov	x19, x1				// x19 = DTB size
	add	x2, x25, x28			// kernel end
	cmp	x21, x2
	b.hs	6f				// DTB starts after the kernel
	add	x3, x21, x19
	cmp	x3, x25
	b.ls	6f				// DTB ends before the kernel
	// overlap: new DTB = align_up(max(kernel end, blob end), 2 MB)
	cmp	x2, x27
	csel	x2, x2, x27, hs
	mov	x3, #0x1fffff
	add	x2, x2, x3
	and	x2, x2, #~0x1fffff
	mov	x20, x2
	adr	x0, s_dtbmove
	bl	puts
	mov	x0, x20
	bl	puthex
	bl	newline
	// copy DTB to x20, descending (x20 > x21, regions may overlap)
	mov	x3, x19
5:	sub	x3, x3, #8
	ldr	x4, [x21, x3]
	str	x4, [x20, x3]
	cbnz	x3, 5b
	mov	x21, x20
6:
	// 5. copy the payload down to dest, 16 bytes at a time, ascending
	cmp	x25, x23
	b.eq	8f				// already in place
	mov	x1, x23
	mov	x2, x25
	add	x3, x23, x24
7:	ldp	x4, x5, [x1], #16
	stp	x4, x5, [x2], #16
	cmp	x1, x3
	b.lo	7b
8:
	adr	x0, s_jump
	bl	puts
	mov	x0, x25
	bl	puthex
	bl	newline
	bl	uart_drain

	// 6. clean up and jump
	dsb	sy
	ic	iallu
	dsb	sy
	isb
	mov	x0, x21
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	br	x25

// ---- helpers --------------------------------------------------------------
// die: print the message in x0 and park the CPU
die:
	bl	puts
	bl	newline
9:	wfe
	b	9b

// putc: w0 = char. Clobbers x9-x11.
putc:
	ldr	x10, p_uart_type
	cbz	x10, 3f
	ldr	x9, p_uart_base
	cmp	x10, #2
	b.eq	2f
1:	ldr	w11, [x9, #0x14]		// 8250 LSR, regs on 4-byte stride
	tbz	w11, #5, 1b			// wait for THRE
	str	w0, [x9]
	ret
2:	ldr	w11, [x9, #0x18]		// PL011 FR
	tbnz	w11, #5, 2b			// wait while TXFF
	str	w0, [x9]
3:	ret

// uart_drain: wait until the 8250 transmitter is fully empty, so nothing is
// lost when the kernel re-initialises the port
uart_drain:
	ldr	x10, p_uart_type
	cmp	x10, #1
	b.ne	2f
	ldr	x9, p_uart_base
1:	ldr	w11, [x9, #0x14]
	tbz	w11, #6, 1b			// TEMT
2:	ret

// puts: x0 = NUL-terminated string. Clobbers x0, x9-x13, x15.
puts:
	mov	x15, x30
	mov	x12, x0
1:	ldrb	w0, [x12], #1
	cbz	w0, 2f
	bl	putc
	b	1b
2:	mov	x30, x15
	ret

newline:
	mov	x15, x30
	mov	w0, #'\r'
	bl	putc
	mov	w0, #'\n'
	bl	putc
	mov	x30, x15
	ret

// puthex: x0 = value, printed as 0x%016x. Clobbers x0, x9-x15.
puthex:
	mov	x15, x30
	mov	x13, x0
	mov	w0, #'0'
	bl	putc
	mov	w0, #'x'
	bl	putc
	mov	x14, #60
1:	lsr	x0, x13, x14
	and	x0, x0, #0xf
	cmp	x0, #10
	b.lo	2f
	add	x0, x0, #('a' - 10 - '0')
2:	add	x0, x0, #'0'
	bl	putc
	subs	x14, x14, #4
	b.pl	1b
	mov	x30, x15
	ret

s_banner:	.asciz	"\r\n[citaq-stub] relocation stub v1\r\n"
s_dtb:		.asciz	"[citaq-stub] dtb="
s_src:		.asciz	" src="
s_len:		.asciz	" len="
s_dest:		.asciz	"[citaq-stub] dest="
s_isize:	.asciz	" image_size="
s_dtbmove:	.asciz	"[citaq-stub] DTB overlaps kernel, moved to "
s_jump:		.asciz	"[citaq-stub] jumping to "
s_badmagic:	.asciz	"[citaq-stub] ERROR: payload is not an arm64 Image"
s_destabove:	.asciz	"[citaq-stub] ERROR: dest is above src, not supported"
	.balign 16
