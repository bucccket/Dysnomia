ASM=nasm

SRC_DIR=src
BUILD_DIR=build

#
# Generate Floppy
#
floppy_image: $(BUILD_DIR)/main_floppy.img
$(BUILD_DIR)/main_floppy.img: bootloader kernel 
	dd bs=512 count=2880 if=/dev/zero of=$@
	mkfs.fat -F 12 -n "ERIS" $@
	dd if=$(BUILD_DIR)/bootloader.bin of=$@ conv=notrunc
	mcopy -i $@ $(BUILD_DIR)/kernel.bin "::kernel.bin"

#
# Bootloader
#
bootloader: $(BUILD_DIR)/bootloader.bin
$(BUILD_DIR)/bootloader.bin: always
	$(ASM) $(SRC_DIR)/boot/main.asm -f bin -o $@

#
# Kernel
#
kernel: $(BUILD_DIR)/kernel.bin
$(BUILD_DIR)/kernel.bin: always
	$(ASM) $(SRC_DIR)/kernel/main.asm -f bin -o $@

#
# Always
#
always:
	mkdir -p $(BUILD_DIR)

#
# Clean 
#
clean:
	rm -rf $(BUILD_DIR)/*

.PHONY: all floppy_image kernel bootloader clean always
