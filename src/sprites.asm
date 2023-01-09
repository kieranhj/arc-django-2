; Sprites.
; Simple MODE 9 masked sprites with pixel plotting.
; Assume colour 0 is transparent.

.equ Sprite_Width, 16
.equ Sprite_Height, 16
.equ Sprites_Num, 6

.equ Sprite_X_Pos, 0
.equ Sprite_Data_Ptr, 8
.equ Sprite_Block_Size, 8

.equ Note_X_Gap, 64
.equ Note_X_Start, Screen_Width + Note_X_Gap
.equ Note_Left_Edge, -Sprite_Width
.equ Note_Right_Edge, Screen_Width - Sprite_Width + Note_X_Gap
.equ Note_Y_Adjust, 42
.equ Notes_Max_Sprites, 5
.equ Note_Sprite_Bytes, 128

; Returns rand in R0, preserves R1, R2.
rand_slow:
    stmfd sp!, {r1-r2}
    ldr r0, rnd_seed
    mov r1, #1              ; need a spare bit!
    RND R0, R1, R2
    str r0, rnd_seed
    ldmfd sp!, {r1-r2}
    mov pc, lr

update_sprites:
	str lr, [sp, #-4]!
    ldr r12, screen_addr

    adr r11, sprite_blocks
    adr r9, sinus

    mov r10, #0
.1:
    ; Load sprite block: R0=X, R1=Y, R2=Data ptr.
    ldmia r11, {r0,r2}

    ; Move sprite left.
    sub r0, r0, #1
    cmp r0, #Note_Left_Edge
    bgt .2

    ; New sprite!
    .3:
    bl rand_slow
    and r0, r0, #7
    cmp r0, #Notes_Max_Sprites
    bge .3

    mov r2, r0, lsl #7          ; 128 bytes per note.

    ; Start on the RHS.
    mov r0, #Note_Right_Edge

    .2:
    ; Calculate Y pos on sinewave.
    add r3, r0, r10, lsl #4
    and r3, r3, #0x3f
    ldr r1, [r9, r3, lsl #2]
    sub r1, r1, #Note_Y_Adjust
    stmia r11!, {r0,r2}

    stmfd sp!, {r9-r11}
    bl plot_sprite
    ldmfd sp!, {r9-r11}

    add r10, r10, #1
    cmp r10, #Sprites_Num
    bne .1

	ldr pc, [sp], #4


; R0=X, R1=Y, R2=data offset, R12=screen addr
plot_sprite:
	str lr, [sp, #-4]!

    ; Offset from sprite base.
    adr r3, note_sprite_data
    add r2, r2, r3

    ; Calculate pixel offset.
    and r3, r0, #7          ; 8 pixels per word.
    bic r0, r0, #7          ; clamp X pos to word.

    ; Calculate screen plot address.
    add r9, r12, r1, lsl #7 ; 128 * y
    add r9, r9, r1, lsl #5  ; + 32 * y = 160 * y
    add r9, r9, r0, asr #1  ; + x / 2

    ; Pixel offset shift.
    mov r10, r3, lsl #2     ; pixel shift (4*n)
    rsb r11, r10, #32       ; reverse pixel shift (32-4*n)

    ; For each line.
    mov r14, r0
    mov r8, r2
    mov r7, #0 
    .1:

    ; ASSUME: Sprite_Width==16 (assert this?)
    ldmia r8!, {r0-r1}        ; read 16 pixels.
    ; Shift right by N pixels
    ; Screen: 01234567 Word: 76543210
    ; Copy right-most pixels into R2.
    mov r2, r1, lsr r11
    mov r1, r1, lsl r10
    orr r1, r1, r0, lsr r11
    mov r0, r0, lsl r10

    ldmia r9, {r4-r6}

    ; Compute mask.
    mov r3, #0
    tst r0, #0x0000000f
    orrne r3, r3, #0x0000000f
    tst r0, #0x000000f0
    orrne r3, r3, #0x000000f0
    tst r0, #0x00000f00
    orrne r3, r3, #0x00000f00
    tst r0, #0x0000f000
    orrne r3, r3, #0x0000f000
    tst r0, #0x000f0000
    orrne r3, r3, #0x000f0000
    tst r0, #0x00f00000
    orrne r3, r3, #0x00f00000
    tst r0, #0x0f000000
    orrne r3, r3, #0x0f000000
    tst r0, #0xf0000000
    orrne r3, r3, #0xf0000000

    ; Mask out screen bits, mask in sprite bits.    
    bic r4, r4, r3
    orr r4, r4, r0

    ; Compute mask.
    mov r3, #0
    tst r1, #0x0000000f
    orrne r3, r3, #0x0000000f
    tst r1, #0x000000f0
    orrne r3, r3, #0x000000f0
    tst r1, #0x00000f00
    orrne r3, r3, #0x00000f00
    tst r1, #0x0000f000
    orrne r3, r3, #0x0000f000
    tst r1, #0x000f0000
    orrne r3, r3, #0x000f0000
    tst r1, #0x00f00000
    orrne r3, r3, #0x00f00000
    tst r1, #0x0f000000
    orrne r3, r3, #0x0f000000
    tst r1, #0xf0000000
    orrne r3, r3, #0xf0000000

    ; Mask out screen bits, mask in sprite bits.    
    bic r5, r5, r3
    orr r5, r5, r1

    ; Compute mask.
    mov r3, #0
    tst r2, #0x0000000f
    orrne r3, r3, #0x0000000f
    tst r2, #0x000000f0
    orrne r3, r3, #0x000000f0
    tst r2, #0x00000f00
    orrne r3, r3, #0x00000f00
    tst r2, #0x0000f000
    orrne r3, r3, #0x0000f000
    tst r2, #0x000f0000
    orrne r3, r3, #0x000f0000
    tst r2, #0x00f00000
    orrne r3, r3, #0x00f00000
    tst r2, #0x0f000000
    orrne r3, r3, #0x0f000000
    tst r2, #0xf0000000
    orrne r3, r3, #0xf0000000

    ; Mask out screen bits, mask in sprite bits.    
    bic r6, r6, r3
    orr r6, r6, r2

;   No sprite clipping.
;   stmia r9, {r4-r6}
;   add r9, r9, #Screen_Stride

    ; Super shit sprite clipping but we don't care as only plotting 5x small sprites.
    cmp r14, #0
    blt .2
    cmp r14, #Screen_Width
    bge .2
    str r4, [r9]
    
    ; Skip word 0.
    .2:
    add r9, r9, #4
    add r14, r14, #8

    cmp r14, #0
    blt .3
    cmp r14, #Screen_Width
    bge .3
    str r5, [r9]
    
    ; Skip word 1.
    .3:
    add r9, r9, #4
    add r14, r14, #8

    cmp r14, #0
    blt .4
    cmp r14, #Screen_Width
    bge .4
    str r6, [r9]

    ; Skip word 2.
    .4:
    add r9, r9, #Screen_Stride - 8
    sub r14, r14, #16

    add r7, r7, #1
    cmp r7, #Sprite_Height
    blt .1

	ldr pc, [sp], #4

sprite_blocks:
    .long Note_X_Start + 0*Note_X_Gap, 0*Note_Sprite_Bytes
    .long Note_X_Start + 1*Note_X_Gap, 1*Note_Sprite_Bytes
    .long Note_X_Start + 2*Note_X_Gap, 2*Note_Sprite_Bytes
    .long Note_X_Start + 3*Note_X_Gap, 3*Note_Sprite_Bytes
    .long Note_X_Start + 4*Note_X_Gap, 4*Note_Sprite_Bytes
    .long Note_X_Start + 5*Note_X_Gap, 2*Note_Sprite_Bytes

sinus:
    ; Could turn these into bytes but we 1/4'd the table anyway.
     .long 0xfe,0xfe,0xff,0xff,0x100,0x100,0x101,0x101,0x101,0x101,0x102,0x102,0x102,0x102,0x102,0x102
     .long 0x102,0x102,0x102,0x102,0x102,0x102,0x102,0x101,0x101,0x101,0x100,0x100,0x100,0xff,0xff,0xfe
     .long 0xfe,0xfe,0xfd,0xfd,0xfc,0xfc,0xfb,0xfb,0xfb,0xfa,0xfa,0xfa,0xfa,0xfa,0xfa,0xfa
     .long 0xfa,0xfa,0xfa,0xfa,0xfa,0xfa,0xfa,0xfb,0xfb,0xfb,0xfc,0xfc,0xfc,0xfd,0xfd,0xfe
