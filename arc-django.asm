; ============================================================================
; arc-django-2 - An Archimedes port of Chipo Django 2 musicdisk by Rabenauge.
; ============================================================================

.equ _DEBUG, 1
.equ _DEBUG_RASTERS, (_DEBUG && _RASTERMAN==0 && 1)
.equ _DEBUG_SHOW, (_DEBUG && 0)

.equ _DJANGO, 2

.equ Sample_Speed, 48		; ideally 24us for ARM250+

.equ Screen_Banks, _DJANGO
.equ Screen_Mode, 9
.equ Screen_Width, 320
.equ Screen_Height, 256
.equ Mode_Height, 256
.equ Screen_PixelsPerByte, 2
.equ Screen_Stride, Screen_Width/Screen_PixelsPerByte
.equ Screen_Bytes, Screen_Stride*Screen_Height
.equ Mode_Bytes, Screen_Stride*Mode_Height

.include "lib/swis.h.asm"
.include "lib/config.h.asm"

; ============================================================================
; Macros.
; ============================================================================

.macro RND seed, bit, temp
    TST    \bit, \bit, LSR #1                       ; top bit into Carry
    MOVS   \temp, \seed, RRX                        ; 33 bit rotate right
    ADC    \bit, \bit, \bit                         ; carry into lsb of R1
    EOR    \temp, \temp, \seed, LSL #12             ; (involved!)
    EOR    \seed, \temp, \temp, LSR #20             ; (similarly involved!)
.endm

.macro SET_BORDER rgb
	.if _DEBUG_RASTERS
	mov r4, #\rgb
	bl palette_set_border
	.endif
.endm

; ============================================================================
; App defines
; ============================================================================

.equ MAX_SONGS, 11

.if _DEBUG
.equ Splash_Frames, 3
.equ Fade_Speed, 1
.else
.equ Splash_Frames, 3*50				; 3 seconds.
.equ Fade_Speed, 3
.endif
.equ Menu_Beat_Frames, 25				; 0.5 seconds.

.equ Glitch_Time, 12

.equ VU_Bars_Effect, 2					; 'effect'
.equ VU_Bars_Gravity, 2					; lines per vsync

.equ Mouse_Enable, 1
.equ Mouse_Sensitivity, 10

.equ AutoPlay_Default, MAX_SONGS
.equ Stereo_Positions, 1		; Amiga (full) stereo positions.

.equ KeyBit_Space, 0
.equ KeyBit_Return, 1
.equ KeyBit_ArrowUp, 2
.equ KeyBit_ArrowDown, 3
.equ KeyBit_A, 4
.equ KeyBit_LeftClick, 5

; ============================================================================
; Code Start
; ============================================================================

.org 0x8000

Start:
    ldr sp, stack_p
	B main

stack_p:
	.long stack_base_no_adr

; ============================================================================
; Main
; ============================================================================

main:
	; Set screen MODE & disable cursor
	adr r0, vdu_screen_disable_cursor
	mov r1, #12
	swi OS_WriteN

	; Set screen size for number of buffers
	MOV r0, #DynArea_Screen
	SWI OS_ReadDynamicArea
	MOV r0, #DynArea_Screen
	MOV r2, #Mode_Bytes * Screen_Banks
	SUBS r1, r2, r1
	SWI OS_ChangeDynamicArea
	MOV r0, #DynArea_Screen
	SWI OS_ReadDynamicArea
	CMP r1, #Mode_Bytes * Screen_Banks
	ADRCC r0, error_noscreenmem
	SWICC OS_GenerateError

	; Grab mouse.
	.if Mouse_Enable
	swi OS_Mouse
	str r1, prev_mouse_y
	.endif

	; Seed RND.
	swi OS_ReadMonotonicTime
	str r0, rnd_seed

	; EARLY INIT / LOAD STUFF HERE!
	bl new_font_init
	bl maths_init
	bl init_3d_scene

	; RasterMan Init.
	.if _RASTERMAN
	bl rasters_init
	.endif

	; QTM Init.
	; Required to make QTM play nicely with RasterMan.
	.if _RASTERMAN
	mov r0, #4
	mov r1, #-1
	mov r2, #-1
	swi QTM_SoundControl
	.endif

	mov r0, #8    ;set bit 3 of music options byte = QTM retains control of sound system after Pause/Stop/Clear
	mov r1, #8
	SWI QTM_MusicOptions

	mov r0, #VU_Bars_Effect
	mov r1, #VU_Bars_Gravity
	swi QTM_VUBarControl

	mov r0, #0
	mov r1, #Stereo_Positions
	swi QTM_Stereo

	mov r0, #Sample_Speed
	swi QTM_SetSampleSpeed

	; QTM callback.
	bl claim_music_interrupt

	; Clear all screen buffers
	mov r1, #1
