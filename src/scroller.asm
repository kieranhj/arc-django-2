; ============================================================================
; Scroller
; ============================================================================

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
	.long 0

scroller_cur_column:
	.long 15

scroller_glyph_data_ptr:
	.long 0

scroller_init:
	adr r0, scroller_text_string_end
	sub r0, r0, #1
	str r0, scroller_text_ptr
	mov pc, lr

scroller_update:
    ldr r0, scroller_delay
    cmp r0, #0
    beq .1
    subs r0, r0, #1
    str r0, scroller_delay
    mov pc, lr

    .1:
	str lr, [sp, #-4]!

	; next column index
	ldr r0, scroller_cur_column
    ldr r1, scroller_speed
	add r0, r0, r1
	cmp r0, #Scroller_Glyph_Width
	; next string char?
	blge get_next_char
	str r0, scroller_cur_column

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
	ldr pc, [sp], #4

get_next_char:
	ldr r10, scroller_text_ptr
    
    .1:
	ldrb r0, [r10], #1
    cmp r0, #Scroller_Code_Wait
    bne .2

    ; Next byte is time.
	ldrb r0, [r10], #1
    mov r0, r0, lsl #3      ; wait value * 8 frames.
    str r0, scroller_delay
	mov r0, #Scroller_Glyph_Width		; scroller_cur_column
    b .5

    .2:
    cmp r0, #Scroller_Code_Speed
    bne .3

    ; Next byte is speed.
    ldrb r0, [r10], #1
    str r0, scroller_speed
    b .1

    .3:
	cmp r0, #Scroller_Code_EOF
	bne .4

    ; Loop text.
	adr r10, scroller_text_string
    b .1

    .4:
	adr r9, scroller_font_data
	sub r0, r0, #ASCII_Space	; start at ' '
	; TODO: Multiply by constant macros.
	add r9, r9, r0, lsl #7		; *128 bytes per glyph.
	str r9, scroller_glyph_data_ptr
	mov r0, #0	; cur_column

	.5:
	str r10, scroller_text_ptr
	mov pc, lr

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
	.if _DEBUG_RASTERS
	adr r0, vdu_set_border_red
	mov r1, #6
	swi OS_WriteN
	.endif

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
	.if _DEBUG_RASTERS
	adr r0, vdu_set_border_black
	mov r1, #6
	swi OS_WriteN
	.endif
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
