;Copyright (c) 2026 akm
;This content is under the MIT License.

;directive for NASM
[BITS 16]
[CPU 8086]
SIZE equ 512

	section .text
	global start
start:
	;set offset address for the COM program
	org	0x100
	;init variables
;	mov	byte [isVGADisabled], 0
	;print credit
	mov	dx, Msg_Version
	call	print
	xor	bx, bx

parse:;ds:[si] (si:81h-FFh) parameters
	cld;clear direction flag
	mov	byte [paramBankNumFrom], -1
	mov	si,0x81
parse_0:
	lodsb
parse_1:
	cmp	al,0x0D;=(CR)
	jne	parse_2
	jmp	parse_end
parse_2:
	cmp	al,' '
	jbe	parse_0
	dec	si
	call	getnum
	;the number of banks to dump must be 0 - 15.
	mov	dx, Msg_ErrParamNum
	jc	err
	cmp	bx, 15
	ja	err
	mov	byte [paramBankNumFrom], bl
	mov	byte [paramBankNumTo], bl
	;verify the next is '-'
	lodsb
	cmp	al,'-'
	jne	parse_end
	;the next will be a number
	call	getnum
	mov	dx, Msg_ErrParamNum
	jc	err
	cmp	bx, 15
	ja	err
	mov	byte [paramBankNumTo], bl
	je	parse_end
parse_searchnext:
	lodsb
	cmp	al,0x0D;=(CR)
	je	parse_end
	cmp	al,' '
	jbe	parse_0
	jmp	parse_searchnext
parse_end:
	mov	dx, Msg_ErrParamNum
	mov	al, [paramBankNumFrom]
	cmp	al, -1
	je	err
	mov	bl, [paramBankNumTo]
	;paramBankNumTo must be >= paramBankNumFrom
	cmp	al, bl
	ja	err

	;---begin for debug
;	mov	dx, Msg_ReadConf1
;	call	print
;	mov	dh, [paramBankNumFrom]
;	call	printhex
;	mov	dh, [paramBankNumTo]
;	call	printhex
;	mov	dx, Msg_ReadConf2
;	call	print
	;---end debug

	;get the machine ID (FFFF:Eh) and the sub model ID (FFFF:Bh)
	push	ax
	push	ds
	push	ds
	pop	es
	mov	ax, 0xFFFF
	mov	ds, ax
	mov	al, [ds:0x0e]
	mov	byte [es:machineID_0], al
	mov	al, [ds:0x0b]
	mov	byte [es:machineID_1], al
	pop	ds
	pop	ax
	
	int	0x11
	mov	[equipFlags], ax
	
	;print the Machine ID
	mov	dx, Msg_MachineIDis
	call	print
	mov	dh, [machineID_0]
	call	printhex
	mov	dx, Msg_CrLf
	call	print
	mov	dx, Msg_SubModelIDis
	call	print
	mov	dh, [machineID_1]
	call	printhex
	mov	dx, Msg_CrLf
	call	print
	
	;check the machine ID is not an IBM PC compatibles
	mov	al, [machineID_0]
	cmp	al, 0xf0	;Machine ID is PC or PS/55 (>= F0h)
	jae	MachineIsPC

	;check the current video mode is PS/55 (5550) text
	mov	ah, 0x0F
	int	0x10
	mov	dx, Msg_CurVidMode
	call	print
	mov	dh, al
	call	printhex
	mov	dx, Msg_CrLf
	call	print
	cmp	al, 8
	je	readFont_start
	cmp	al, 0xE
	je	readFont_start
	jmp	VidmodeIsNot55text

MachineIsPC:
	mov	dx, Msg_ErrMachineType
	jmp	err
VidmodeIsNot55text:
	mov	dx, Msg_ErrVidmode
	jmp	err

readFont_start:
	xor	ax, ax
	xor	cx, cx
	mov	ah, 0x3c	;DOS 2+ - CREATE OR TRUNCATE FILE
				;ah = 3Ch, cx = file attribute, DS:DX = ASCIZ filename
	mov	dx, Name_Fontfile
	int	0x21
	mov	dx, Msg_ErrFileOpen
	jc	err

	mov	[hndl], ax
	mov	al, [paramBankNumFrom]
	mov	byte [bankNum], al
loop_nextbank:
	call	ReadFont1Bank
	mov	dx, Msg_ErrFileWrite
	jc	err
nextbankif:
	mov	ah, [bankNum]
	cmp	ah, [paramBankNumTo]	;read until bank [paramBankNum] (= nn * 48k)
	jge	loopEndRead
	inc	ah
	mov	byte [bankNum], ah
	jmp	loop_nextbank
loopEndRead:
	;close a file
	mov	bx, [hndl]
	mov	ah, 0x3e	;DOS: close a file
	int	0x21
	
	xor	ax, ax
	jmp	exit

err:
	;dx = pointer to error message
	push	dx
	mov	dx, Msg_CrLf
	call	print
	pop	dx
	call	print
	mov	al, 1
	jmp	exit
	
exit:
exit_PrintMes:
	;to save return code (AL)
	push	ax
	cmp	al, 1
	jae	exit_err1
	mov	dx, Msg_Exit0
	jmp	exit_toDOS
exit_err1:
	mov	dx, Msg_Exit1
	jmp	exit_toDOS
exit_toDOS:
	call	print
	pop	ax
	mov	ah, 0x02
	mov	dl, 0x07	;buzz
	int	0x21
	mov	ah, 0x4c	;DOS: terminate with return code
	int	0x21
