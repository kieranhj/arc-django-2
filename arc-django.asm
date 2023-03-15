; ============================================================================
; arc-django-2 - An Archimedes port of Chipo Django 2 musicdisk by Rabenauge.
; ============================================================================

.equ _DEBUG, 1
.equ _DEBUG_RASTERS, (_DEBUG && 1)
.equ _DEBUG_SHOW, (_DEBUG && 0)
.equ _DEBUG_FAST_SPLASH, (_DEBUG && 1)

.equ Sample_Speed_SlowCPU, 48		; ideally get this down for ARM2
.equ Sample_Speed_FastCPU, 16		; ideally 16us for ARM250+

.equ Screen_Banks, 2
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

.equ MAX_SONGS, 14

.if _DEBUG_FAST_SPLASH
.equ Splash_Frames, 3
.equ Fade_Speed, 1
.else
.equ Splash_Frames, 3*50				; 3 seconds.
.equ Fade_Speed, 3
.endif

.equ Splash_YPos, 28
.equ Menu_Beat_Frames, 25				; 0.5 seconds.

.equ VU_Bars_Effect, 2					; 'effect'
.equ VU_Bars_Gravity, 2					; lines per vsync

.equ Mouse_Enable, 1
.equ Mouse_Sensitivity, 10

.equ AutoPlay_Default, 1
.equ Stereo_Positions, 1		; Amiga (full) stereo positions.

.equ KeyBit_Space, 0
.equ KeyBit_Return, 1
.equ KeyBit_ArrowUp, 2
.equ KeyBit_ArrowDown, 3
.equ KeyBit_A, 4
.equ KeyBit_LeftClick, 5

; TODO: Final location for ARM2 and maybe increase gap to menu..?
.equ RasterSplitLine, 56+100			; 56 lines from vsync to screen start
; Check MENU_TOP_YPOS definition.

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

	; Clear all screen buffers
	mov r1, #1
	str r1, scr_bank
.1:
	; CLS bank N
	mov r0, #OSByte_WriteVDUBank
	swi OS_Byte
	SWI OS_WriteI + 12		; cls

	add r1, r1, #1
	cmp r1, #Screen_Banks
	ble .1

	; Grab mouse.
	.if Mouse_Enable
	swi OS_Mouse
	str r1, prev_mouse_y
	.endif

	; Seed RND.
	swi OS_ReadMonotonicTime
	str r0, rnd_seed

	; Install our own IRQ handler - thanks Steve! :)
	bl install_irq_handler

	; EARLY INIT / LOAD STUFF HERE!
	bl new_font_init
	bl maths_init
	; R12=top of RAM used.
	bl menu_init		; must come after new_font_init.
	bl init_3d_scene
	bl scroller_init
	bl logo_init

	; QTM Config.

	; Count how long the init takes as a very rough estimate of CPU speed.
	ldr r1, vsync_count
	cmp r1, #80		; ARM3~=20, ARM250~=70, ARM2~=108
	movge r0, #Sample_Speed_SlowCPU
	movlt r0, #Sample_Speed_FastCPU
	swi QTM_SetSampleSpeed

	mov r0, #8    	; set bit 3 of music options byte = QTM retains control of sound system after Pause/Stop/Clear
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

	; LATE INITALISATION HERE!
	bl get_next_screen_for_writing

	; Splash.
	ldr r2, rabenauge_pal_block_p
	bl palette_init_fade_to_black
	bl palette_set_block
	ldr r0, rabenauge_splash_p
	ldr r1, screen_addr
	add r1, r1, #Splash_YPos * Screen_Stride
	bl unlz4

	bl show_screen_at_vsync

	; Pause.
	mov r4, #Splash_Frames
	bl wait_frames
	; Fade.
	bl fade_out

	swi OS_WriteI + 12		; cls

	; Pause.
	mov r4, #Menu_Beat_Frames
	bl wait_frames

	; Set palette (shows screen).
	adrl r2, logo_pal_block
	bl palette_set_block

	; Claim the Event vector.
	MOV r0, #EventV
	ADR r1, event_handler
	MOV r2, #0
	SWI OS_Claim

	; Claim the Error vector.
	MOV r0, #ErrorV
	ADR r1, error_handler
	MOV r2, #0
	SWI OS_Claim

	; Start with song #0.
	mov r0, #0
	bl play_song

	; Enable key pressed event.
	mov r0, #OSByte_EventEnable
	mov r1, #Event_KeyPressed
	SWI OS_Byte

	; Wait for vsync on first frame.
	ldr r0, vsync_count
	str r0, last_vsync

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
	bl scroller_update_new
	bl update_3d_scene
	SET_BORDER 0x000000

	; ========================================================================
	; VSYNC
	; ========================================================================

	; Block if we've not even had a vsync since last time - we're >50Hz!
	ldr r1, last_vsync