.1:
	str r1, scr_bank

	; CLS bank N
	mov r0, #OSByte_WriteVDUBank
	swi OS_Byte
	mov r0, #12
	SWI OS_WriteC

	ldr r1, scr_bank
	add r1, r1, #1
	cmp r1, #Screen_Banks
	ble .1

	; Start with bank 1.
	mov r1, #1
	str r1, scr_bank

	; LATE INITALISATION HERE!
	bl get_screen_addr

	; Splash.
	.if _DJANGO==1
	adrl r2, rabenauge_pal_block
	bl palette_init_fade_to_black
	bl palette_set_block
	adr r0, rabenauge_splash
	ldr r1, screen_addr
	bl unlz4
	; Pause.
	mov r4, #Splash_Frames
	bl wait_frames
	; Fade.
	bl fade_out

	; Pause.
	mov r4, #Menu_Beat_Frames
	bl wait_frames

	; Menu Screen.
	mov r0, #12				; cls
	SWI OS_WriteC

	; Draw logo.
	ldr r12, screen_addr
	adrl r9, logo_data
	bl plot_logo

	; Draw menu to screen.
	ldr r12, screen_addr
	bl plot_menu
	.endif

	; Set palette (shows screen).
	adrl r2, logo_pal_block
	bl palette_set_block

	; Claim the Event vector.
	.if _RASTERMAN==0
	MOV r0, #EventV
	ADR r1, event_handler
	MOV r2, #0
	SWI OS_Claim
	.endif

	; Claim the Error vector.
	MOV r0, #ErrorV
	ADR r1, error_handler
	MOV r2, #0
	SWI OS_Claim

	; Start with song #0.
	mov r0, #0
	bl play_song

	; Fire up the RasterMan!
	.if _RASTERMAN
	swi RasterMan_Install
	.else
	; Enable Vsync
	mov r0, #OSByte_EventEnable
	mov r1, #Event_VSync
	SWI OS_Byte

	; Enable key pressed event.
	mov r0, #OSByte_EventEnable
	mov r1, #Event_KeyPressed
	SWI OS_Byte
	.endif

main_loop:

	; ========================================================================
	; TICK
	; ========================================================================

	SET_BORDER 0xffffff		; white = tick
	; do menu.
	ldr r0, keyboard_pressed_mask
	bl update_menu

	; autoplay!
	bl check_autoplay

	; tick modules
	bl update_columns
	bl scroller_update
	bl update_3d_scene
	SET_BORDER 0x000000

	; ========================================================================
	; VSYNC
	; ========================================================================

	; Block if we've not even had a vsync since last time - we're >50Hz!
	.if _RASTERMAN
	swi RasterMan_Wait
	mov r0, #1
	ldr r2, vsync_count
	add r2, r2, r0
	str r2, vsync_count
	.else
	ldr r1, last_vsync
.1:
	ldr r2, vsync_count
	cmp r1, r2
	beq .1
	sub r0, r2, r1
	str r2, last_vsync
	.endif

	; R0 = vsync delta since last frame.

	; ========================================================================
	; DRAW
	; ============b============================================================

	bl get_next_screen_for_writing

	SET_BORDER 0x00ff00		; green = screen clear
	ldr r12, screen_addr
	bl clear_left_screen

	SET_BORDER 0x00ffff		; yellow = columns
	ldr r12, screen_addr	
	bl plot_columns

	SET_BORDER 0xff00ff		; magenta = masked logo
	ldr r12, screen_addr
	bl plot_logo

	SET_BORDER 0xffff00		; cyan = masked scroller
	ldr r12, screen_addr
	bl scroller_draw

	SET_BORDER 0x0000ff		; red = plot cube
	ldr r12, screen_addr
	bl draw_3d_scene

	SET_BORDER 0xff0000		; blue = plot menu
	ldr r12, screen_addr
	bl plot_new_menu

	SET_BORDER 0x000000

	; show debug
	.if _DEBUG_SHOW
	bl debug_write_vsync_count
	.endif

	; Swap screens!
	bl show_screen_at_vsync

	; exit if Escape is pressed
	swi OS_ReadEscapeState
	bcs exit

	; repeat!
	b main_loop

