; Logo plotting.

.equ Logo_Width, 320
.equ Logo_Height, 84
.equ Logo_Gap, Screen_Stride-Logo_Width/Screen_PixelsPerByte

logo_data_p:
    .long logo_data_no_adr

logo_mask_p:
    .long logo_mask_no_adr

; R9=logo_addr, R12=screen_addr
; Assume plotting at top of the screen.
plot_logo:
	ldr r9, logo_data_p
    ldr r8, logo_mask_p
    mov r10, #Logo_Height
    mov r11, r12

    .1:
.rept Logo_Width/32
    ldmia r11, {r0-r3}      ; 4 words of screen.
    ldmia r8!, {r4-r7}      ; 4 words of mask.
    bic r0, r0, r4
    bic r1, r1, r5
    bic r2, r2, r6
    bic r3, r3, r7
    ldmia r9!, {r4-r7}      ; 4 words of logo.
    orr r0, r0, r4
    orr r1, r1, r5
    orr r2, r2, r6
    orr r3, r3, r7
    stmia r11!, {r0-r3}     ; 4 words of screen.
.endr

    add r11, r11, #Logo_Gap
    subs r10, r10, #1
    bne .1

    mov pc, lr

.macro logo_shift_right_by_pixels
    mov r8, r8, lsl r10
    orr r8, r8, r7, lsr r11
    mov r7, r7, lsl r10
    orr r7, r7, r6, lsr r11
    mov r6, r6, lsl r10
    orr r6, r6, r5, lsr r11
    mov r5, r5, lsl r10
    orr r5, r5, r4, lsr r11
    mov r4, r4, lsl r10
    orr r4, r4, r3, lsr r11
    mov r3, r3, lsl r10
    orr r3, r3, r2, lsr r11
    mov r2, r2, lsl r10
    orr r2, r2, r1, lsr r11
    mov r1, r1, lsl r10
    orr r1, r1, r0, lsr r11
.endm

; R9=logo_addr, R12=screen_addr
; Assume plotting at top of the screen.
plot_logo_glitched:
    str lr, [sp, #-4]!
    mov r14, #Logo_Height

    .1:
    ldr r0, rnd_seed
    mov r1, #1              ; need a spare bit!
    RND R0, R1, R2
    str r0, rnd_seed

    ; Pixel offset shift.
    and r0, r0, #0x03
    mov r10, r0, lsl #2     ; pixel shift (4*n)
    rsb r11, r10, #32       ; reverse pixel shift (32-4*n)

    add r9, r9, #124        ; 4th chunk.
    add r12, r12, #128      ; 4th chunk.
    ldmia r9, {r0-r8}       ; 9 words = 68 pixels.
    logo_shift_right_by_pixels
    stmia r12, {r1-r8}      ; 8 words = 64 pixels.

    sub r9, r9, #32         ; 3rd chunk.
    sub r12, r12, #32       ; 3rd chunk.
    ldmia r9, {r0-r8}       ; 9 words = 68 pixels.
    logo_shift_right_by_pixels
    stmia r12, {r1-r8}      ; 8 words = 64 pixels.

    sub r9, r9, #32         ; 2nd chunk.
    sub r12, r12, #32       ; 2nd chunk.
    ldmia r9, {r0-r8}       ; 9 words = 68 pixels.
    logo_shift_right_by_pixels
    stmia r12, {r1-r8}      ; 8 words = 64 pixels.

    sub r9, r9, #32         ; 1st chunk.
    sub r12, r12, #32       ; 1st chunk.
    ldmia r9, {r0-r8}       ; 9 words = 68 pixels.
    logo_shift_right_by_pixels
    stmia r12, {r1-r8}      ; 8 words = 64 pixels.

    sub r9, r9, #28         ; 0th chunk.
    sub r12, r12, #32       ; 0th chunk.
    mov r0, #0
    ldmia r9, {r1-r8}       ; 9 words = 68 pixels.
    logo_shift_right_by_pixels
    stmia r12, {r1-r8}      ; 8 words = 64 pixels.

    add r9, r9, #Screen_Stride
    add r12, r12, #Screen_Stride

    subs r14, r14, #1
    bne .1

	ldr pc, [sp], #4