.1:
	ldr r2, vsync_count
	cmp r1, r2
	beq .1
	sub r0, r2, r1
	str r2, last_vsync

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
	bl scroller_draw_new

	SET_BORDER 0x0000ff		; red = plot cube
	ldr r12, screen_addr
	bl draw_3d_scene

	SET_BORDER 0xff0000		; blue = plot menu
	ldr r12, screen_addr
	bl plot_menu_sprites

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
	; Wait for vsync (any pending buffers)
	mov r0, #0
	swi OS_Byte

	; Remove music autoplay handler.
	bl release_music_interrupt

	; Fade out for a nice exit.
	.if _DEBUG_FAST_SPLASH==0
	mov r0, #-1
	str r0, song_number				; tell irq handler to back off!
	adrl r2, logo_pal_block
	bl palette_init_fade_to_black
	bl fade_out_with_volume
	.endif

	; Return QTM to a normal state.
	mov r0, #8	;clear bit 3 of music options byte
	mov r1, #0
	swi QTM_MusicOptions

	; Disable music
	mov r0, #0
	swi QTM_Clear

	; Remove our IRQ handler
	bl uninstall_irq_handler

	; Disable key press event
	mov r0, #OSByte_EventDisable
	mov r1, #Event_KeyPressed
	swi OS_Byte

	; Release our event handler
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

; ============================================================================
; Sequence helpers.
; ============================================================================

rabenauge_pal_block_p:
	.long rabenauge_pal_block_no_adr

rabenauge_splash_p:
	.long rabenauge_splash_no_adr

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
	movne pc, lr

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

	bl uninstall_irq_handler

	; Release event handler.
	MOV r0, #OSByte_EventDisable
	MOV r1, #Event_KeyPressed
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
; Interrupt handling.
; ============================================================================

oldirqhandler:
	.long 0

oldirqjumper:
	.long 0

vsyncstartdelay:
	.long 127*RasterSplitLine  ;2000000/50.08