;-----------------------------------------------
;Dump a bank of kanji font ROM data into a file
;[hndl] = file handler to write data
;[bankNum] = bank number to read (1 bank = 48 kb)
;Vertical Sync Video Inactive Time: 0.30 ms = 300 us = 4800 cycles @ 16 MHz
;Horizontal Sync Video Inactive Time: 3.4 us = 54  cycles
ReadFont1Bank:
	push	ax
	push	bx
	push	cx
	push	dx
	mov	word [fontAddrH], 0
	;print "Reading font bank no. n ..."
	mov	dx, Msg_Reading1
	call	print
	mov	dh, [bankNum]
	call	printhex
;	mov	dx, Msg_Reading2
;	call	print
;	mov	dh, [paramBankNum]
	;call	printhex
	mov	dx, Msg_Reading3
	call	print
readFont512:
	jmp	$+2
	;---begin for debug
;	mov	dx, [fontAddrH]
;	call	printhex
;	xchg	dh, dl
;	call	printhex
	;---end debug
	
	cli	;Prevent interrupts
	mov	dx, 0x160
	out	dx, al
	cmp	byte [machineID_1], 0xbe
	je	machineBE_1
	test	byte [equipFlags], 0x04
	jnz	machineBE_1
	mov	dx, 0x16A
	jmp	out16x
machineBE_1:
	mov	dx, 0x168
out16x:
	out	dx, al
	
	;readFont
	push	ds
	pop	es
	
	mov	di, rdata
	mov	ax, [fontAddrH]
	mov	si, ax
	mov	al, [bankNum]
	mov	cl, al
	
	mov	ax, 0xF000
	mov	ds, ax
	mov	al, cl
	mov	byte [ds:0], al;[F000:0] = [bankNum]
	
	jmp	$+2
	jmp	$+2
	
	mov	cx, SIZE
	rep	movsb
	
	push	es
	pop	ds
	
	sti;Allow interrupts
	
	mov	ah, 0x40	;DOS 2+ - WRITE TO FILE OR DEVICE
	mov	bx, [hndl]
	mov	cx, SIZE
	mov	dx, rdata
	int	0x21
	jc	errReadFont
	cmp	ax, cx
	jb	errReadFont
	
	mov	ax, [fontAddrH]
	add	ax, SIZE
	cmp	ax, 0xC000	;read segment F000h - FC00h
	jae	noerrReadFont
	mov	[fontAddrH], ax
	jmp	readFont512
noerrReadFont:
	clc
	jmp	endReadFont
errReadFont:
	stc
endReadFont:
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
;-----------------------------------------------
print:;cs:dx = address to the message
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
printhex:;dh = 2-digit hexadecimal value
	push	ax
	push	cx
	push	dx
	push	ds
	mov	ch, 1
	mov	ax, cs
	mov	ds, ax
	mov	dl, dh
;	shr	dl, 4
	shr	dl, 1
	shr	dl, 1
	shr	dl, 1
	shr	dl, 1
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
getnum:;convert ASCII characters into the numeric value (cf = 1 when the input is invalid)
;[in]ds:si = ASCII of number [out]bx=number, si=point to char after number
	xor	bx, bx
getnum_1:
	lodsb
	sub	al, '0'
	jb	getnum_notnum
	cmp	al, 9
	ja	getnum_notnum
	cbw
	xchg	ax, bx
	mov	dx, 10
	mul	dx 
	add	bx, ax
	;return 0 if the number is larger than 65535
	jc	getnum_toolarge
	jmp	getnum_1
getnum_notnum:
	clc
	jmp	getnum_ret
getnum_toolarge:
	stc
	jmp	getnum_ret
getnum_ret:
	dec	si
	ret
;-----------------------------------------------

	section .data
Name_Fontfile:	db	"DUMP",0
;Msg_ReadConf1:	db	"Read bank: " ,"$" ;debug
;Msg_ReadConf2:	db	0Dh,0Ah,"$" ;debug
Msg_Reading1:	db	"Reading font bank " ,"$"
;Msg_Reading2:	db	" of " ,"$" ;debug
Msg_Reading3:	db	"h ..." ,0Dh,0Ah,"$"
Msg_CurVidMode:	db	"Current video mode:  " ,"$"
Msg_MachineIDis:	db	"Machine ID: " ,"$"
Msg_SubModelIDis:	db	"Sub-Model ID: " ,"$"
Msg_ErrVidmode:	db	"Error: Must run in text mode." ,0Dh,0Ah,"$"
Msg_ErrMachineType:	db	"Error: Unsupported machine type." ,0Dh,0Ah,"$"
Msg_CrLf:	db	0Dh,0Ah,"$"
Msg_ErrFileOpen:
Msg_ErrFileWrite:	db	"Error: Cannot write to DUMP." ,0Dh,0Ah,"$"
Msg_ErrParamNum:	db	"Error: Invalid switch." ,0Dh,0Ah, \
				0Dh,0Ah, \
				"Usage: GETK55 mm[-nn]" ,0Dh,0Ah, \
				"         mm[-nn]   Specifies a range of bank numbers to dump (0-15).",0Dh,0Ah, \
				"                   One bank = 48 kilobytes",0Dh,0Ah, \
				0Dh,0Ah ,"$"
Msg_Exit0:	db	"Dump completed." ,0Dh,0Ah,"$"
Msg_Exit1:	db	"Program terminated." ,0Dh,0Ah,"$"
Msg_Version:	db	"Font ROM Dump Utility for IBM 5550 Version 0.03" ,0Dh,0Ah,"$"
METACREDIT:	db	"Copyright (c) 2026 akm.$"

	section .bss
hndl:	resw	1
fontAddrH:	resw	1
bankNum:	resb	1
paramBankNumFrom:	resb	1
paramBankNumTo:	resb	1
curVidMode:	resb	1
machineID_0:	resb	1
machineID_1:	resb	1
equipFlags:	resw	1
rdata:	resw	SIZE