; ============================================================================
; New font for Django 2.
; ============================================================================

.equ NewFont_MaxGlyphs, 42
.equ NewFont_GlyphHeight, 5
.equ NewFont_GlyphWidth, 8
.equ NewFont_SpaceWidth, 5
.equ NewFont_I_Width, 4
.equ NewFont_AdjustPadding, 2       ; pixels

.equ ASCII_a, 97
.equ ASCII_z, 122
.equ ASCII_A, 65
.equ ASCII_i, 'i'
.equ ASCII_Z, 90
.equ ASCII_0, 48
.equ ASCII_9, 57
.equ ASCII_ExclamationMark, 33
.equ ASCII_Colon, 58
.equ ASCII_Space, 32
.equ ASCII_Minus, 45
.equ ASCII_LessThan, 60
.equ ASCII_MoreThan, 62

.equ VDU_SetPos, 31

.equ NewFont_a, 0
.equ NewFont_z, 25
.equ NewFont_0, 26
.equ NewFont_9, 35
.equ NewFont_ExclamationMark, 36
.equ NewFont_Colon, 37
.equ NewFont_Space, 38
.equ NewFont_Minus, 39
.equ NewFont_LessThan, 40
.equ NewFont_MoreThan, 41

; ============================================================================

new_font_data_p:
    .long new_menu_font_data_no_adr

new_font_map_p:
    .long new_font_map_no_adr

new_font_map_from_ascii:
    .byte ASCII_Space, NewFont_Space, 1
    .byte ASCII_ExclamationMark, NewFont_ExclamationMark, 1
    .byte ASCII_Minus, NewFont_Minus, 1
    .byte ASCII_Colon, NewFont_Colon, 1
    .byte ASCII_LessThan, NewFont_LessThan, 1
    .byte ASCII_MoreThan, NewFont_MoreThan, 1

    .byte ASCII_0, NewFont_0, 10
    .byte ASCII_a, NewFont_a, 26
    .byte -1, -1, -1
.p2align 2

; ============================================================================

; Create map of ASCII to small font glyph:
new_font_init:
    ldr r3, new_font_map_p
    adr r4, new_font_map_from_ascii
.1:
    ldrb r0, [r4], #1   ; ascii
    ldrb r1, [r4], #1   ; new font glyph no.
    ldrb r5, [r4], #1   ; count
    
    cmp r5, #0xff
    beq .3

.2:
    ; R0=ascii
    ; R1=small font glyph #
    strb r1, [r3, r0]   ; store gylph no. at ascii offset
    subs r5, r5, #1
    beq .1

    add r0, r0, #1
    add r1, r1, #1
    b .2

.3:
    mov pc, lr

.if 0
; R11=screen addr to plot at (updated).
; R10=colour word.
; R0=ASCII.
; Trashes: r3, r4, r9
new_font_plot_glyph:
    ldr r3, new_font_map_p
    ldrb r0, [r3, r0]       ; ascii->glyph no.

    ldr r9, new_font_data_p
    .if NewFont_GlyphHeight == 5
    add r9, r9, r0, lsl #4
    add r9, r9, r0, lsl #2
    .else
    .err "Expected NewFont_GlyphHeight to be 5!" 
    .endif

    .rept NewFont_GlyphHeight
    ldr r3, [r9], #4                ; glyph word
    ldr r4, [r11]                   ; screen word
    bic r4, r4, r3                  ; clear glyph bits from screen word
    and r3, r3, r10                 ; mask in colour word
    orr r4, r3, r4                  ; mask colour glyph word into screen
    str r4, [r11], #Screen_Stride   ; next line
    .endr

    sub r11, r11, #NewFont_GlyphHeight*Screen_Stride - 4
    mov pc, lr

