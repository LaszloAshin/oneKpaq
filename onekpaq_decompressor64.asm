; Copyright (c) Teemu Suutari

;; ---------------------------------------------------------------------------
; Please define ONEKPAQ_DECOMPRESSOR_MODE as a compile time option
; from 1 to 4, this number matches the definition from StreamCodec:
; 1 - Single section decoder. Slow decoder for single section data
; 2 - Multi section decode. Slow decoder for multi-section data
; 3 - Single section decoder. Fast decoder for single section data
; 4 - Multi section decode. Fast decoder for multi-section data
;
; Define either shift by ONEKPAQ_DECOMPRESSOR_SHIFT or modify byte
; onekpaq_decompressor.shift later
;; ---------------------------------------------------------------------------

; clean out defines that should not be directly defined
%undef ONEKPAQ_DECOMPRESSOR_FAST
%undef ONEKPAQ_DECOMPRESSOR_MULTI_SECTION

%ifndef ONEKPAQ_DECOMPRESSOR_MODE
%error "please define ONEKPAQ_DECOMPRESSOR_MODE"
; nasm does not know how to stop preprocessor
%define ONEKPAQ_DECOMPRESSOR_MODE
%endif

%ifidn ONEKPAQ_DECOMPRESSOR_MODE,1
; Single section, normal speed
; (default mode)

%elifidn ONEKPAQ_DECOMPRESSOR_MODE,2
; Multi section, normal speed
%define ONEKPAQ_DECOMPRESSOR_MULTI_SECTION 1

%elifidn ONEKPAQ_DECOMPRESSOR_MODE,3
; Single section, fast speed
%define ONEKPAQ_DECOMPRESSOR_FAST 1

%elifidn ONEKPAQ_DECOMPRESSOR_MODE,4
; Multi section, fast speed
%define ONEKPAQ_DECOMPRESSOR_FAST 1
%define ONEKPAQ_DECOMPRESSOR_MULTI_SECTION 1

%else
%error "ONEKPAQ_DECOMPRESSOR_MODE is not valid (1 - 4)"
%endif

%ifndef ONEKPAQ_DECOMPRESSOR_SHIFT
%define ONEKPAQ_DECOMPRESSOR_SHIFT 0
%endif

;; ---------------------------------------------------------------------------

; Debugging can be enabled with DEBUG_BUILD.
; However, debug builds are really really noisy and not PIE.
%ifdef DEBUG_BUILD
%include "debug64.asm"
%else
%macro DEBUG 1+
%endm
%endif

;; ---------------------------------------------------------------------------

	bits 64
	cpu x64

;; end of preproc and setup, start of real stuff

	; embeddable code block
	;
	; inputs:
	; rbx concatenated block1+block2, pointer to start of block2
	; rdi dest (must be zero filled and writable from -13 byte offset
	;     to the expected length plus one byte)
	; header+src+dest buffers must not overlap
	; d flag clear
	; fpu inited and 2 registers free
	;
	; output & side effects:
	; messed up header
	; messed up src
	; dest filled out with unpacked data
	; all registers contents destroyed
	; xmm0 & xmm1 contents destroyed when using fast variant
	; 88 bytes of stack used (56 bytes for fast variant)
onekpaq_decompressor:
	DEBUG "oneKpaq decompression started..."

	lea rsi,[byte rdi-(9+4)]	; rsi=dest, rdi=window start
	lodsd
	inc eax
	mov ecx,eax

%ifdef ONEKPAQ_DECOMPRESSOR_MULTI_SECTION
	lea rdx,[byte rbx+1]		; header=src-3 (src has -4 offset)
%else
	lea rdx,[byte rbx+3]		; header=src-1 (src has -4 offset)
%endif
	; ebp unitialized, will be cleaned by following loop + first decode
	; which will result into 0 bit, before actual data

.normalize_loop:
	shl byte [byte rbx+4],1
	jnz short .src_byte_has_data
	inc rbx
	rcl byte [byte rbx+4],1		; CF==1
.src_byte_has_data:
	rcl ebp,1

.block_loop:
	; loop level 1
	; eax range
	; rbx src
	; ecx dest bit shift
	; rdx header
	; rsi dest
	; rdi window start
	; ebp value
.byte_loop:
.bit_loop:
	; loop level 2
	; eax range
	; rbx src
	; ecx dest bit shift
	; rdx header
	; rsi dest
	; rdi window start
	; ebp value
.normalize_start:
	add eax,eax
	jns short .normalize_loop

	; for subrange calculation
	fld1
	; p = 1
	fld1

	push rax
	push rcx
	push rdx

	mov al, 00h
.context_loop:
	; loop level 3
	; al 0
	; eax negative
	; rbx src
	; cl dest bit shift
 	; ch model
	; rdx header
	; rsi dest
	; rdi window start
	; ebp value
	; st0 p
	; [rsp] ad

	mov ch,[rdx]

	push rax
	push rcx
	push rdx
	push rdi
	cdq
	mov [rbx],edx			; c0 = c1 = -1

%ifdef ONEKPAQ_DECOMPRESSOR_FAST
	movq xmm0,[rsi]			; SSE
%endif

.model_loop:
	; loop level 4
	; al 0
	; [rbx] c1
	; cl dest bit shift
	; ch model
	; edx c0
	; rsi dest
	; rdi window start
	; st0 p
	; [rsp] ad
	; [rsp+32] ad

