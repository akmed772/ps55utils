;Copyright (c) 2024 akm
;This content is under the MIT License.
;You have to save this file with Shift JIS encoding to avoid resulting mojibake.

;directive for NASM
[BITS 16]
SIZE equ 32768

	section .text
	global start
start:
	;set offset address for the COM program
	org	0x100
	;print credit
	mov	dx, Msg_Version
	call	print
	;check the current video mode is PS/55 text mode
	mov	ah, 0x0F
	int	0x10
;	mov	dx, Msg_CurVidMode
;	call	print
;	mov	dh, al
;	call	printhex
	;save current video mode
	cmp	al, 8
	je	VidmodeIs55
	cmp	al, 0xE
	je	VidmodeIs55
	cmp	al, 0xA
	je	VidmodeIs55
	cmp	al, 0xD
	je	VidmodeIs55
	cmp	al, 0xF
	je	VidmodeIs55
	;check the text buffer window (e0000h-e0fffh) is disabled
	mov	dx, 0xe1
	in	al, dx
	test	al, 0x02
	jnz	VidmodeIs55
	jmp	VidmodeIsOthers
VidmodeIs55:
	mov	dx, Msg_ErrVidmode
	jmp	err
VidmodeIsOthers:
;Check the Model byte in BIOS ROM = F8h
	mov	ax, 0xF000
	mov	es, ax
	mov	al, es:[0xFFFE]
	mov	dx, Msg_ErrModelID
	cmp	al, 0xF8
	jnz	err
;Check XMS driver not installed
	mov	ax, 0x4300	;EXTENDED MEMORY SPECIFICATION (XMS) v2+ - INSTALLATION CHECK
	int	0x2f
	cmp	al, 0x80	;al = 80h XMS driver installed
	jne	noxms
	mov	dx, Msg_WarnXMS
	call	print
noxms:
;Open file
	xor	ax, ax
	xor	cx, cx
	mov	ah, 0x3c	;DOS 2+ - CREATE OR TRUNCATE FILE
				;ah = 3Ch, cx = file attribute, DS:DX = ASCIZ filename
	mov	dx, Name_Dumpfile
	int	0x21
	mov	dx, Msg_ErrFileOpen
	jc	err
	mov	[hndl], ax
;Read data from BIOS ROM area
	mov	ax, 0xE000
	mov	cx, 4
readbios:
;print "Current reading address: xxxx"
	mov	dx, Msg_AddrReading
	call	print
	mov	dh, ah
	call	printhex
	mov	dh, al
	call	printhex
	mov	dx, Msg_CrLf
	call	print
	push	cx
	push	ax
;disable shadow RAM
	push	ax
	mov	dx, 0xe1
	in	al, dx
	mov	byte [bakE1], al
	or	al, 0x02
	out	dx, al
	jmp	$+2
	jmp	$+2
	pop	ax
;set target addresses
	push	ds
	pop	es
	mov	ds, ax
	mov	si, 0
	mov	di, rdata
	mov	cx, SIZE
	cli	;disable interrupt
;copy es:di to ds:rdata
movedata:
	rep	movsb
;enable shadow RAM
	push	es
	pop	ds
	mov	dx, 0xe1
	mov	al, [bakE1]
	out	dx, al
	jmp	$+2
	jmp	$+2
	sti	;enable interrupt
;write buf to file
	mov	ah, 0x40	;DOS 2+ - WRITE TO FILE OR DEVICE
	mov	bx, [hndl]
	mov	cx, SIZE
	mov	dx, rdata
	int	0x21
	mov	dx, Msg_ErrFileWrite
	jc	err
	cmp	ax, cx
	jb	err
;next loop
	pop	ax
	pop	cx
	add	ax, 0x800
	loop	readbios
;end loop and close the file
	mov	bx, [hndl]
	mov	ah, 0x3e	;DOS: close a file
	int	0x21
	
	mov	dx, Msg_Complete
	call	print
	xor	ax, ax
	jmp	exit
;-----------------------------------------------
;
print:;dx = address to the message
	push	ax
	push	ds
	mov	ax, cs
	mov	ds, ax
	mov	ah, 9
	int	0x21
print_end:
	pop	ds
	pop	ax
	ret
;-----------------------------------------------
printhex:;dh = hexadecimal value
	push	ax
	push	cx
	push	dx
	push	ds
	mov	ch, 1
	mov	ax, cs
	mov	ds, ax
	mov	dl, dh
	shr	dl, 4
printhex_toA:
	add	dl, 0x30
	cmp	dl, 0x39
	jbe	printhex_out
	add	dl, 7
printhex_out:
	mov	ah, 0x02
	int	0x21
	mov	dl, dh
	and	dl, 0xF
	cmp	ch, 0
	jz	printhex_end
	dec	ch
	jmp	printhex_toA
printhex_end:
	pop	ds
	pop	dx
	pop	cx
	pop	ax
	ret
;-----------------------------------------------
;
err:
	call	print
	mov	al, 1
	jmp	exit
	
exit:
	jmp	exit_toDOS
exit_toDOS:
	mov	ah, 0x02
	mov	dl, 0x07	;buzz
	int	0x21
	mov	ah, 0x4c	;DOS: terminate with return code
	int	0x21

	section .data
Name_Dumpfile:	db	"SYSBIOS.BIN",0
;Msg_CurVidMode:	db	"The current video mode is " ,"$"
Msg_ErrVidmode:	db	"Error: Must run in PS/2 text mode." ,0Dh,0Ah, \
				"エラー: PS/2英語(US)モードに切り替えてから再度実行して下さい." ,0Dh,0Ah,"$"
Msg_CrLf:	db	0Dh,0Ah,"$"
Msg_ErrFileOpen:
Msg_ErrFileWrite:	db	"Error: Cannot write to SYSBIOS.BIN." ,0Dh,0Ah, \
				"       This program requires 128 KB of free drive space." ,0Dh,0Ah ,"$"
Msg_ErrModelID:	db	"Error: This computer is not supported." ,0Dh,0Ah,"$"
Msg_WarnXMS:	db	"Warning: XMS driver is installed. The BIOS ROM data would have been changed." ,0Dh,0Ah,"$"
Msg_AddrReading:	db	"Reading: ","$"
Msg_Version:	db	"BIOS Dump for PS/55 Ver.0.01" ,0Dh,0Ah,\
			"This has never been tested on the real machine. I'm glad if you send me a feedback." ,0Dh,0Ah,"$"
Msg_Complete:	db	"Dump completed." ,0Dh,0Ah,"$"
METACREDIT:	db	"Copyright (c) 2024 akm.$"

	section .bss
hndl:	resw	1
bakE1:	resb	1
rdata:	resb	SIZE