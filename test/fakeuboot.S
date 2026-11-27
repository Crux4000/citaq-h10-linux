// Mimics the Citaq's U-Boot hand-off inside qemu -M virt:
// kernel blob at RAM+0x280000, jump with x0 = DTB, x1-x3 = 0, MMU off.
	.global _start
_start:
	ldr	x0, dtb
	ldr	x4, kern
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	br	x4
	.balign 8
dtb:	.quad	0x48000000
kern:	.quad	0x40280000