exit:
	; wait for vsync (any pending buffers)
	bl release_music_interrupt

	; Fade out.
	.if _DJANGO==1 && _DEBUG==0
	adrl r2, logo_pal_block
	bl palette_init_fade_to_black
	bl fade_out_with_volume
	.endif

	mov r0, #8	;clear bit 3 of music options byte
	mov r1, #0
	swi QTM_MusicOptions

	; disable music
	mov r0, #0
	swi QTM_Clear

	; disable vsync event
	mov r0, #OSByte_EventDisable
	mov r1, #Event_VSync
	swi OS_Byte

	mov r0, #OSByte_EventDisable
	mov r1, #Event_KeyPressed
	swi OS_Byte

	; release our event handler
	mov r0, #EventV
	adr r1, event_handler
	mov r2, #0
	swi OS_Release

	; Release our error handler
	mov r0, #ErrorV
	adr r1, error_handler
	mov r2, #0
	swi OS_Release

	; Display whichever bank we've just written to
	mov r0, #OSByte_WriteDisplayBank
	ldr r1, scr_bank
	swi OS_Byte
	; and write to it
	mov r0, #OSByte_WriteVDUBank
	ldr r1, scr_bank
	swi OS_Byte

	; Flush keyboard buffer.
	mov r0, #15
	mov r1, #1
	swi OS_Byte

	SWI OS_Exit

.if _DJANGO==1
wait_frames:
	mov r0, #19
	swi OS_Byte
	subs r4, r4, #1
	bne wait_frames
	mov pc, lr

