; Copyright (c) Teemu Suutari


	bits 64

%ifidn __OUTPUT_FORMAT__, elf64
global onekpaq_decompressor_mode%[ONEKPAQ_DECOMPRESSOR_MODE]_shift
onekpaq_decompressor_mode%[ONEKPAQ_DECOMPRESSOR_MODE]_shift: equ onekpaq_decompressor.shift

global onekpaq_decompressor_mode%[ONEKPAQ_DECOMPRESSOR_MODE]
onekpaq_decompressor_mode%[ONEKPAQ_DECOMPRESSOR_MODE]:
%else
global _onekpaq_decompressor_mode%[ONEKPAQ_DECOMPRESSOR_MODE]_shift
_onekpaq_decompressor_mode%[ONEKPAQ_DECOMPRESSOR_MODE]_shift: equ onekpaq_decompressor.shift

global _onekpaq_decompressor_mode%[ONEKPAQ_DECOMPRESSOR_MODE]
_onekpaq_decompressor_mode%[ONEKPAQ_DECOMPRESSOR_MODE]:
%endif

; cfunc(src, dest) -> rdi=src, rsi=dest
; onekpaq_decomp needs: ebx=src edi=dest

	push rbp
	push rbx
	mov rbx, rdi
	mov rdi, rsi

;%define DEBUG_BUILD

%include "onekpaq_decompressor64.asm"

	pop rbx
	pop rbp
	ret

%ifidn __OUTPUT_FORMAT__, elf64
global onekpaq_decompressor_mode%[ONEKPAQ_DECOMPRESSOR_MODE]_end
onekpaq_decompressor_mode%[ONEKPAQ_DECOMPRESSOR_MODE]_end:
%else
global _onekpaq_decompressor_mode%[ONEKPAQ_DECOMPRESSOR_MODE]_end
_onekpaq_decompressor_mode%[ONEKPAQ_DECOMPRESSOR_MODE]_end:
%endif

	__SECT__

;; ---------------------------------------------------------------------------
