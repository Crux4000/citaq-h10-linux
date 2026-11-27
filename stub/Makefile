CROSS ?= aarch64-linux-gnu-

reloc.bin: reloc.S
	$(CROSS)as -o reloc.o reloc.S
	$(CROSS)ld -Ttext=0 -e _start -o reloc.elf reloc.o
	$(CROSS)objcopy -O binary reloc.elf reloc.bin
	@test "$$($(CROSS)readelf -r reloc.o | grep -c R_AARCH64)" = "0" || \
		echo "note: relocations resolved by ld"

clean:
	rm -f reloc.o reloc.elf reloc.bin

.PHONY: clean