fade_out:
	str lr, [sp, #-4]!
	.1:
	mov r4, #Fade_Speed
	bl wait_frames
	bl palette_update_fade_to_black
	cmp r0, #0
	bne .1
	ldr pc, [sp], #4

fade_out_with_volume:
	str lr, [sp, #-4]!
	mov r7, #64
	.1:
	mov r4, #1
	bl wait_frames
	
	; Volume.
	mov r0, r7
	swi QTM_Volume

	; Palette.
    ldr r2, palette_source
	mov r0, r7, lsr #2
    bl palette_make_fade_to_black
    adr r2, palette_interp_block
    bl palette_set_block

	subs r7, r7, #1
	bne .1
	ldr pc, [sp], #4

fade_in:
	str lr, [sp, #-4]!
	.1:
	mov r4, #Fade_Speed
	bl wait_frames
	bl palette_update_fade_from_black
	cmp r0, #16
	bne .1
	ldr pc, [sp], #4
.endif

; ============================================================================
; Debug helpers.
; ============================================================================

.if _DEBUG
debug_print_r0:
	stmfd sp!, {r0-r2}
	adr r1, debug_string
	mov r2, #10
	swi OS_ConvertHex4	; or OS_ConvertHex8
	adr r0, debug_string
	swi OS_WriteO
	ldmfd sp!, {r0-r2}
	mov pc, lr

debug_write_vsync_count:
	str lr, [sp, #-4]!
	mov r0, #30	; home cursor
	swi OS_WriteC
	mov r0, #17	; set text colour
	swi OS_WriteC
	mov r0, #15
	swi OS_WriteC

    ; display current tracker position
    mov r0, #-1
    mov r1, #-1
    swi QTM_Pos

	mov r3, r1
	adr r1, debug_string
	mov r2, #8
	swi OS_ConvertHex2
	adr r0, debug_string
	swi OS_WriteO

	mov r0, r3
	adr r1, debug_string
	mov r2, #8
	swi OS_ConvertHex2
	adr r0, debug_string
	swi OS_WriteO

	; swi OS_NewLine
	swi OS_WriteI+32
	ldr r0, song_number
	bl debug_print_r0

	swi OS_WriteI+32
	ldr r0, autoplay_flag
	bl debug_print_r0

	swi OS_WriteI+32
	ldr r0, song_ended
	bl debug_print_r0

.if Mouse_Enable
	swi OS_WriteI+32
	ldr r0, prev_mouse_y
	bl debug_print_r0
.endif

	swi OS_WriteI+32
	ldr r0, keyboard_pressed_mask
	adr r1, debug_string
	mov r2, #8
	swi OS_ConvertHex4
	adr r0, debug_string
	swi OS_WriteO

.if 0
	; display frame count / frame rate etc.
	ldr r0, vsync_count	; vsync_delta
	adr r1, debug_string
	mov r2, #8
	swi OS_ConvertHex4

	adr r0, debug_string
	swi OS_WriteO
.endif
	ldr pc, [sp], #4

debug_string:
	.skip 10
.endif

; ============================================================================
; System stuff.
; ============================================================================

error_noscreenmem:
	.long 0
	.byte "Cannot allocate screen memory!"
	.p2align 2
	.long 0

get_screen_addr:
	str lr, [sp, #-4]!
	adrl r0, screen_addr_input
	adrl r1, screen_addr
	swi OS_ReadVduVariables
	ldr pc, [sp], #4
	
screen_addr_input:
	.long VD_ScreenStart, -1

; TODO: rename these to be clearer.
scr_bank:
	.long 0				; current VIDC screen bank being written to.

vsync_count:
	.long 0				; current vsync count from start of exe.

last_vsync:
	.long 0

keyboard_pressed_mask:
	.long 0

; R0=event number
event_handler:
	cmp r0, #Event_KeyPressed
	bne .1

	; R1=0 key up or 1 key down
	; R2=internal key number (RMKey_*)

	str r0, [sp, #-4]!

	ldr r0, keyboard_pressed_mask
	cmp r1, #0
	beq .2

	; Key down
	cmp r2, #RMKey_Space
	orreq r0, r0, #1<<KeyBit_Space
	cmp r2, #RMKey_Return
	orreq r0, r0, #1<<KeyBit_Return
	cmp r2, #RMKey_ArrowUp
	orreq r0, r0, #1<<KeyBit_ArrowUp
	cmp r2, #RMKey_ArrowDown
	orreq r0, r0, #1<<KeyBit_ArrowDown
	cmp r2, #RMKey_A
	orreq r0, r0, #1<<KeyBit_A
	cmp r2, #RMKey_LeftClick
	orreq r0, r0, #1<<KeyBit_LeftClick
	b .3

.2:
	; Key up
	cmp r2, #RMKey_Space
	biceq r0, r0, #1<<KeyBit_Space
	cmp r2, #RMKey_Return
	biceq r0, r0, #1<<KeyBit_Return
	cmp r2, #RMKey_ArrowUp
	biceq r0, r0, #1<<KeyBit_ArrowUp
	cmp r2, #RMKey_ArrowDown
	biceq r0, r0, #1<<KeyBit_ArrowDown
	cmp r2, #RMKey_A
	biceq r0, r0, #1<<KeyBit_A
	cmp r2, #RMKey_LeftClick
	biceq r0, r0, #1<<KeyBit_LeftClick

.3:
	str r0, keyboard_pressed_mask
	ldr r0, [sp], #4
	mov pc, lr

.1:
	cmp r0, #Event_VSync
	movnes pc, r14

	str r0, [sp, #-4]!

	; update the vsync counter
	LDR r0, vsync_count
	ADD r0, r0, #1
	STR r0, vsync_count

	ldr r0, [sp], #4
	mov pc, lr

show_screen_at_vsync:
	; Show current bank at next vsync
	ldr r1, scr_bank
	MOV r0, #OSByte_WriteDisplayBank
	swi OS_Byte

	ldr r1, vsync_count
	str r1, last_vsync	; we have to wait for the next one.
	mov pc, lr

get_next_screen_for_writing:
	; Increment to next bank for writing
	ldr r1, scr_bank
	add r1, r1, #1
	cmp r1, #Screen_Banks
	movgt r1, #1
	str r1, scr_bank

	; Now set the screen bank to write to
	mov r0, #OSByte_WriteVDUBank
	swi OS_Byte

	; Back buffer address for writing bank stored at screen_addr
	b get_screen_addr

error_handler:
	STMDB sp!, {r0-r2, lr}

	; Release event handler.
	MOV r0, #OSByte_EventDisable
	MOV r1, #Event_VSync
	SWI OS_Byte
	MOV r0, #EventV
	ADR r1, event_handler
	mov r2, #0
	SWI OS_Release

	; Release error handler.
	MOV r0, #ErrorV
	ADR r1, error_handler
	MOV r2, #0
	SWI OS_Release

	; Write & display current screen bank.
	MOV r0, #OSByte_WriteDisplayBank
	LDR r1, scr_bank
	SWI OS_Byte

	; Do these help?
	swi QTM_Stop

	LDMIA sp!, {r0-r2, lr}
	MOVS pc, lr

; ============================================================================
; Play the music!
; ============================================================================

glitch_timer:
	.long 0

song_number:
	.long -1

autoplay_flag:
	.long AutoPlay_Default		; set to MAX_SONGS when enabled.

song_ended:
	.long 0

prev_music_interrupt:
	.long 0

prev_interrupt_sp:
	.long 0

volume_fade:
	.long 0

play_song:
	swi QTM_Stop

	; Unload the current module.
	mov r1, r0
	mov r0, #-1
	swi QTM_Clear
	mov r0, r1

	; Load module.
	str r0, song_number
	adr r2, music_table
	ldr r1, [r2, r0, lsl #2]	; r0 * 4
	mov r0, #0					; load from address
	swi QTM_Load

	mov r0, #64					; max volume
	swi QTM_Volume

	; Play music!
	swi QTM_Start

	mov r0, #Glitch_Time
	str r0, glitch_timer
	mov pc, lr

check_autoplay:
	ldr r0, volume_fade
	cmp r0, #0
	bne .1

	ldr r1, song_ended
	cmp r1, #0
	moveq pc, lr
	str r0, song_ended

	ldr r0, autoplay_flag
	cmp r0, #0
	moveq pc, lr

	mov r0, #64
	str r0, volume_fade
	mov pc, lr

.1:
	subs r0, r0, #1
	str r0, volume_fade
	beq .2

	swi QTM_Volume
	mov pc, lr

.2:
	str lr, [sp, #-4]!
	ldr r0, song_number
	mov r3, r0
	add r0, r0, #1
	cmp r0, #MAX_SONGS
	movge, r0, #0
	bl play_song

	ldr pc, [sp], #4

claim_music_interrupt:
	mov r0, #2
	mov r1, #2
	swi QTM_MusicOptions

	mov r0, #0
	adr r1, music_interrupt
	mov r2, #0
	swi QTM_MusicInterrupt
	str r1, prev_music_interrupt
	str r2, prev_interrupt_sp
	mov pc, lr

release_music_interrupt:
	mov r0, #0
	ldr r1, prev_music_interrupt
	ldr r2, prev_interrupt_sp
	swi QTM_MusicInterrupt
	mov pc, lr

music_interrupt:
	cmp r0, #MusicInterrupt_SongEnded
	movnes pc, lr
	str r1, song_ended
	movs pc, lr

; ============================================================================
; Additional code modules
; ============================================================================

rnd_seed:
    .long 0x87654321

screen_addr:
	.long 0					; ptr to the current VIDC screen bank being written to.

.include "lib/mode9-palette.asm"
.include "src/menu.asm"
.include "src/new-font.asm"
.include "src/columns.asm"
.include "src/scroller.asm"
.include "src/logo.asm"
.include "lib/lz4-decode.asm"
.include "lib/maths.asm"
.include "src/3d-scene.asm"

; ============================================================================
; Data Segment
; ============================================================================

vdu_screen_disable_cursor:
.byte 22, Screen_Mode, 23,1,0,0,0,0,0,0,0,0
.p2align 2

music_table:
	.long music_01_mod_no_adr
	.long music_02_mod_no_adr
	.long music_03_mod_no_adr
	.long music_04_mod_no_adr
	.long music_05_mod_no_adr
	.long music_06_mod_no_adr
	.long music_07_mod_no_adr
	.long music_08_mod_no_adr
	.long music_09_mod_no_adr
	.long music_10_mod_no_adr
	.long music_11_mod_no_adr

.p2align 2
logo_pal_block:
.incbin "data/logo-palette-hacked.bin"

; ============================================================================
; DATA Segment
; ============================================================================

.include "src/data.asm"

; ============================================================================
; BSS Segment
; ============================================================================

.include "src/bss.asm"
