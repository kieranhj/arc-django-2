; ============================================================================
; arc-django-2 - An Archimedes port of Chipo Django 2 musicdisk by Rabenauge.
; ============================================================================

.equ _DEBUG, 0
.equ _DEBUG_RASTERS, (_DEBUG && 0)
.equ _DEBUG_SHOW, (_DEBUG && 0)
.equ _DEBUG_FAST_SPLASH, (_DEBUG && 1)
.equ _CHECK_FRAME_DROP, 0

.equ Sample_Speed_SlowCPU, 24		; ideally get this down for ARM2
.equ Sample_Speed_FastCPU, 16		; ideally 16us for ARM250+

.equ Screen_Banks, 3
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
.equ Splash_Frames, 242				; 3 seconds.
.equ Fade_Speed, 3
.endif

.equ Splash_YPos, 28
.equ Menu_Beat_Frames, 25				; 0.5 seconds.
.equ EndScreen_Frames, 3*50

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
.equ KeyBit_1, 6
.equ KeyBit_2, 7
.equ KeyBit_3, 8
.equ KeyBit_4, 9
.equ KeyBit_5, 10
.equ KeyBit_E, 11
.equ KeyBit_F, 12
.equ KeyBit_R, 13

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
.1:
	str r1, write_bank

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

	; Count how long the init takes as a very rough estimate of CPU speed.
	ldr r1, vsync_count
	cmp r1, #80		; ARM3~=20, ARM250~=70, ARM2~=108
	movge r0, #Sample_Speed_SlowCPU
	movlt r0, #Sample_Speed_FastCPU

	; Setup QTM for our needs.
	swi QTM_SetSampleSpeed

	mov r0, #-1
	mov r1, #0b100	; QTM retains sounds system after Pause/Stop/Clear
	mov r2, #-1
	swi QTM_SoundControl
	str r1, prev_sound_flags

	mov r0, #VU_Bars_Effect
	mov r1, #VU_Bars_Gravity
	swi QTM_VUBarControl

	mov r1, #0
	mov r0, #0b0010				; always loop our songs, we control autoplay manually.
	swi QTM_MusicOptions

	mov r0, #0
	mov r1, #Stereo_Positions
	swi QTM_Stereo

	; LATE INITALISATION HERE!
	bl get_next_bank_for_writing

	; Splash.
	ldr r2, rabenauge_pal_block_p
	bl palette_init_fade_to_black
	bl palette_set_block
	ldr r0, rabenauge_splash_p
	ldr r1, screen_addr
	add r1, r1, #Splash_YPos * Screen_Stride
	bl unlz4
	bl mark_write_bank_as_pending_display

	; Play splash ditty.
	mov r0, #0					; load from address and copy to RMA.
	ldr r1, splash_mod_p
	swi QTM_Load

	mov r0, #64					; max volume
	swi QTM_Volume
	swi QTM_Start
	
	; Pause.
	mov r4, #Splash_Frames
	bl wait_frames

	; Fade.
	mov r7, #64
	bl fade_out_with_volume
	swi OS_WriteI + 12		; cls
	swi QTM_Stop

	; Remaining QTM setup.
	mov r0, #AutoPlay_Default
	bl set_autoplay

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

	; This will block if there isn't a bank available to write to.
	bl get_next_bank_for_writing

	; Useful to determine frame rate for debug.
	.if _DEBUG || _CHECK_FRAME_DROP
	ldr r1, last_vsync
	ldr r2, vsync_count
	sub r0, r2, r1
	str r2, last_vsync
	str r0, vsync_delta
	.endif

	; R0 = vsync delta since last frame.
	.if _CHECK_FRAME_DROP
	cmp r0, #1
	ble .2
	str r2, last_dropped_frame
	.2:
	movle r4, #0x000000
	movgt r4, #0x0000ff
	bl palette_set_border
	.endif

	; ========================================================================
	; DRAW
	; ========================================================================

	SET_BORDER 0x00ff00		; green = screen clear
	ldr r12, screen_addr
	bl clear_left_screen

	SET_BORDER 0x00ffff		; yellow = columns
	ldr r12, screen_addr	
	bl plot_columns

	SET_BORDER 0xff00ff		; magenta = masked logo
	ldr r12, screen_addr
	ldr r0, song_number
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
	bl mark_write_bank_as_pending_display

	; exit if Escape is pressed
	swi OS_ReadEscapeState
	bcs exit

	; repeat!
	b main_loop

