; ============================================================================
; arc-django-2 - An Archimedes port of Chipo Django 2 musicdisk by Rabenauge.
; ============================================================================

.equ _DEBUG, 1
.equ _DEBUG_RASTERS, (_DEBUG && _RASTERMAN==0 && 1)

.equ _DJANGO, 2
.equ _RASTERMAN, 0
.equ _USE_MODE9_FONT, 1	; convert font to MODE 9 at runtime.

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

.equ VU_Bars_Effect, 2	; 'effect'
.equ VU_Bars_Gravity, 2	; lines per vsync

.equ Mouse_Enable, 1
.equ Mouse_Sensitivity, 10

.equ AutoPlay_Default, MAX_SONGS
.equ Stereo_Positions, 1		; Amiga (full) stereo positions.

; ============================================================================
; Code Start
; ============================================================================

.org 0x8000

Start:
    ldr sp, stack_p
	B main

stack_p:
	.long stack_base

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
	.if _USE_MODE9_FONT
	bl mode9_font_init
	.endif

	; RasterMan Init.
	.if _RASTERMAN
	bl rasters_init
	.endif

	; QTM Init.
	; Required to make QTM play nicely with RasterMan.
	mov r0, #4
	mov r1, #-1
	mov r2, #-1
	swi QTM_SoundControl

	mov r0, #8    ;set bit 3 of music options byte = QTM retains control of sound system after Pause/Stop/Clear
	mov r1, #8
	SWI QTM_MusicOptions

	mov r0, #VU_Bars_Effect
	mov r1, #VU_Bars_Gravity
	swi QTM_VUBarControl

	mov r0, #0
	mov r1, #Stereo_Positions
	swi QTM_Stereo

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
	.endif

	; Draw menu to screen.
	ldr r12, screen_addr
	bl plot_menu

	.if _DJANGO==1
	bl scroller_init
	.endif

	; Set palette (shows screen).
	adrl r2, logo_pal_block
	bl palette_set_block

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
	.endif

main_loop:

	; ========================================================================
	; TICK
	; ========================================================================

	; do menu.
	bl keyboard_scan_debounced
	bl update_menu

	; autoplay!
	bl check_autoplay

	; ========================================================================
	; VSYNC
	; ========================================================================

	; Block if we've not even had a vsync since last time - we're >50Hz!
	.if _RASTERMAN
	swi RasterMan_Wait
	.else
	mov r0, #19
	swi OS_Byte
	.endif

	mov r0, #1
	ldr r2, vsync_count
	add r2, r2, r0
	str r2, vsync_count
	; R0 = vsync delta since last frame.

	; ========================================================================
	; DRAW
	; ========================================================================

	bl get_next_screen_for_writing

	SET_BORDER 0x00ff00
	ldr r12, screen_addr
    bl clear_left_screen

	ldr r12, screen_addr
	bl plot_columns
	
	bl update_columns
	SET_BORDER 0x000000

	SET_BORDER 0xff0000
	bl plot_menu
	bl plot_menu_selection
	SET_BORDER 0x000000

	.if _DJANGO==1
	; scroll the bottom.
	bl scroller_update

	; do VU bars.
	bl update_vu_bars

	; do glitch.
	ldr r0, glitch_timer
	cmp r0, #0
	beq .8

	subs r0, r0, #1
	str r0, glitch_timer

	ldr r12, screen_addr
	adrl r9, logo_data
	bleq plot_logo
	blne plot_logo_glitched
	.8:

	SET_BORDER 0x00ff00
	bl update_sprites
	SET_BORDER 0x000000
	.endif

	; show debug
	.if _DEBUG
	bl debug_write_vsync_count
	.endif

	; Swap screens!
	bl show_screen_at_vsync

	; exit if Escape is pressed
	.if _RASTERMAN
	swi RasterMan_ScanKeyboard
	mov r1, #0xc0c0
	cmp r0, r1
	beq exit
	.else
	swi OS_ReadEscapeState
	bcs exit
	.endif

	; repeat!
	b main_loop

exit:
	; wait for vsync (any pending buffers)
	.if _RASTERMAN
	swi RasterMan_Wait
	.endif

	bl release_music_interrupt

	.if _RASTERMAN
	swi RasterMan_Release
	swi RasterMan_Wait
	.endif

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

	; Release our error handler
	mov r0, #ErrorV
	adr r1, error_handler
	mov r2, #0
	swi OS_Release

	.if _DJANGO==1 && _DEBUG==0
	; Pause.
	mov r4, #Menu_Beat_Frames
	bl wait_frames

	; Bitshifters.
	adr r0, bitshifters_splash
	ldr r1, screen_addr
	bl unlz4

	adrl r2, bitshifters_pal_block
	bl palette_init_fade_from_black
	; Fade.
	bl fade_in

	; Pause.
	mov r4, #Menu_Beat_Frames*2
	bl wait_frames
	.endif

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

	swi OS_NewLine
	ldr r0, song_number
	bl debug_print_r0

	mov r0, #32
	swi OS_WriteC
	ldr r0, autoplay_flag
	bl debug_print_r0

	mov r0, #32
	swi OS_WriteC
	ldr r0, song_ended
	bl debug_print_r0

.if Mouse_Enable
	mov r0, #32
	swi OS_WriteC
	ldr r0, prev_mouse_y
	bl debug_print_r0
.endif

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