; R0=ptr to string
; R10=colour word
; R11=screen addr to plot at (updated).
; R12=screen base addr (required if using VDU 31).
; Trashes r3, r4, r6, r9
new_font_plot_string:
	str lr, [sp, #-4]!

    mov r6, r0
.1:
    ldrb r0, [r6], #1           ; next char
    cmp r0, #0                  ; EOS
	ldreq pc, [sp], #4          ; rts

    cmp r0, #VDU_SetPos
    bne .2

    ; Set Pos - next two bytes are (column,line)
    ldrb r3, [r6], #1
    ldrb r4, [r6], #1

    add r11, r12, r4, lsl #7    ; line * 128
    add r11, r11, r4, lsl #5    ; + line * 32 = line * 160
    add r11, r11, r3, lsl #2    ; column.
    b .1

.2:
    bl new_font_plot_glyph
    b .1
.endif

; ============================================================================

; R12=buffer stride.    ; TODO: Maybe just fix this for simplicity?
; R11=buffer ptr (word addr to plot) (updated).
; R6=pixel offset (updated)
; R0=ASCII.
; Trashes: r2-r4, r7-r9
new_font_plot_glyph_to_buffer:
	str lr, [sp, #-4]!

    ldr r3, new_font_map_p
    ldrb r2, [r3, r0]       ; ascii->glyph no.

    ldr r9, new_font_data_p
    .if NewFont_GlyphHeight == 5
    add r9, r9, r2, lsl #4
    add r9, r9, r2, lsl #2
    .else
    .err "Expected NewFont_GlyphHeight to be 5!" 
    .endif

    mov r8, r6, lsl #2              ; word shift
    rsb r7, r8, #32                 ; reverse word shift

    mov r14, #NewFont_GlyphHeight
.1:
    ldr r3, [r9], #4                ; glyph word

	mov r2, r3, lsr r7			    ; R2 = pixels in next word
	mov r3, r3, lsl r8			    ; R3 = pixels in this word (shifting left moves pixels right)

    ldr r4, [r11, #0]               ; this word
    bic r4, r4, r3                  ; clear glyph bits from this word
    orr r4, r3, r4                  ; mask colour glyph word into screen
    str r4, [r11, #0]               ; this word

    ; TODO: Watch for buffer overrun!
    cmp r2, #0
    beq .2
    ldr r4, [r11, #4]               ; next word
    bic r4, r4, r2                  ; clear glyph bits from next word
    orr r4, r2, r4                  ; mask colour glyph word into screen
    str r4, [r11, #4]               ; next word
    .2:

    add r11, r11, r12               ; next line
    subs r14, r14, #1
    bne .1

    ; restore buffer ptr.
    sub r11, r11, r12, lsl #2
    sub r11, r11, r12

    add r6, r6, #NewFont_GlyphWidth
    cmp r0, #ASCII_Space
    subeq r6, r6, #NewFont_GlyphWidth-NewFont_SpaceWidth
    cmp r0, #ASCII_i
    subeq r6, r6, #NewFont_GlyphWidth-NewFont_I_Width

    cmp r6, #8
    addge r11, r11, #4              ; next word
    subge r6, r6, #8                ; correct pixel

	ldr pc, [sp], #4


; R2=ptr to string
; Returns R6=pixel width.
; Trashes R0.
new_font_get_pixel_width_for_string:
    mov r6, #0
.1:
    ldrb r0, [r2], #1           ; next char
    cmp r0, #0                  ; EOS
	moveq pc, lr

    add r6, r6, #NewFont_GlyphWidth
    cmp r0, #ASCII_Space
    subeq r6, r6, #NewFont_GlyphWidth-NewFont_SpaceWidth
    cmp r0, #ASCII_i
    subeq r6, r6, #NewFont_GlyphWidth-NewFont_I_Width
    b .1

; R1=ptr to string (updated).
; R10=adjust flag (0=LHS, otherwise RHS)
; R11=buffer_ptr (updated).
; Returns R12=buffer stride.
new_font_plot_string_as_sprite:
	str lr, [sp, #-4]!

    mov r2, r1
    bl new_font_get_pixel_width_for_string
    ; R6=width of string in pixels.

    ; Padding.
    add r6, r6, #NewFont_AdjustPadding

    ; Extend pixel width to words.
    add r12, r6, #7
    bic r12, r12, #7
    sub r6, r12, r6                     ; RHS adjustment = buffer width - pixel width
    mov r12, r12, lsr #1
    ; R12=width of buffer in bytes (stride).

    cmp r10, #0
    moveq r6, #NewFont_AdjustPadding    ; LHS adjustment.
    ; R6=pixel offset (updated)

    mov r0, #0
    mov r2, r11
    add r3, r2, r12, lsl #2
    add r3, r3, r12
.3:
    str r0, [r2], #4
    cmp r2, r3
    blt .3

.1:
    ldrb r0, [r1], #1           ; next char
    cmp r0, #0                  ; EOS
	beq .2

    ; R12=buffer stride.
    ; R11=buffer ptr (word addr to plot) (updated).
    ; R0=ASCII.
    bl new_font_plot_glyph_to_buffer
    b .1
.2:
    ; Update buffer ptr to end of this buffer.
    add r11, r11, r12, lsl #2
    add r11, r11, r12           ; ptr += 5*stride

	ldr pc, [sp], #4