install_irq_handler:
	mov r1, #0x18					; IRQ vector.
	
	; Remember previous IRQ branch call.
	ldr r0, [r1]					; old IRQ handler.
	str r0, oldirqjumper

	; Calculate old IRQ hanlder address from branch opcode.
	bic r0, r0, #0xff000000
	mov r0, r0, lsl #2
	add r0, r0, #32
	str r0, oldirqhandler

	; Set Timer 1.
	SWI		OS_EnterOS
	MOV     R12,#0x3200000           ;IOC address

	TEQP    PC,#0b11<<26 | 0b11  ;jam all interrupts!

	LDR     R0,vsyncstartdelay
	STRB    R0,[R12,#0x50]
	MOV     R0,R0,LSR#8
	STRB    R0,[R12,#0x54]           ;prepare timer 1 for waiting until screen start
									;don't start timer1, done on next Vs...
	TEQP    PC,#0
	MOV     R0,R0

	; Install our IRQ handler.
	swi OS_IntOff
	adr r0, irq_handler
	sub r0, r0, #32
	mov r0, r0, lsr #2
	add r0, r0, #0xea000000			; B irq_handler.
	str r0, [r1]
	swi OS_IntOn

	mov pc, lr

uninstall_irq_handler:
	mov r1, #0x18					; IRQ vector.
	
	; Restore previous IRQ branch call.
	ldr r0, oldirqjumper
	str r0, [r1]

	mov pc, lr

irq_handler:
	STMFD   R13!,{R0-R1,R11-R12}
	MOV     R12,#0x3200000           ;IOC address
	LDRB    R0,[R12,#0x14+0]
	TST     R0,#1<<6 | (1<<3)
	BEQ     nottimer1orVs           ;not T1 or Vs, back to RISCOS

	TEQP    PC,#0b11<<26 | 0b11
	MOV     R0,R0

	MOV     R11,#VIDC_Write
	TST     R0,#1<<3
	BNE     vsync                   ;...Vs higher priority than T1

timer1:
	ldr r0, song_number
	cmp r0, #-1
	beq .2
	adr	r1, timer1_vidc_regs_list
	.1:
	ldr r0, [r1], #4
	cmp r0, #-1
	beq .2
	str r0, [r11]					; why Steve has ,#0x40?
	b .1
	.2:

	LDRB    R0,[R12,#0x18]
	BIC     R0,R0,#1<<6
	STRB    R0,[R12,#0x18]           ;stop T1 irq...

exittimer1:
	TEQP    PC,#0b10<<26 | 0b10
	MOV     R0,R0
	LDMFD   R13!,{R0-R1,R11-R12}
	SUBS    PC,R14,#4

vsync:
	ldr r0, song_number
	cmp r0, #-1
	beq .2
	adr	r1, vsync_vidc_regs_list
	.1:
	ldr r0, [r1], #4
	cmp r0, #-1
	beq .2
	str r0, [r11]					; why Steve has ,#0x40?
	b .1
	.2:

	STRB    R0,[R12,#0x58]           ;T1 GO (latch already set up)
	LDRB    R0,[R12,#0x18]
	ORR     R0,R0,#1<<6
	STRB    R0,[R12,#0x18]           ;enable T1 irq...
	MOV     R0,#1<<6
	STRB    R0,[R12,#0x14]           ;clear any pending T1 irq

	; update the vsync counter
	LDR r0, vsync_count
	ADD r0, r0, #1
	STR r0, vsync_count

exitVs:
	TEQP    PC,#0b10<<26 | 0b10
	MOV     R0,R0

nottimer1orVs:
	LDMFD   R13!,{R0-R1,R11-R12}
	ldr pc, oldirqhandler


; ============================================================================
; Play the music!
; ============================================================================

song_number:
	.long -1

autoplay_flag:
	.long AutoPlay_Default

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
.include "src/new-font.asm"
.include "src/menu.asm"
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
	.long music_12_mod_no_adr
	.long music_13_mod_no_adr
	.long music_14_mod_no_adr

logo_pal_block:
.incbin "data/logo-palette-hacked.bin"

timer1_vidc_regs_list: ; bgr
	.long VIDC_Col1  | 0x533			; cube colours
	.long VIDC_Col2  | 0xb88
	.long VIDC_Col3  | 0x756
	.long VIDC_Col4  | 0xacd			; menu colours
	.long VIDC_Col5  | 0xafc			; (under cube)
	.long VIDC_Col6  | 0xafb
	.long VIDC_Col7  | 0x7fb
	.long VIDC_Col8  | 0xfff			; line marker
	;
	.long VIDC_Col10 | 0x4ca			; scroller
	.long -1

vsync_vidc_regs_list:
	.long VIDC_Col1  | 0x700			; logo colours
	.long VIDC_Col2  | 0x821
	.long VIDC_Col3  | 0xa42
	.long VIDC_Col4  | 0xb73
	.long VIDC_Col5  | 0xc94
	.long VIDC_Col6  | 0xec7
	.long VIDC_Col7  | 0xfeb
	.long VIDC_Col8  | 0xfed
	;
	.long VIDC_Col10 | 0x000
	.long -1

; ============================================================================
; DATA Segment
; ============================================================================

.include "src/data.asm"

; ============================================================================
; BSS Segment
; ============================================================================

.include "src/bss.asm"