.if 0
; R0=event number
event_handler:
	cmp r0, #Event_VSync
	movnes pc, r14

	STMDB sp!, {r0-r1, lr}

	; update the vsync counter
	LDR r0, vsync_count
	ADD r0, r0, #1
	STR r0, vsync_count

	; is there a new screen buffer ready to display?
	LDR r1, buffer_pending
	CMP r1, #0
	LDMEQIA sp!, {r0-r1, pc}

	; set the display buffer
	MOV r0, #0
	STR r0, buffer_pending
	MOV r0, #OSByte_WriteDisplayBank

	; Allow SWIs to be safely called from within interrupt handler.
	; See Archimedes Operating System book pp.264
	STMDB sp!, {r2-r12}
	MOV r9, pc     		; save the current PC & mode in R9.
	ORR r8, r9, #3 		; use R9 to make R8 a supervisor version.
	TEQP r8, #0			; use R8 to change mode.
	MOV r0,r0			; no-op **REQUIRED**
	STR lr, [sp, #-4]!	; stack the supervisor LR.
	; Now safe to call SWIs.
	
	SWI XOS_Byte

	; set full palette if there is a pending palette block
	ldr r2, palette_pending
	cmp r2, #0
	beq .4

    adr r1, palette_osword_block
    mov r0, #16
    strb r0, [r1, #1]       ; physical colour

    mov r3, #0
    .3:
    strb r3, [r1, #0]       ; logical colour

    ldr r4, [r2], #4        ; rgbx
    and r0, r4, #0xff
    strb r0, [r1, #2]       ; red
    mov r0, r4, lsr #8
    strb r0, [r1, #3]       ; green
    mov r0, r4, lsr #16
    strb r0, [r1, #4]       ; blue
    mov r0, #12
    swi XOS_Word

    add r3, r3, #1
    cmp r3, #16
    blt .3

	mov r0, #0
	str r0, palette_pending
.4:

	; Allow SWIs to be safely called from within interrupt handler.
	; See Archimedes Operating System book pp.264
	LDR lr, [sp], #4		; Get supervisor LR back.
	TEQP r9, #0 			; Restore the original state.
	MOV r0, r0				; No-op **REQUIRED**

	LDMIA sp!, {r2-r12}
	LDMIA sp!, {r0-r1, pc}

palette_pending:
	.long 0				; (optional) ptr to a block of palette data to set at vsync.
.endif

buffer_pending:
	.long 0				; screen bank number to display at vsync.

show_screen_at_vsync:
	; Show current bank at next vsync
	ldr r1, scr_bank
	MOV r0, #OSByte_WriteDisplayBank
	swi OS_Byte
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
	swi RasterMan_Release

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
	add r1, r1, r2				; MOD data address
	mov r0, #0					; load from address
	swi QTM_Load

	mov r0, #64					; max volume
	swi QTM_Volume

	; This seems to help minimise how much RasterMan timing slips after QTM_Start.
	swi RasterMan_Wait

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

	; R3=old item,
	bl plot_menu_item
	ldr r3, song_number
	bl plot_menu_item

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
.include "src/small-font.asm"
.include "src/columns.asm"
.if _DJANGO==1
.include "src/logo.asm"
.include "src/vubars.asm"
.include "src/scroller.asm"
.include "src/sprites.asm"
.endif
.if _RASTERMAN
.include "src/rasters.asm"
.endif
.include "lib/lz4-decode.asm"

; ============================================================================
; Data Segment
; ============================================================================

vdu_screen_disable_cursor:
.byte 22, Screen_Mode, 23,1,0,0,0,0,0,0,0,0
.p2align 2

music_table:
	.long music_01_mod - music_table
	.long music_02_mod - music_table
	.long music_03_mod - music_table
	.long music_04_mod - music_table
	.long music_05_mod - music_table
	.long music_06_mod - music_table
	.long music_07_mod - music_table
	.long music_08_mod - music_table
	.long music_09_mod - music_table
	.long music_10_mod - music_table
	.long music_11_mod - music_table

.p2align 2
logo_pal_block:
.incbin "build/logo.bin.pal"

.if _DJANGO==1
.p2align 2
logo_data:
.incbin "build/logo.bin"

.p2align 2
rabenauge_pal_block:
.incbin "build/rabenauge.bin.pal"

.p2align 2
rabenauge_splash:
.incbin "build/rabenauge.lz4"

.p2align 2
bitshifters_pal_block:
.incbin "build/bitshifters.bin.pal"

.p2align 2
bitshifters_splash:
.incbin "build/bitshifters.lz4"

.p2align 2
note_sprite_data:
.incbin "build/note1.bin"
.incbin "build/note2.bin"
.incbin "build/note3.bin"
.incbin "build/note4.bin"
.incbin "build/note5.bin"
.endif

.p2align 2
scroller_text_string:
.include "src/scrolltxt-final.asm"
scroller_text_string_end:

.p2align 2
scroller_font_data:
.incbin "build/scroller_font.bin"

.p2align 2
music_01_mod:
.incbin "build/music_01.bin"

.p2align 2
music_02_mod:
.incbin "build/music_02.bin"

.p2align 2
music_03_mod:
.incbin "build/music_03.bin"

.p2align 2
music_04_mod:
.incbin "build/music_04.bin"

.p2align 2
music_05_mod:
.incbin "build/music_05.bin"

.p2align 2
music_06_mod:
.incbin "build/music_06.bin"

.p2align 2
music_07_mod:
.incbin "build/music_07.bin"

.p2align 2
music_08_mod:
.incbin "build/music_08.bin"

.p2align 2
music_09_mod:
.incbin "build/music_09.bin"

.p2align 2
music_10_mod:
.incbin "build/music_10.bin"

.p2align 2
music_11_mod:
.incbin "build/music_11.bin"

; ============================================================================
; BSS Segment
; ============================================================================

.include "src/bss.asm"