exit:
	; Fade out for a nice exit.
	.if _DEBUG_FAST_SPLASH==0
	ldr r7, song_number

	mov r0, #-1
	str r0, song_number				; tell irq handler to back off!
	adrl r2, logo_pal_block
	bl palette_init_fade_to_black

	adr r2, volumeTable
	ldrb r7, [r2, r7]
	bl fade_out_with_volume

	; End screen.
	SWI OS_WriteI + 12		; cls
	ldr r0, endscreen_p
	ldr r1, screen_addr
	bl unlz4
	bl mark_write_bank_as_pending_display
	ldr r2, rabenauge_pal_block_p
	bl palette_init_fade_from_black
	bl fade_in

	; Pause.
	mov r4, #EndScreen_Frames
	bl wait_frames
	.else
	mov r0, #19
	swi OS_Byte
	.endif

	; Disable music
	mov r0, #0
	swi QTM_Clear

	; Return QTM to a normal state.
	mov r0, #-1
	ldr r1, prev_sound_flags
	mov r2, #-1
	swi QTM_SoundControl

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
	ldr r1, write_bank
	swi OS_Byte
	; and write to it
	mov r0, #OSByte_WriteVDUBank
	ldr r1, write_bank
	swi OS_Byte

	; Flush keyboard buffer.
	mov r0, #15
	mov r1, #1
	swi OS_Byte

	SWI OS_Exit

; ============================================================================
; Sequence helpers.
; ============================================================================

splash_mod_p:
	.long splash_mod_no_adr

rabenauge_pal_block_p:
	.long rabenauge_pal_block_no_adr

rabenauge_splash_p:
	.long rabenauge_splash_no_adr

endscreen_pal_block_p:
	.long endscreen_pal_block_no_adr

endscreen_p:
	.long endscreen_no_adr

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

