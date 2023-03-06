; ============================================================================
; Menu stuff.
; ============================================================================

.equ MENU_SONG_XPOS, 0
.equ MENU_ARTIST_XPOS, 26
.equ MENU_TOP_YPOS, 100
.equ MENU_ROW_HEIGHT, 7
.equ MENU_ITEM_COLOUR, 10
.equ MENU_PLAYING_COLOUR, 15

.if Mouse_Enable
prev_mouse_y:
	.long 0
.endif

selection_number:
	.long 0

selection_colour:
	.long 0

keyboard_prev_mask:
	.long 0

; R0=keyboard pressed mask
update_menu:
	str lr, [sp, #-4]!

	ldr r2, keyboard_prev_mask
	mvn r2, r2				; ~old
	and r2, r0, r2			; new & ~old		; diff bits
	str r0, keyboard_prev_mask
	and r4, r2, r0			; diff bits & key down bits	

	; Update selected item colour.
    ldr r1, vsync_count
    and r1, r1, #1

	ldr r0, selection_colour
	add r0, r0, r1
	cmp r0, #15
	movgt r0, #0
	str r0, selection_colour

	; check up
	tst r4, #1<<KeyBit_ArrowUp	; key changed & down?
	beq .2

	ldr r3, selection_number
	cmp r3, #0
	beq .2
	sub r3, r3, #1
	str r3, selection_number
	
.2:
	; check down
	tst r4, #1<<KeyBit_ArrowDown	; key changed & down?
	beq .3

	ldr r3, selection_number
	cmp r3, #MAX_SONGS
	bge .3
	add r3, r3, #1
	str r3, selection_number

.3:
	; Can't select new song if fade is active.
	ldr r0, volume_fade
	cmp r0, #0
	bne .5

	tst r4, #1<<KeyBit_A	; key changed & down?
	bne .10

	; check return & space
    .if Mouse_Enable
	tst r4, #1<<KeyBit_Return|1<<KeyBit_Space|1<<KeyBit_LeftClick	; key changed & down?
    .else
	tst r4, #1<<KeyBit_Return|1<<KeyBit_Space	; key changed & down?
	.endif
	beq .5

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

	; Update autoplay string.
	adr r1, menu_autoplay_off_string
	adr r2, menu_autoplay_on_string
	cmp r0, #0
	movne r1, r2
	str r1, menu_item_autoplay

	mov r3, #MAX_SONGS
	b .5

	.9:
	; Don't restart current song as can be spammed.
	cmp r0, r3
	beq .5

	; Play song in R0.
	bl play_song

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
	ldr pc, [sp], #4


; R12=screen addr.
plot_new_menu:
	str lr, [sp, #-4]!

	mov r5, #0
	adr r2, menu_table
	ldr r7, selection_number
	ldr r8, song_number
.1:
	; set colour word.
	mov r10, #MENU_ITEM_COLOUR

	; song_number = what's playing
	cmp r5, r8
	moveq r10, #MENU_PLAYING_COLOUR

	; selection_number = what's flashing
	cmp r5, r7
	ldreq r10, selection_colour

	orr r10, r10, r10, lsl #4
	orr r10, r10, r10, lsl #8
	orr r10, r10, r10, lsl #16

	ldr r0, [r2], #4
	bl new_font_plot_string

	add r5, r5, #1
	cmp r5, #MAX_SONGS
	ble .1

	ldr pc, [sp], #4	

; ============================================================================

.p2align 2
menu_table:
	.long menu_01_string
	.long menu_02_string
	.long menu_03_string
	.long menu_04_string
	.long menu_05_string
	.long menu_06_string
	.long menu_07_string
	.long menu_08_string
	.long menu_09_string
	.long menu_10_string
	.long menu_11_string
menu_item_autoplay:
	.long menu_autoplay_on_string

; ============================================================================

.p2align 2
menu_01_string:
	.byte 31, MENU_SONG_XPOS, MENU_TOP_YPOS, "birdhouse in da houz3", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS, "slime", 0

.p2align 2
menu_02_string:
	.byte 31, MENU_SONG_XPOS+9, MENU_TOP_YPOS+1*MENU_ROW_HEIGHT, "autumn mood", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+1*MENU_ROW_HEIGHT, "triace", 0

.p2align 2
menu_03_string:
	.byte 31, MENU_SONG_XPOS+6, MENU_TOP_YPOS+2*MENU_ROW_HEIGHT, "square circles", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+2*MENU_ROW_HEIGHT, "ne7", 0

.p2align 2
menu_04_string:
	.byte 31, MENU_SONG_XPOS+11, MENU_TOP_YPOS+3*MENU_ROW_HEIGHT, "je suis k", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+3*MENU_ROW_HEIGHT, "okeanos", 0

.p2align 2
menu_05_string:
	.byte 31, MENU_SONG_XPOS+2, MENU_TOP_YPOS+4*MENU_ROW_HEIGHT, "la soupe aux choux", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+4*MENU_ROW_HEIGHT, "okeanos", 0

.p2align 2
menu_06_string:
	.byte 31, MENU_SONG_XPOS+12, MENU_TOP_YPOS+5*MENU_ROW_HEIGHT, "booaxian", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+5*MENU_ROW_HEIGHT, "slash", 0

.p2align 2
menu_07_string:
	.byte 31, MENU_SONG_XPOS+16, MENU_TOP_YPOS+6*MENU_ROW_HEIGHT, "sajt", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+6*MENU_ROW_HEIGHT, "dalezy", 0

.p2align 2
menu_08_string:
	.byte 31, MENU_SONG_XPOS+12, MENU_TOP_YPOS+7*MENU_ROW_HEIGHT, "holodash", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+7*MENU_ROW_HEIGHT, "virgill", 0

.p2align 2
menu_09_string:
	.byte 31, MENU_SONG_XPOS+10, MENU_TOP_YPOS+8*MENU_ROW_HEIGHT, "squid ring", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+8*MENU_ROW_HEIGHT, "curt cool", 0

.p2align 2
menu_10_string:
	.byte 31, MENU_SONG_XPOS+16, MENU_TOP_YPOS+9*MENU_ROW_HEIGHT, "lies", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+9*MENU_ROW_HEIGHT, "punnik", 0

.p2align 2
menu_11_string:
	.byte 31, MENU_SONG_XPOS+15, MENU_TOP_YPOS+10*MENU_ROW_HEIGHT, "dummy", 31, MENU_ARTIST_XPOS, MENU_TOP_YPOS+10*MENU_ROW_HEIGHT, "lord", 0

.p2align 2
menu_autoplay_on_string:
	.byte 31, 0, MENU_TOP_YPOS+11*MENU_ROW_HEIGHT, "autoplay on", 0

.p2align 2
menu_autoplay_off_string:
	.byte 31, 0, MENU_TOP_YPOS+11*MENU_ROW_HEIGHT, "autoplay off", 0

.p2align 2
; ============================================================================
