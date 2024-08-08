;Copyright (c) 2023-2024 akm
;This content is under the MIT License.
;You have to save this file with Shift JIS encoding to avoid resulting mojibake.

;directive for NASM
[BITS 16]
ID_TSR	equ	0xE8A2
ID_INSTALLED	equ	0xDEE2

	section .text
	global start
start:
	;set offset address for the COM program
	org	0x100
	;jump to the entry point
	jmp	init_entry

;workarea for TSR
org_int10:	dw	0,0
org_int2F:	dw	0,0

;patch_dcb
;This overwrites the device configuration block in the DOS I/O workarea
; to indicate that the Graphics Support Hardware is not supported.
patch_dcb:
	;The Display Configuration Block may be addressed at 0BEB:06F2h(0000C5A2h) <- JDOS 4 only
	;Int 1Fh : Get the address to the Device Configuration Block (PS/55 DOS only)
	;Return: AX = AX, CX = number of data(?), ES:BX = segment:offset
	push	ax
	push	bx
	push	cx
	push	es
	xor	ax, ax
	mov	es, ax
	;request the Display Configulation Block
	mov	ax, 0x0008
	int	0x1F
	mov	ax, es
	cmp	ax, 0
	je	patch_dcb_noDCB
	and	byte [es:bx], 0xDF
patch_dcb_noDCB:
	pop	es
	pop	cx
	pop	bx
	pop	ax
	ret
;-----------------------------------------------
;new_int10
new_int10_entry:
	;patch the DCB if the videomode set (INT 10H, AH=00h) is called
	cmp	ah, 0
	jne	new_int10_next
	;call the original Int 10h and then patch the DCB
	pushf
	call	 far [cs:org_int10]
;	;backup registers
;	push	ax
;	push	bx
;	push	dx
;	;backup the current Int 10h vector
;	push	es
;	mov	ax, 0x3510
;	int	0x21
;	mov	word [cs:org2_int10], bx
;	mov	word [cs:org2_int10 + 2], es
;	pop	es
;	;restore the original Int 10h vector
;	push	ds
;	mov	dx, word [cs:org_int10]
;	mov	ds, word [cs:org_int10 + 2]
;	mov	ax, 0x2510
;	int	0x21
;	pop	ds
;	;restore registers
;	pop	dx
;	pop	bx
;	pop	ax
;	;call the original Int 10h
;	int	0x10
;	;restore the vector
;	push	ax
;	push	dx
;	push	ds
;	mov	dx, word [cs:org2_int10]
;	mov	ds, word [cs:org2_int10 + 2]
;	mov	ax, 0x2510
;	int	0x21
;	pop	ds
;	pop	dx
;	pop	ax
	;patch the DCB
	call	patch_dcb
	iret
new_int10_next:
	;chain to the next handler
	jmp	 far [cs:org_int10];jmp dword ptr cs:byte_1010A
;-----------------------------------------------
;new_int2F
new_int2F_entry:
	cmp	ax, ID_TSR
	jne	new_int2F_next
	;return ID_INSTALLED if my process is called
	mov	ax, ID_INSTALLED
	iret
new_int2F_next:
	;chain to the next handler
	jmp	far [cs:org_int2F]
;-----------------------------------------------
end_resident_code:;for cutting off the remains of TSR
;-----------------------------------------------
;メッセージ出力 : DX = $で終わる文字列のアドレス
print:
	mov	ax, cs
	mov	ds, ax
	mov	ah, 9
	int	0x21
	ret
;-----------------------------------------------
;checkTSR
checkTSR:
	;Check TSR and parse parameters
	;return AL = 1 if it's already installed
	mov	ax, ID_TSR
	push	ds
	int	0x2F
	pop	ds
	cmp	ax, ID_INSTALLED
	je	checkTSR_Installed
	;install TSR if 'F' in parameters
	mov	ax, cs
	mov	es, ax
	call	parse
	cmp	al, 'F'
	je	checkTSR_InstallTSR
	mov	dx, Mes_NotInstalled
	mov	al, 1
	jmp	checkTSR_exit
checkTSR_Installed:
	mov	dx, Mes_AlreadyInstalled
	mov	al, 1
	jmp	checkTSR_exit