; R7=starting volume.
fade_out_with_volume:
	str lr, [sp, #-4]!
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
	bpl .1
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
	.if 0
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
.endif

.if 1
	; display frame count / frame rate etc.
	ldr r0, vsync_delta
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

displayed_bank:
	.long 0				; VIDC sreen bank being displayed

write_bank:
	.long 0				; VIDC screen bank being written to

pending_bank:
	.long 0				; VIDC screen to be displayed next

vsync_count:
	.long 0				; current vsync count from start of exe.

.if _DEBUG || _CHECK_FRAME_DROP
last_vsync:
	.long 0

vsync_delta:
	.long 0
.endif

.if _CHECK_FRAME_DROP
last_dropped_frame:
	.long 0
.endif

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
	cmp r2, #RMKey_1
	orreq r0, r0, #1<<KeyBit_1
	cmp r2, #RMKey_2
	orreq r0, r0, #1<<KeyBit_2
	cmp r2, #RMKey_3
	orreq r0, r0, #1<<KeyBit_3
	cmp r2, #RMKey_4
	orreq r0, r0, #1<<KeyBit_4
	cmp r2, #RMKey_5
	orreq r0, r0, #1<<KeyBit_5
	cmp r2, #RMKey_E
	orreq r0, r0, #1<<KeyBit_E
	cmp r2, #RMKey_F
	orreq r0, r0, #1<<KeyBit_F
	cmp r2, #RMKey_R
	orreq r0, r0, #1<<KeyBit_R
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
	cmp r2, #RMKey_1
	biceq r0, r0, #1<<KeyBit_1
	cmp r2, #RMKey_2
	biceq r0, r0, #1<<KeyBit_2
	cmp r2, #RMKey_3
	biceq r0, r0, #1<<KeyBit_3
	cmp r2, #RMKey_4
	biceq r0, r0, #1<<KeyBit_4
	cmp r2, #RMKey_5
	biceq r0, r0, #1<<KeyBit_5
	cmp r2, #RMKey_E
	biceq r0, r0, #1<<KeyBit_E
	cmp r2, #RMKey_F
	biceq r0, r0, #1<<KeyBit_F
	cmp r2, #RMKey_R
	biceq r0, r0, #1<<KeyBit_R

.3:
	str r0, keyboard_pressed_mask
	ldr r0, [sp], #4
	mov pc, lr


mark_write_bank_as_pending_display:
	; Mark write bank as pending display.
	ldr r1, write_bank

	; What happens if there is already a pending bank?
	; At the moment we block but could also overwrite
	; the pending buffer with the newer one to catch up.
	; TODO: A proper fifo queue for display buffers.
	.1:
	ldr r0, pending_bank
	cmp r0, #0
	bne .1
	str r1, pending_bank

	; Show panding bank at next vsync.
	MOV r0, #OSByte_WriteDisplayBank
	swi OS_Byte
	mov pc, lr

get_next_bank_for_writing:
	; Increment to next bank for writing
	ldr r1, write_bank
	add r1, r1, #1
	cmp r1, #Screen_Banks
	movgt r1, #1

	; Block here if trying to write to displayed bank.
	.1:
	ldr r0, displayed_bank
	cmp r1, r0
	beq .1

	str r1, write_bank

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
	LDR r1, write_bank
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
	mov r0, #0
	str r0, vsync_bodge

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
	ldr r0, vsync_bodge
	cmp r0, #0
	beq .3
	b exitVs
.3:
	mov r0, #1
	str r0, vsync_bodge

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

	; Update the vsync counter
	LDR r0, vsync_count
	ADD r0, r0, #1
	STR r0, vsync_count

	; Pending bank will now be displayed.
	ldr r1, pending_bank
	cmp r1, #0
	beq exitVs

	str r1, displayed_bank

	; Clear pending bank.
	mov r0, #0
	str r0, pending_bank

exitVs:
	TEQP    PC,#0b10<<26 | 0b10
	MOV     R0,R0

nottimer1orVs:
	LDMFD   R13!,{R0-R1,R11-R12}
	ldr pc, oldirqhandler

vsync_bodge:
	.long 0

; ============================================================================
; Play the music!
; ============================================================================

song_number:
	.long -1

autoplay_flag:
	.long 0

song_timer:
	.long 0

song_pause:
	.long 0

volume_fade:
	.long 0

prev_sound_flags:
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
	mov r0, #-1					; load from address and copy to RMA.
	swi QTM_Load

	adr r2, volumeTable
	ldr r1, song_number
	ldrb r0, [r2, r1]
	swi QTM_Volume

	; Play music!
	swi QTM_Start

	mov r0, #0
	str r0, song_timer
	str r0, song_pause
	str r0, volume_fade
	mov pc, lr

check_autoplay:
	; Are we already transitioning to the next song?
	ldr r0, song_pause
	cmp r0, #0
	bne .3

	ldr r0, volume_fade
	cmp r0, #0
	bne .1

	; How long has the song been running?
	ldr r1, song_timer
	add r1, r1, #1
	str r1, song_timer

	; Check autoplay flag - just exit if off.
	ldr r0, autoplay_flag
	cmp r0, #0
	moveq pc, lr

	; Has the song timer gone over our autoplay duration?
	ldr r0, song_number

	adr r2, durationTable
	ldr r3, [r2, r0, lsl #2]

	adr r4, volumeTable
	ldrb r5, [r4, r0]

	sub r3, r3, r5			; so we end on Bodo's frame?
	cmp r1, r3
	movlt pc, lr

	; Kick off fade out.
	str r5, volume_fade
	mov pc, lr

	; Fade out volume.
.1:
	subs r0, r0, #1
	str r0, volume_fade
	beq .2

	swi QTM_Volume
	mov pc, lr

	; Pause for breath between tracks.
.2:
	ldr r1, song_number
	adr r2, songpausetable
	ldr r0, [r2, r1, lsl #2]
	str r0, song_pause
	mov pc, lr

.3:
	subs r0, r0, #1
	str r0, song_pause
	movne pc, lr

	str lr, [sp, #-4]!
	ldr r0, song_number
	mov r3, r0
	add r0, r0, #1
	cmp r0, #MAX_SONGS
	movge, r0, #0
	bl play_song

	ldr pc, [sp], #4

; R0=autoplay flag.
set_autoplay:
	str r0, autoplay_flag
	mov pc, lr

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
	.long birdhouse_mod_no_adr			; 1
	.long funky_delicious_mod_no_adr	; 2
	.long autumn_mood_mod_no_adr		; 3
	.long je_suis_k_mod_no_adr			; 4
	.long square_circles_mod_no_adr		; 5
	.long cool_beans_mod_no_adr			; 6
	.long la_soupe_mod_no_adr			; 7
	.long sajt_mod_no_adr				; 8
	.long bodoaxian_mod_no_adr			; 9
	.long holodash_mod_no_adr			; 10
	.long squid_ring_mod_no_adr			; 11
	.long lies_mod_no_adr				; 12
	.long vectrax_mod_no_adr			; 13
	.long changing_waves_mod_no_adr		; 14

volumeTable:    
    .byte    35   ; birdhouse
    .byte    50    ; funky delicious
    .byte    62-2  ; autumn
    .byte    51  ; je suis k
    .byte    60-2  ; square circles
    .byte    50     ; coolbeans
    .byte    54  ; la soupe
    .byte    56-3  ; sajt
    .byte    59-1  ; bodoaxian
    .byte    64    ; holodash
    .byte    39-2  ; squid ring
    .byte    61-1  ; lies
    .byte    53      ; vectrax longplay
    .byte    45-8-4    ; changing waves
.p2align 2

durationTable:
;    dcb.w   10,250  
    .long    51*50       ; birdhouse
    .long    50*92      ; funky delicious
    .long    192*50-40      ; autumn
    .long    159*50      ; je suis k
    .long    173*50      ; square circles
    .long    145*50      ; coolbeans
    .long    120*50      ; la soupe
    .long    95*50       ; sajt
    .long    110*50      ; bodoaxian
    .long    116*50      ; holodash
    .long    174*50      ; squid ring
    .long    181*50-10   ; lies
    .long    485*50      ; vectrax longplay
    .long    50*6*60     ; changing waves

; break between tunes
songpausetable:
    .long    50      ; birdhouse
    .long    50      ; funky delicious
    .long    10       ; autumn
    .long    70      ; je suis k
    .long    80      ; square circles
    .long    50      ; coolbeans
    .long    80+20      ; la soupe
    .long    50      ; sajt
    .long    70      ; bodoaxian
    .long    90      ; holodash
    .long    90      ; squid ring
    .long    50-10   ; lies
    .long    50      ; vectrax longplay
    .long    600      ; changing waves

logo_pal_block:
.incbin "data/logo-palette-hacked.bin"

timer1_vidc_regs_list: ; bgr
.if _DEBUG && !_DEBUG_RASTERS && !_CHECK_FRAME_DROP
	.long VIDC_Border | 0x0f0
.endif
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
.if _DEBUG && !_DEBUG_RASTERS
	.long VIDC_Border | 0x000
.endif
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
