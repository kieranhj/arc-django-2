; ============================================================================
; Columns
; ============================================================================

.equ Columns_Num, 5
.equ Columns_Tooth, 16      ; pixels

.macro FLOAT_TO_FP value
    .long 1<<16 * (\value)
.endm

column_y_offset:
    .skip Columns_Num * 4

column_y_speed:
    FLOAT_TO_FP 0.25
    FLOAT_TO_FP 0.5
    FLOAT_TO_FP 1
    FLOAT_TO_FP 1.5
    FLOAT_TO_FP 2

column_colours:
    .long 0xbbbbbbbb
    .long 0xcccccccc
    .long 0xdddddddd
    .long 0xeeeeeeee
    .long 0xffffffff

; R11=screen plot pointer
; R10=y offset
; R9=colour word
; R8=narrow flag
; Trashes: r5-r8
plot_column:
    ; Copy colour word.
    mov r7, r9
    mov r6, r9

    mov r5, #0              ; line loop.
.1:
    ; assumes 'tooth' size is 16 pixels
    movs r0, r10, lsr #16+5     ; parity in C

    ; if carry set draw tooth
    stmcsia r11, {r6-r7}    ; plot 16 pixels
    add r11, r11, #8        ; skip 16 pixels
    
    stmia r11!, {r6-r7}     ; plot 16 pixels

    cmp r8, #0
    stmeqia r11, {r6-r7}    ; plot 16 pixels

    add r11, r11, #Screen_Stride-16

    add r10, r10, #1<<16    ; next y offset
    add r5, r5, #1          ; next line
    cmp r5, #256
    blt .1

    mov pc, lr

; R12=screen addr
plot_columns:
    str lr, [sp, #-4]!

    mov r8, #0

    ; Start in the middle.
    add r11, r12, #Screen_Stride/2 + 0
    ldr r10, column_y_offset + 0
    ldr r9, column_colours + 0
    bl plot_column

    add r11, r12, #Screen_Stride/2 + 16
    ldr r10, column_y_offset + 4
    ldr r9, column_colours + 4
    bl plot_column

    add r11, r12, #Screen_Stride/2 + 32
    ldr r10, column_y_offset + 8
    ldr r9, column_colours + 8
    bl plot_column

    add r11, r12, #Screen_Stride/2 + 48
    ldr r10, column_y_offset + 12
    ldr r9, column_colours + 12
    bl plot_column

    add r11, r12, #Screen_Stride/2 + 64
    ldr r10, column_y_offset + 16
    ldr r9, column_colours + 16
    mov r8, #1  ; narrow
    bl plot_column

    ldr pc, [sp], #4

update_columns:

    adr r9, column_y_offset
    adr r8, column_y_speed
    mov r7, #5
.1:
    ldr r0, [r9]
    ldr r1, [r8], #4
    add r0, r0, r1
    bic r0, r0, #0xff000000 ; assume 256
    str r0, [r9], #4
    subs r7, r7, #1
    bne .1

    mov pc, lr

; R12=screen addr
clear_left_screen:
    mov r0, #0
    mov r1, r0
    mov r2, r0
    mov r3, r0
    mov r4, r0
    mov r5, r0
    mov r6, r0
    mov r7, r0
    mov r8, r0
    mov r9, r0

    add r11, r12, #Screen_Bytes
.1:
    stmia r12!, {r0-r9}     ; 80 pixels
    stmia r12!, {r0-r9}     ; 80 pixels
    stmia r12, {r0-r1}      ; 16 pixels
    add r12, r12, #Screen_Stride/2
    cmp r12, r11
    blt .1

    mov pc, lr
