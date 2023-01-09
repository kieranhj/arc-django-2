; ============================================================================
; Menu stuff.
; ============================================================================

.equ MENU_SONG_XPOS, 3
.equ MENU_ARTIST_XPOS, 23
.equ MENU_TOP_YPOS, 114
.equ MENU_ROW_HEIGHT, 7
.equ MENU_COLOUR, 15

current_key:
	.long 0

held_key:
	.long 0

.if Mouse_Enable
prev_mouse_y:
	.long 0
.endif

selection_number:
	.long 0

selection_colour:
	.long 0

update_menu:
	str lr, [sp, #-4]!

	; check up
	mov r1, #RMKey_ArrowUp
	bl check_key_debounced
	bne .2

	ldr r3, selection_number
	cmp r3, #0
	beq .2
	.if _DJANGO==1
	bl plot_menu_item
	.endif
	sub r3, r3, #1
	str r3, selection_number
	
.2:
	; check down
	mov r1, #RMKey_ArrowDown
	bl check_key_debounced
	bne .3

	ldr r3, selection_number
	cmp r3, #MAX_SONGS
	bge .3
	.if _DJANGO==1
	bl plot_menu_item
	.endif
	add r3, r3, #1
	str r3, selection_number

.3:
	; Can't select new song if fade is active.
	ldr r0, volume_fade
	cmp r0, #0
	bne .5

	; check A for toggle autoplay
	mov r1, #RMKey_A
	bl check_key_debounced
	beq .10

	; check return
	mov r1, #RMKey_Return
	bl check_key_debounced
	beq .4

    ; and space
    mov r1, #RMKey_Space
    bl check_key_debounced
	beq .4

    .if Mouse_Enable
	mov r1, #RMKey_LeftClick
	bl check_key_debounced
    .endif
	bne .5

	; Select menu item.
	.4:
	ldr r3, song_number

	ldr r0, selection_number
	cmp r0, #MAX_SONGS
	blt .9

.10:
	; Toggle autplay.
	ldr r0, autoplay_flag
	eor r0, r0, #MAX_SONGS
	str r0, autoplay_flag

	mov r3, #MAX_SONGS
	.if _DJANGO==1
	bl plot_menu_item
	.endif
	b .5

	.9:
	; Don't restart current song as can be spammed.
	cmp r0, r3
	beq .5

	; Play song in R0.
	bl play_song
	.if _DJANGO==1
	bl plot_menu_item
	.endif

.5:

.if Mouse_Enable        ; NB. Not tested!
	; Check mouse.
	swi OS_Mouse
	ldr r0, prev_mouse_y
	str r1, prev_mouse_y
	subs r0, r0, r1
	; R0=mouse delta
    rsbmi r0, r0, #0
	cmp r0, #Mouse_Sensitivity
	blt .6

    ; Absolute Y.
	mov r0, #1023
    mov r2, #MAX_SONGS+1
	sub r1, r0, r1
    mul r2, r1, r2
    mov r2, r2, lsr #10

	ldr r3, selection_number
	cmp r2, r3
	beq .6
	.if _DJANGO==1
	bl plot_menu_item
	.endif

    ; Absolute Y.
	mov r0, #1023
    mov r3, #MAX_SONGS+1
	ldr r1, prev_mouse_y
	sub r1, r0, r1
    mul r3, r1, r3
    mov r3, r3, lsr #10
	str r3, selection_number
.endif

.6:
	.if _DJANGO==1
	bl plot_menu_selection
	.endif
	
	ldr pc, [sp], #4

plot_menu_selection:
	str lr, [sp, #-4]!

	; Update selected item.
    ldr r1, vsync_count
    and r1, r1, #1

	ldr r0, selection_colour
	add r0, r0, r1
	cmp r0, #15
	movgt r0, #0
	str r0, selection_colour
    str r0, small_font_colour
	mov r0, #SmallFont_BoldBase
	str r0, small_font_bold_flag
    str r0, small_font_ripple_flag
	ldr r3, selection_number
	bl plot_menu_item_ex
    mov r10, #MENU_COLOUR
    str r10, small_font_colour
    mov r10, #0
    str r10, small_font_ripple_flag

    .8:
	ldr pc, [sp], #4

keyboard_scan_debounced:
    swi RasterMan_ScanKeyboard
;	mov r0, #OSByte_KeyboardScan
;	mov r1, #1
;	swi OS_Byte

    mov r1, #0xff
    cmp r0, #0 
    beq .1

    and r2, r0, #0xf000
    cmp r2, #0xc000
    bne .1

    and r2, r0, #0x00f0
    cmp r2, #0x00c0
    bne .1

    ; 0xcLcH
    and r2, r0, #0x0f00
    mov r1, r2, lsr #8
    and r2, r0, #0x000f
    orr r1, r1, r2, lsl #4 

.1:
	; R1 contains key or 0xff if no key.
	mov r2, r1	; key pressed
	ldr r0, held_key
	cmp r1, r0
	moveq r2, #0xff
	str r1, held_key
	str r2, current_key
	mov pc, lr

; R1=IKey no. EOR 0xff
check_key_debounced:
;	eor r1, r1, #0xff
	ldr r0, current_key
	cmp r0, r1
	mov pc, lr

plot_menu:
	str lr, [sp, #-4]!
    mov r10, #MENU_COLOUR
    bl small_font_colour
	mov r3, #MAX_SONGS
	.1:
	bl plot_menu_item
	subs r3, r3, #1
	bpl .1
	ldr pc, [sp], #4

; R3=item # (preserved)
plot_menu_item:
	mov r0, #0
	ldr r1, song_number
	cmp r3, #MAX_SONGS		; autoplay hack.
	ldreq r1, autoplay_flag
	cmp r3, r1
	moveq r0, #SmallFont_BoldBase
	str r0, small_font_bold_flag
; Fall through!
plot_menu_item_ex:
	str lr, [sp, #-4]!
	adr r2, menu_table
	ldr r1, [r2, r3, lsl #2]	; r0 * 4
	add r0, r1, r2				; string address
	bl small_font_plot_string
    mov r0, #0
    str r0, small_font_bold_flag
	ldr pc, [sp], #4

.p2align 2
menu_table:
	.long menu_01_string - menu_table
	.long menu_02_string - menu_table
	.long menu_03_string - menu_table
	.long menu_04_string - menu_table
	.long menu_05_string - menu_table
	.long menu_06_string - menu_table
	.long menu_07_string - menu_table
	.long menu_08_string - menu_table
	.long menu_09_string - menu_table
	.long menu_10_string - menu_table
	.long menu_11_string - menu_table
	.long menu_12_string - menu_table

.p2align 2
menu_01_string:
	.byte 31, MENU_SONG_XPOS, MENU_TOP_YPOS, "SWITCHIN LANES", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS, "BY JUICE", 0

.p2align 2
menu_02_string:
	.byte 31, MENU_SONG_XPOS, MENU_TOP_YPOS+1*MENU_ROW_HEIGHT, "BRATGRUMBEERE", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+1*MENU_ROW_HEIGHT, "BY VIRGILL", 0

.p2align 2
menu_03_string:
	.byte 31, MENU_SONG_XPOS, MENU_TOP_YPOS+2*MENU_ROW_HEIGHT, "RED DROPS", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+2*MENU_ROW_HEIGHT, "BY OKEANOS", 0

.p2align 2
menu_04_string:
	.byte 31, MENU_SONG_XPOS, MENU_TOP_YPOS+3*MENU_ROW_HEIGHT, "AMIGA FUNERAL", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+3*MENU_ROW_HEIGHT, "BY VIRGILL", 0

.p2align 2
menu_05_string:
	.byte 31, MENU_SONG_XPOS, MENU_TOP_YPOS+4*MENU_ROW_HEIGHT, "A VIRAG ELSZARADT", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+4*MENU_ROW_HEIGHT, "BY DALEZY", 0

.p2align 2
menu_06_string:
	.byte 31, MENU_SONG_XPOS, MENU_TOP_YPOS+5*MENU_ROW_HEIGHT, "PAWS AND CLAWS", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+5*MENU_ROW_HEIGHT, "BY SLASH", 0

.p2align 2
menu_07_string:
	.byte 31, MENU_SONG_XPOS, MENU_TOP_YPOS+6*MENU_ROW_HEIGHT, "RESURGENCE", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+6*MENU_ROW_HEIGHT, "BY VEDDER", 0

.p2align 2
menu_08_string:
	.byte 31, MENU_SONG_XPOS, MENU_TOP_YPOS+7*MENU_ROW_HEIGHT, "QUICKSHOT DRAMAKING", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+7*MENU_ROW_HEIGHT, "BY CURT COOL", 0

.p2align 2
menu_09_string:
	.byte 31, MENU_SONG_XPOS, MENU_TOP_YPOS+8*MENU_ROW_HEIGHT, "SYNCOPATED GROOVE", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+8*MENU_ROW_HEIGHT, "BY OKEANOS", 0

.p2align 2
menu_10_string:
	.byte 31, MENU_SONG_XPOS, MENU_TOP_YPOS+9*MENU_ROW_HEIGHT, "PAULA AT THE DISCO", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+9*MENU_ROW_HEIGHT, "BY TRIACE", 0

.p2align 2
menu_11_string:
	.byte 31, MENU_SONG_XPOS, MENU_TOP_YPOS+10*MENU_ROW_HEIGHT, "CONCORDIA", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+10*MENU_ROW_HEIGHT, "BY MA2E", 0

.p2align 2
menu_12_string:
	.byte 31, 32, MENU_TOP_YPOS+11*MENU_ROW_HEIGHT, "AUTOPLAY", 0

.p2align 2
