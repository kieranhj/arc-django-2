; ============================================================================
; Scroller
; ============================================================================

.equ Scroller_Y_Pos, 237

.equ Scroller_Glyph_Width, 16
.equ Scroller_Glyph_Height, 16

.equ Scroller_Code_EOF, 0
.equ Scroller_Code_Wait, 1
.equ Scroller_Code_Speed, 2

scroller_speed:
    .long 4

scroller_delay:
    .long 0

scroller_text_ptr:
	.long scroller_text_string_end_no_adr - 2

scroller_text_start_p:
	.long scroller_text_string_no_adr

scroller_column:
	.long Scroller_Glyph_Width

scroller_glyph_data_ptr:
	.long 0

scroller_font_data_p:
	.long scroller_font_data_no_adr

scroller_update:
	str lr, [sp, #-4]!

    ldr r0, scroller_delay
    cmp r0, #0
    beq .1
    subs r0, r0, #1
    str r0, scroller_delay
	ldrne pc, [sp], #4
	; jump to next char.
	mov r0, #Scroller_Glyph_Width
	str r0, scroller_column
    .1:

	; next column index
	ldr r0, scroller_column
    ldr r1, scroller_speed
	add r0, r0, r1
	cmp r0, #Scroller_Glyph_Width
	; next string char?
	blge get_next_char
	str r0, scroller_column

	.if _DJANGO==1
	; hit a delay so no scroll.
	ldr r2, scroller_delay
	cmp r2, #0
	ldrne pc, [sp], #4

	; next glyph word?
	ands r1, r0, #7		; 8 pixels per word

	;   copy glyph word to a buffer
	bleq get_next_glyph_word

	; scroll the row
	bl scroller_scroll_row
	.endif

	ldr pc, [sp], #4

get_next_char:
	ldr r10, scroller_text_ptr
    
    .1:
	ldrb r0, [r10, #1]!
    cmp r0, #Scroller_Code_Wait
    bne .2

    ; Next byte is time.
	ldrb r0, [r10, #1]!
    mov r0, r0, lsl #3      ; wait value * 8 frames.
    str r0, scroller_delay
	mov r0, #0				; scroller_column
    b .5

    .2:
    cmp r0, #Scroller_Code_Speed
    bne .3

    ; Next byte is speed.
	ldrb r0, [r10, #1]!
    str r0, scroller_speed
    b .1

    .3:
	cmp r0, #Scroller_Code_EOF
	bne .4

    ; Loop text.
	ldr r10, scroller_text_start_p
	sub r10, r10, #1
    b .1

    .4:
	.if _DJANGO==1
	adr r9, scroller_font_data
	sub r0, r0, #ASCII_Space	; start at ' '
	; TODO: Multiply by constant macros.
	add r9, r9, r0, lsl #7		; *128 bytes per glyph.
	str r9, scroller_glyph_data_ptr
	.endif
	
	mov r0, #0	; cur_column

	.5:
	str r10, scroller_text_ptr
	mov pc, lr

.if _DJANGO==1
; r0=column
get_next_glyph_word:
	ldr r9, scroller_glyph_data_ptr
	adr r10, scroller_glyph_column_buffer

	mov r0, r0, lsr #3	; div 8 to get column.
	add r9, r9, r0, lsl #2	; *4 to get word.
	mov r1, #Scroller_Glyph_Height
	.1:
	ldr r2, [r9], #Scroller_Glyph_Width/2	; stride.
	str r2, [r10], #4
	subs r1, r1, #1
	bne .1
	mov pc, lr

scroller_scroll_row:
	str lr, [sp, #-4]!

	; set border colour!
	SET_BORDER 0x0000ff

	ldr r12, screen_addr
	mov r0, #Scroller_Y_Pos
	add r9, r12, r0, lsl #7	; y*128
	add r9, r9, r0, lsl #5	; +y*32 = y*160

    ldr r12, scroller_speed
    mov r12, r12, lsl #2    ; pixel shift (lsr #4*n)

	mov r11, #0
	.1:
	adr r0, scroller_glyph_column_buffer
	ldr r10, [r0, r11, lsl #2]	; r10=scroller_glyph_column_buffer[r11]
	bl scroller_scroll_line
	adr r0, scroller_glyph_column_buffer
	str r10, [r0, r11, lsl #2]	; scroller_glyph_column_buffer[r11]=r10
	add r11, r11, #1
	cmp r11, #Scroller_Glyph_Height
	blt .1

	; set border colour!
	SET_BORDER 0x000000
	ldr pc, [sp], #4

.macro scroller_shift_left_by_pixels
	; shift word right 4 bits to clear left most pixel
	mov r0, r0, lsr r12
	; mask in right most pixel from next word
	orr r0, r0, r1, lsl r14
    ; etc.
	mov r1, r1, lsr r12
	orr r1, r1, r2, lsl r14
	mov r2, r2, lsr r12
	orr r2, r2, r3, lsl r14
	mov r3, r3, lsr r12
	orr r3, r3, r4, lsl r14
	mov r4, r4, lsr r12
	orr r4, r4, r5, lsl r14
	mov r5, r5, lsr r12
	orr r5, r5, r6, lsl r14
	mov r6, r6, lsr r12
	orr r6, r6, r7, lsl r14
	mov r7, r7, lsr r12
	orr r7, r7, r8, lsl r14
.endm

; R9=line address, R10=right hand word, R12=pixel shift
scroller_scroll_line:
	str lr, [sp, #-4]!
    rsb r14, r12, #32       ; reverse pixel shift (lsl #32-4*n)

	ldmia r9, {r0-r8}		; read 9 words = 36 bytes = 72 pixels
    scroller_shift_left_by_pixels
	stmia r9!, {r0-r7}		; write 8 words = 32 bytes = 64 pixels

	ldmia r9, {r0-r8}		; read 9 words = 36 bytes = 72 pixels
    scroller_shift_left_by_pixels
	stmia r9!, {r0-r7}		; write 8 words = 32 bytes = 64 pixels

	ldmia r9, {r0-r8}		; read 9 words = 36 bytes = 72 pixels
    scroller_shift_left_by_pixels
	stmia r9!, {r0-r7}		; write 8 words = 32 bytes = 64 pixels

	ldmia r9, {r0-r8}		; read 9 words = 36 bytes = 72 pixels
    scroller_shift_left_by_pixels
	stmia r9!, {r0-r7}		; write 8 words = 32 bytes = 64 pixels

	ldmia r9, {r0-r7}		; read 8 words = 32 bytes = 64 pixels
    mov r8, r10
    scroller_shift_left_by_pixels
	stmia r9!, {r0-r7}		; write 8 words = 32 bytes = 64 pixels

	mov r10, r10, lsr r12	; rotate new data word
	ldr pc, [sp], #4

scroller_glyph_column_buffer:
	.skip Scroller_Glyph_Height * 4
.else

; Returns R9 = glyph ptr.
scroller_get_next_glyph:
    ldrb r0, [r12], #1

	; Loop end of text.
    cmp r0, #0
    ldreq r12, scroller_text_start_p
    beq scroller_get_next_glyph

	; Skip control codes.
	cmp r0, #ASCII_Space
	blt scroller_get_next_glyph

	sub r0, r0, #ASCII_Space
	ldr r9, scroller_font_data_p
	add r9, r9, r0, lsl #7		; *128 bytes per glyph.
	mov pc, lr

; Draw entire scroller.
; R12=screen addr
scroller_draw:
    str lr, [sp, #-4]!

    mov r0, #Scroller_Y_Pos
    add r11, r12, r0, lsl #7
    add r11, r11, r0, lsl #5        ; assume stride is 160.

    ldr r12, scroller_text_ptr
	bl scroller_get_next_glyph		; r9=ptr to glyph data

    ldr r8, scroller_column

	; TODO: Deal with shifting 16 columns!
	; Current approach not going to work!!!

	movs r5, r8, lsr #3				; word parity
	addne r9, r9, #4				; skip a glyph word

	and r8, r8, #7					; shift within word
    mov r8, r8, lsl #2              ; shift for second word.
    rsb r7, r8, #32                 ; shift for first word.
    mov r10, #0                     ; screen word.

    ; Word loop.
    .1:

    ; Row loop.
    mov r6, #Scroller_Glyph_Height

    .2:
    ldr r0, [r9], #8				; get glyph word, move to next row.

    mov r1, r0, lsr r8              ; second glyph word shifted.
    mov r0, r0, lsl r7              ; first glyph word shifted.

    cmp r0, #0                      ; if first glyph is empty?
    beq .3                          ; skip.

    ; display first glyph word in prev screen word.
    cmp r10, #0
    beq .3                          ; skip if left hand edge of screen.

    ldr r2, [r11, #-4]              ; load prev screen word.
    bic r2, r2, r0
    orr r2, r2, r0                  ; mask in first glyph word.
    str r2, [r11, #-4]              ; store prev screen word.

    ; display second glyph word in current screen word.
    .3:
    cmp r10, #40
    bge .4                          ; skip if right hand edge of screen.

    ldr r2, [r11]                   ; load current screen word.
    bic r2, r2, r1
    orr r2, r2, r1                  ; mask in second glyph word.
    str r2, [r11]                   ; store prev screen word.

	.4:	
    add r11, r11, #Screen_Stride
    subs r6, r6, #1
    bne .2                          ; next row.

	; Next glyph word.
	eors r5, r5, #1
	subne r9, r9, #Scroller_Glyph_Height*8 - 4	; next glyph word on row 0.
	bleq scroller_get_next_glyph

	; Next screen word.
    sub r11, r11, #Scroller_Glyph_Height*Screen_Stride - 4

    add r10, r10, #1                ; next screen word.
    cmp r10, #41                    ; one extra word for scroll!
    bne .1

    ldr pc, [sp], #4

.endif
