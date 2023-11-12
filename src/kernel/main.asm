org  0x7C00
bits 16

%define ENDL 0x0D, 0x0A

start:
	jmp main

	; Prints string to screen
	; [Param]   ds:si string ptr has to be null delimited
	; [Return]

puts:
	push si
	push ax

.loop:
	lodsb
	or al, al
	jz .done

	mov ah, 0x0E
	mov bh, 0x00
	int 0x10
	jmp .loop

.done:
	pop ax
	pop si
	ret

main:
	mov ax, 0
	mov ds, ax
	mov es, ax

	;   stack setup
	mov ss, ax
	mov sp, 0x7C00

	mov  si, str_hello
	call puts

	hlt

.halt:
	jmp .halt

str_hello: db "Hello using BIOS!", ENDL, 0

times 510-($-$$) db 0
dw    0AA55h
