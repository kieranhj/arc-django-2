; Plot small font in MODE 9.
; Small font 8x5 pixels 1bpp.

.equ SmallFont_Height, 5
.equ ASCII_a, 97
.equ ASCII_z, 122
.equ ASCII_A, 65
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
.equ VDU_SetTextColour, 17

.equ SmallFont_a, 0
.equ SmallFont_z, 25
.equ SmallFont_0, 26
.equ SmallFont_9, 35
.equ SmallFont_ExclamationMark, 36
.equ SmallFont_Colon, 37
.equ SmallFont_Space, 38
.equ SmallFont_Minus, 39
.equ SmallFont_LessThan, 40
.equ SmallFont_MoreThan, 41
.equ SmallFont_BoldBase, 42 ; add this to make glyphs bold.

small_font_bold_flag:
    .long 0

small_font_ripple_flag:
    .long 0

small_font_colour:
    .long 15

small_font_bg_word:
    .long 0x00000000        ; TODO: Remove masking code as bg fixed to colour 0.

; R10=colour no.
small_font_get_colour_data:
    ; Convert colour # to word.
    orr r10, r10, r10, lsl #4
    orr r10, r10, r10, lsl #8
    orr r10, r10, r10, lsl #16
    mov pc, lr    

; R0=ptr to string.
small_font_plot_string:
    stmfd sp!, {r3, lr}

    ; Set text cursor to home.
    ; TODO: Could remember cursor position.
    ldr r11, screen_addr

    ldr r10, small_font_colour
    bl small_font_get_colour_data

    mov r6, r0
.1:
    ldrb r0, [r6], #1
    cmp r0, #0                  ; EOS
    ldmeqfd sp!, {r3, pc}       ; rts

    cmp r0, #VDU_SetPos
    bne .2

    ; Set Pos - next two bytes are (column,line)
    ldrb r1, [r6], #1
    ldrb r2, [r6], #1

    ldr r11, screen_addr
    add r11, r11, r2, lsl #7    ; line * 128
    add r11, r11, r2, lsl #5    ; + line * 32 = line * 160
    add r11, r11, r1, lsl #2    ; column.
    b .1

    .2:
    cmp r0, #VDU_SetTextColour
    bne .3

    ; Set Text Colour - next byte is colour #.
    ldrb r10, [r6], #1
    str r10, small_font_colour

    ; Convert colour # to word.
    bl small_font_get_colour_data
    b .1

    .3:
    bl small_font_plot_glyph
    b .1

; R11=screen addr to plot at (updated).
; R10=colour data.
; R0=ASCII.
; Need to preserve R6.
small_font_plot_glyph:
	str lr, [sp, #-4]!			; push lr on stack

    bl small_font_map_ascii_to_glyph
    ; R1=glyph no.

    ; Bold option.
    ldr r4, small_font_bold_flag
    add r1, r1, r4

    ; Ripple hack.
    ldr r12, small_font_ripple_flag

    ; Bg colour.
    ldr r4, small_font_bg_word

    ; Assumes SmallFont_Height == 5
    ; TODO: Assert this?
    adr r9, small_font_data
    add r9, r9, r1, lsl #2      ; + glyph * 4
    add r9, r9, r1              ; + glyph = glyph * 5

    mov r8, r11
    mov r7, #SmallFont_Height
.1:
    ldrb r2, [r9], #1           ; r2 = glyph byte

    mov r3, #0

    ; convert glyph byte to 4bpp
    ; %abcdefgh
    tst r2, #0b00000001
    orrne r3, r3, #0xf0000000
    tst r2, #0b00000010
    orrne r3, r3, #0x0f000000
    tst r2, #0b00000100
    orrne r3, r3, #0x00f00000
    tst r2, #0b00001000
    orrne r3, r3, #0x000f0000
    tst r2, #0b00010000
    orrne r3, r3, #0x0000f000
    tst r2, #0b00100000
    orrne r3, r3, #0x00000f00
    tst r2, #0b01000000
    orrne r3, r3, #0x000000f0
    tst r2, #0b10000000
    orrne r3, r3, #0x0000000f

    ; TODO: Handle background that isn't black.
    bic r5, r4, r3                  ; clear glyph bits from bg word.
    and r3, r3, r10                 ; mask in colour / data.
    orr r3, r3, r5
    str r3, [r8], #Screen_Stride    ; next line.

        ; Ripple hack.
        cmp r12, #0
        beq .2
        and r10, r10, #0x0f
        add r10, r10, #1
        and r10, r10, #0x0f
        bl small_font_get_colour_data
        .2:

    subs r7, r7, #1
    bne .1

        ; Ripple hack.
        cmp r12, #0
        beq .3
        ldr r10, small_font_colour
        bl small_font_get_colour_data
        .3:

    add r11, r11, #4
	ldr pc, [sp], #4			; rts

; R0=ASCII.
; R1=glphy #.
small_font_map_ascii_to_glyph:
    mov r1, #SmallFont_Space    ; space is default glyph.

; Map ASCII to our non-ascii order.
; TODO: Seems like a lot of code, is there a simpler/shorter way?

    cmp r0, #ASCII_Space
    moveq pc,lr
    cmp r0, #ASCII_z
    movgt pc,lr
    cmp r0, #ASCII_ExclamationMark
    moveq r1, #SmallFont_ExclamationMark
    moveq pc, lr
    cmp r0, #ASCII_Colon
    moveq r1, #SmallFont_Colon
    moveq pc, lr
    cmp r0, #ASCII_Minus
    moveq r1, #SmallFont_Minus
    moveq pc, lr
    cmp r0, #ASCII_LessThan
    moveq r1, #SmallFont_LessThan
    moveq pc, lr
    cmp r0, #ASCII_MoreThan
    moveq r1, #SmallFont_MoreThan
    moveq pc, lr

    cmp r0, #ASCII_0
    blt .1
    cmp r0, #ASCII_9
    suble r1, r0, #ASCII_0 - SmallFont_0
    movle pc, lr

    .1:
    cmp r0, #ASCII_A
    blt .2
    cmp r0, #ASCII_Z
    suble r1, r0, #ASCII_A - SmallFont_a
    movle pc, lr

    .2:
    cmp r0, #ASCII_a
    movlt pc, lr
    cmp r0, #ASCII_z
    suble r1, r0, #ASCII_a - SmallFont_a
    mov pc, lr

.p2align 2
small_font_data:
.include "src/smallchars.asm"