checkTSR_InstallTSR:
	mov	al, 0
checkTSR_exit:
	ret
;-----------------------------------------------
;parse
parse:;ds:[si] (si:81h-FFh) parameters
	cld;clear direction flag
	mov	si,0x81
parse_0:
	lodsb
parse_1:
	cmp	al,0x0D
	jne	parse_2
	jmp	parse_end
parse_2:
	cmp	al,' '
	jbe	parse_0
	and	al,0xDF;to upper case
	cmp	al,'F'
	je	parse_f
	jmp	parse_end
parse_f:
parse_end:
	ret
;-----------------------------------------------
;init_entry
init_entry:
	mov	dx, Mes_Version
	call	print
	;check the DOS version >= 3.00
	mov	ax, 0x3000
	int	0x21
	mov	dx, Mes_DOSVer
	cmp	al, 3
	jb	mes_exit
	;check the current DOS is for PS/55
	;this procedure may work for DOS/V only (what if Japanese MS-DOS/V?)
	; Int 15h, AX=4900h - Get BIOS type (DOS/V only?)
	;  Return: CF=0, BL=0 PS/2 or DOS/V, BL=1 PS/55(never used?)
	mov	ax, 0x4900
	int	0x15
	jc	init_ChkDOS2
	cmp	ah, 0
	jne	init_ChkDOS2
	mov	dx, Mes_DOSType
	cmp	bl, 1
	jne	mes_exit;this works for DOS/V
	jmp	init_ChkDOSok
init_ChkDOS2:
 	;check Int 7Dh vector is not 0 (if it is then PC DOS)
 	mov	ax, 0x357D
 	int	0x21
 	cmp	bx, 0
 	jne	init_ChkDOSok
 	mov	ax, es
 	cmp	ax, 0
 	jne	init_ChkDOSok
 	mov	dx, Mes_DOSType
	jmp	mes_exit;this works for non-IBMJ DOS
init_ChkDOSok:
	;Patch the DCB once
	call	patch_dcb
	;check TSR already exists (AL = 1 if installed)
	call	checkTSR;
	cmp	al, 1
	je	skip_install
	;Case 1: Install TSR and exit
	;get and overwrite Int 10h vector
	mov	ax, 0x3510
	int	0x21
	mov	word [org_int10], bx
	mov	word [org_int10 + 2], es
	
	mov	dx, new_int10_entry
	mov	ax, 0x2510
	int	0x21
	;get and overwrite Int 2Fh vector
	mov	ax, 0x352F
	int	0x21
	mov	word [org_int2F], bx
	mov	word [org_int2F + 2], es
	
	mov	dx, new_int2F_entry
	mov	ax, 0x252F
	int	0x21
	;print message and exit
	mov	dx, Mes_Installed
	call	print
	;terminate but stay resident
	mov	ax, 0x3100
	;calculate the number of paragraphs to keep resident
	lea	dx, end_resident_code
	mov	cl, 4
	shr	dx, cl
	add	dx, 0x11;0x10(100h) for PSP, and one(10h) for remainders
	int	0x21
	;Case 2: Exit without installing TSR
skip_install:
mes_exit:;DX = address to message
	call	print
exit:
	;Terminate with return code
	mov	ax, 0x4C00
	int	0x21
;*** exit and return to DOS ***
;-----------------------------------------------
	section .data
Mes_Installed:	db	"常駐しました. INT 10h, AH=00hをフックします." ,0Dh,0Ah,"$"
Mes_NotInstalled:	db	"ディスプレイ構成ブロックをパッチしました." ,0Dh,0Ah,"$"
Mes_AlreadyInstalled:	db	"既に常駐しています. ディスプレイ構成ブロックを再パッチしました." ,0Dh,0Ah,"$"
Mes_DOSVer:	db	"Error: DOS 3.0 or later required." ,0Dh,0Ah,"$"
Mes_DOSType:	db	"Error: The current DOS does not support PS/55 DOS BIOS." ,0Dh,0Ah,"$"
Mes_Version:	db	"dcbpatch Ver.1.01" ,0Dh,0Ah,"$"
METACREDIT:	db	"Enhanced Graphics Abandoner for PS/55 DOS; Copyright (c) 2024 akm.$"