%ifdef ONEKPAQ_DECOMPRESSOR_FAST
	movq xmm1,[rdi]			; SSE
	pcmpeqb xmm1,xmm0		; SSE
	pmovmskb eax,xmm1		; SSE
	or al,ch
	inc ax
	jnz short .match_no_hit

	mov al,[byte rsi+8]
	rol al,cl
	xor al,[byte rdi+8]
	shr eax,cl
	jnz short .match_no_hit
%else
	; deepest stack usage 24+32+32 bytes = 88 bytes
	push rax
	push rcx
	push rsi
	push rdi

.match_byte_loop:
	; loop level 5
	cmpsb
	rcr ch,1			; ror would work as well
	ja short .match_mask_miss	; CF==0 && ZF==0
	add al,0x60			; any odd multiplier of 0x20 works
	jnz short .match_byte_loop

	lodsb
	rol al,cl
	xor al,[rdi]
	shr al,cl			; undefined CF when cl=8, still works though
					; To make this conform to Intel spec
					; add 'xor eax,eax' after 'pushad'
					; and replace 'shr al,cl' with 'shr eax,cl'
					; -> +2 bytes
.match_mask_miss:
	pop rdi
	pop rsi
	pop rcx
	pop rax
	jnz short .match_no_hit
%endif
	; modify c1 and c0
	dec edx
	dec dword [rbx]

	jc short .match_bit_set
	sar edx,1
%ifndef ONEKPAQ_DECOMPRESSOR_FAST
.match_no_hit:
%endif
	db 0xc0				; rcl cl,0x3b -> nop (0x3b&31=3*9)
.match_bit_set:
	sar dword [rbx],1

;	DEBUG "Model+bit: %hx, new weights %d/%d",ecx,dword [ebx],edx
%ifdef ONEKPAQ_DECOMPRESSOR_FAST
.match_no_hit:
%endif
	inc rdi

	; matching done
	cmp rdi,rsi
%ifdef ONEKPAQ_DECOMPRESSOR_MULTI_SECTION
	ja short .model_early_start
	jnz short .model_loop
%else
	; will do underflow matching with zeros...
	; not ideal if data starts with lots of ones.
	; Usally impact is 1 or 2 bytes, thus mildly
	; better than +2 bytes of code
	jc short .model_loop
%endif
	; scale the probabilities before loading them to FPU
	; p *= c1/c0 =>  p = c1/(c0/p)
.weight_upload_loop:
.shift:	equ $+2
	rol dword [rbx],byte ONEKPAQ_DECOMPRESSOR_SHIFT
	fidivr dword [rbx]
	mov [rbx],edx

%ifdef ONEKPAQ_DECOMPRESSOR_FAST
	neg ecx
	js short .weight_upload_loop
%else
	dec eax
	jp short .weight_upload_loop
%endif

.model_early_start:
	pop rdi
	pop rdx
	pop rcx
	pop rax

.context_reload:
	dec rdx
	cmp ch,[rdx]
	jc short .context_next
	fsqrt
	jbe short .context_reload

.context_next:
	cmp al,[rdx]
	jnz short .context_loop

	pop rdx
	pop rcx
	pop rax

	; restore range
	shr eax,1

	; subrange = range/(p+1)
	faddp st1
	mov [rbx],eax
	fidivr dword [rbx]
	fistp dword [rbx]

	; Arith decode
	DEBUG "value %x, range %x, sr %x",ebp,eax,dword [rbx]
	sub eax,[rbx]
	cmp ebp,eax
%ifdef ONEKPAQ_DECOMPRESSOR_MULTI_SECTION
	jc .dest_bit_is_set;short .dest_bit_is_set
%else
	jbe .dest_bit_is_set;short .dest_bit_is_set
	inc eax
%endif
	sub ebp,eax
	mov eax,[rbx]
;	uncommenting the next command would make the single-section decompressor "correct"
;	i.e. under %ifndef ONEKPAQ_DECOMPRESSOR_MULTI_SECTION
;	does not seem to be a practical problem though
	;dec eax
.dest_bit_is_set:
	rcl byte [byte rsi+8],1

%ifndef ONEKPAQ_DECOMPRESSOR_MULTI_SECTION
	; preserves ZF when it matters i.e. on a non-byte boundary ...
	loop .no_full_byte
	inc rsi
	mov cl,8
.no_full_byte:
	jnz .bit_loop;short .bit_loop

%else
.block_loop_trampoline:
	dec cl
	jnz .bit_loop
;	loop .bit_loop
	inc rsi

	dec word [byte rdx+1]
	jnz .new_byte;short .new_byte

	DEBUG "Block done"
	; next header
.skip_header_loop:
	dec rdx
	cmp ch,[rdx]
	jnz .skip_header_loop;short .skip_header_loop
	lea rdx,[byte rdx-3]
	cmp cx,[byte rdx+1]
	lea rdi,[byte rsi+8]
.new_byte:
	mov cl,9
	jnz .block_loop_trampoline;short .block_loop_trampoline
%endif
	; all done!
	; happy happy joy joy
	DEBUG "oneKpaq decompression done"
onekpaq_decompressor_end:

;; ---------------------------------------------------------------------------
