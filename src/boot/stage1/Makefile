BUILD_DIR?=build/
ASM?=nasm

.PHONY: all clean

all: stage1
stage1: $(BUILD_DIR)/stage1.bin

$(BUILD_DIR)/stage1.bin: 
	$(ASM) boot.asm -f bin -o $@

clean:
	rm -f $(BUILD_DIR)/stage1.bin
