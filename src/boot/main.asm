org  0x7C00
bits 16

%define ENDL 0x0D, 0x0A

	;FAT 12 MBR disk header - EBxx90

	jmp short start; 0xEB <main>
nop ; 0x90

bdb_oem:                    db 'MSWIN4.1'           ; 8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880                 ; 2880 * 512 = 1.44MB
bdb_media_descriptor_type:  db 0F0h                 ; F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9                    ; 9 sectors/fat
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

ebr_drive_number:           db 0                    ; 0x00 floppy, 0x80 hdd, useless
db 0; reserved
ebr_signature:              db 29h
ebr_volume_id:              db 055h, 0B0h, 0EFh, 0BEh   ; serial number, value doesn't matter
ebr_volume_label:           db 'DYSNOMIA   '        ; 11 bytes, padded with spaces
ebr_system_id:              db 'FAT12   '           ; 8 bytes

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

	;read data from floppy
	;By   default the BIOS sets DL to the drive number
	mov   [ebr_drive_number], dl
	mov   ax, 1
	mov   cl, 1
	mov   bx, 0x7E00; data should be after the bootloader
	call  disk_read

	;print message
	mov    si, str_hello
	call   puts

	cli
	hlt

	; Error Handlers

floppy_error:
	mov  si, str_read_fail
	call puts
	jmp  wait_key_and_reboot

wait_key_and_reboot:
	mov ah, 0
	int 16h
	jmp 0FFFFh:0; jump to BIOS entry point

.halt:
	cli ; disable interrupts to avoid hlt being disregarded
	hlt

	; Disk operations

	; Converts LBA address to CHS address
	; [Param]  ax LBA address

	; [Return] cx[0-5]  sector
	; [Return] cx[6-15] cylinder
	; [Return] dh head

	; S = (LBA % bdb_sectors_per_track) + 1
	; H = (LBA / bdb_sectors_per_track) % bdb_heads
	; C = (LBA / bdb_sectors_per_track) / bdb_heads

lba_to_chs:

	push ax
	push dx

	;Sector
	xor dx, dx
	div word [bdb_sectors_per_track]; ax DIV dx MOD
	inc dx
	and dx, 0x3F; mask bits
	mov cx, dx

	;Cylinder
	xor dx, dx
	div word [bdb_heads]; ax DIV dx MOD
	mov dh, dl; dh = heads, but res is in dl
	mov ch, al
	shl ah, 6
	or  cl, ah

	pop ax; pop previeous content of dx to ax temporary
	mov dl, al; only apply dx data to dl
	pop ax; pop actual ax back

	ret

	; Reads from disk
	; [Param] ax    LBA address
	; [Param] cl    number of sectors to read (max 128)
	; [Param] dl    drive number
	; [Param] es:bx location in memory to store data read

disk_read:

	push ax
	push bx
	push cx
	push dx
	push di

	push cx; store param since it is used in upcoming func call
	call lba_to_chs
	pop  ax; AL = number of sectors to read

	mov ah, 02h
	mov di, 3

.retry:
	pusha
	stc
	int 13h
	jnc .done; carry reset = success

	;    read failed
	popa
	call disk_reset

	dec  di
	test di, di
	jnz  .retry

.fail:
	jmp floppy_error

.done:
	popa

	pop di
	pop dx
	pop cx
	pop bx
	pop ax

	ret

	; Resets floppy disk controller

	; [Param] dl drive number

disk_reset:
	pusha
	mov ah, 0
	stc
	int 13h
	jc  floppy_error
	popa
	ret

str_hello:      db "Hello using BIOS!", ENDL, 0
str_read_fail:  db "Failed reading floppy", ENDL, 0

times 510-($-$$) db 0
dw    0AA55h
