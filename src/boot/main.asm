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
	;   data segment setup
	mov ax, 0
	mov ds, ax
	mov es, ax

	;   stack setup
	mov ss, ax
	mov sp, 0x7C00

	;    some BIOSes may start at 07C0:0000
	push es
	push word .after
	retf

.after:

	;   read data from floppy
	;   By default the BIOS sets DL to the drive number
	mov [ebr_drive_number], dl

	;    print message
	mov  si, str_loading
	call puts

	;    read drive params -> more secure than "trusting the system"
	push es
	mov  ah, 08h
	int  13h
	jc   floppy_error
	pop  es

	and cl, 0x3F
	xor ch, ch
	mov [bdb_sectors_per_track], cx; sectors

	inc dh
	mov [bdb_heads], dh; heads

	;    read FAT root dir
	;    [ Reserved ] [ FAT ] [ Root Directory ] [ Data ]
	;    LBA of root directory = reserved + fat_count * sectors_per_fat
	;    this is technically a constant expression since we define the fields here
	mov  ax, [bdb_sectors_per_fat]
	mov  bl, [bdb_fat_count]
	xor  bh, bh
	mul  bx
	add  ax, [bdb_reserved_sectors]; LBA of root dir
	push ax; save result to stack

	;   compute size of root directory
	mov ax, [bdb_dir_entries_count]
	shl ax, 5
	xor dx, dx; dx = 0
	div word [bdb_bytes_per_sector]

	test dx, dx; if dx != 0, add 1
	jz   .root_dir_after
	inc  ax

.root_dir_after:

	;    read root directory
	mov  cl, al
	pop  ax; LBA of root dir
	mov  dl, [ebr_drive_number]
	mov  bx, buffer; es:bx = buffer
	call disk_read

	;   search for kernel.bin
	xor bx, bx; counter
	mov di, buffer; points to "file name" field in DirectoryEntry

.search_kernel:
	mov  si, str_filename_kernel_bin
	mov  cx, 11; compare up to 11 chars
	push di
	repe cmpsb; incrementally compare *si and *di until cx-- is null
	pop  di
	je   .found_kernel

	add di, 32
	inc bx
	cmp bx, [bdb_dir_entries_count]
	jl  .search_kernel

	jmp kernel_not_found_error

.found_kernel:
	;   dir should have the address to the entry
	mov ax, [di+26]; DirectryEntry.FirstClusterLow
	mov [u12_kernel_cluster], ax

	;    load FAT from disk
	mov  ax, [bdb_reserved_sectors]; LBA
	mov  cl, [bdb_sectors_per_fat]; sector count
	mov  dl, [ebr_drive_number]; drive number
	mov  bx, buffer; es:bx ptr to buffer
	call disk_read

	;real mode address space (up to 0x100000)
	;     0x00000000 - 0x000003FF : Real Mode Interrupt Vector Table T unusable                |
	;     0x00000400 - 0x000004FF : BIOS data area [BDA]             |_________________________|
	;     0x00000500 - 0x00007BFF : Conventional memory              T                         | 640 KiB RAM
	;     0x00007C00 - 0x00007DFF : OS BootSector                    | usable                  | "Low Memory"
	;     0x00007E00 - 0x0007FFFF : Conventional memory <-- use      |_________________________|
	;     0x00080000 - 0x0009FFFF : Extended BIOS Data Area [EBDA]   T_partially_used_by_EDBA__|_______________
	;     0x000A0000 - 0x000BFFFF : Video memory                     T_hardware_mapped_________T
	;     0x000C0000 - 0x000C7FFF : Video BIOS                       T                         | 384 KiB System
	;     0x000C8000 - 0x000EFFFF : BIOS Expansions                  | ROM and hardware mapped | "Upper Memory"
	;     0x000F0000 - 0x000FFFFF : Motherboard BIOS                 |_________________________|

	;   to read the kernel into it's best to choose the 480.5 KiB region at 0x7E00
	;   since the File Allocation Table is read from 0x7E00 onward it's best to pad the
	;   section in this instance 0x20000 was chose which leaves 98.5 KiB of buffer size
	mov bx, KERNEL_LOAD_SEGMENT
	mov es, bx
	mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:
	;    read next cluster
	mov  ax, [u12_kernel_cluster]
	;    start sector = reserved + fat + sizeof root dir = 1 + 18 +143 = u12_kernel_cluster + 31 =  153
	;    first cluster = (u12_kernel_cluster - 2) * sectors_per_cluster + start_sector
	add  ax, 31; works for now.. only on a floppy.. that's it
	mov  cl, 1
	mov  dl, [ebr_drive_number]
	call disk_read

	;   causes overflow if size > 64KiB if segment is not incremented accordingly
	add bx, [bdb_bytes_per_sector]

	;   get location of next cluster
	mov ax, [u12_kernel_cluster]
	mov cx, 3; fatIndex = current cluster * 3 / 2
	mul cx
	mov cx, 2
	div cx; ax div : dx mod

	mov si, buffer
	add si, ax
	mov ax, [ds:si]

	or dx, dx
	jz .even

.odd:
	shr ax, 4
	jmp .next_cluster_after

.even:
	and ax, 0x0FFF; mask only first 12 bit

.next_cluster_after:
	cmp ax, 0x0FF8
	jae .read_finish

	mov [u12_kernel_cluster], ax
	jmp .load_kernel_loop

.read_finish:

	;   boot device select
	mov dl, [ebr_drive_number]

	;   set up registers for far jump to kernel
	mov ax, KERNEL_LOAD_SEGMENT
	mov ds, ax
	mov es, ax

	jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET

	jmp wait_key_and_reboot

cli
hlt

	; Error Handlers

floppy_error:
	mov  si, str_read_fail
	call puts
	jmp  wait_key_and_reboot

kernel_not_found_error:
	mov  si, str_kernel_not_found
	call puts
	jmp  wait_key_and_reboot

wait_key_and_reboot:
	mov ah, 0
	int 16h
	jmp 0FFFFh:0; jump to BIOS entry point

.halt:
	cli ; disable interrupts to avoid hlt being disregarded
	hlt

	; Printing operations

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

str_loading:             db "Loading...", ENDL, 0
str_read_fail:           db "Failed reading floppy", ENDL, 0
str_filename_kernel_bin: db "KERNEL  BIN"
str_kernel_not_found:    db "kernel not found", ENDL, 0
u12_kernel_cluster       dw 0; 12 FAT cluster

KERNEL_LOAD_SEGMENT equ 0x2000
KERNEL_LOAD_OFFSET equ 0

times 510-($-$$) db 0
dw    0AA55h

buffer:
	;cannot exceed 98.5 KiB of data!!
