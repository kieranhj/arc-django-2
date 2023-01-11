; ============================================================================
; Rasters via RasterMan.
; ============================================================================

.equ VU_Bars_Y_Pos, 216
.equ VU_Bars_Height, 3
.equ VU_Bars_Gap, 4

.equ Horizontal_Divider_1, 100
.equ Horizontal_Divider_2, 202
.equ Horizontal_Divider_3, 233
.equ MenuArea_Top, Horizontal_Divider_1+2
.equ MenuArea_Height, Horizontal_Divider_2-Horizontal_Divider_1-3
.equ Stave_Top, VU_Bars_Y_Pos - VU_Bars_Gap

rasters_init:
    ; Configure RasterMan for future compatibility.
    mov r0, #4
    mov r1, #0
    mov r2, #-1
    mov r3, #-1
    mov r4, #-1
    swi RasterMan_Configure

	; Init tables.
	adr r5, raster_tables
	ldmia r5, {r0-r3}
	stmfd sp!, {r0-r3}

	mov r4, #0
	mov r6, #0x40000000		; set border colour black.
	mov r7, r6
	mov r8, r6
	mov r9, r6
	mov r5, #256
.1:
	stmia r0!, {r6-r9}		; 4x VIDC commands per line.
	stmia r1!, {r6-r9}		; 4x VIDC commands per line.
	stmia r2!, {r6-r9}		; 4x VIDC commands per line.
	stmia r2!, {r6-r9}		; 4x VIDC commands per line.
	str r4, [r3], #4
	str r4, [r3], #4
	subs r5, r5, #1
	bne .1

	ldmfd sp, {r0-r3}
	swi RasterMan_SetTables
	ldmfd sp!, {r0-r3}

    ; Add some actual rasters. Use a table, dummy.
    mov r3, #0
    adr r2, raster_list
.2:
    ldmia r2!, {r5-r9}
    cmp r5, #-1
    moveq pc, lr

    movs r4, r5, lsr #8     ; strip out repeat.
    moveq r4, #1            ; zero repeat means just 1.
    and r5, r5, #0xff       ; raster line.
    add r1, r0, r5, lsl #4  ; find line entry in VIDC table 1.

.3:
    stmia r1!, {r6-r9}      ; blat VIDC registers for line.
    subs r4, r4, #1
    bne .3

    str r3, [r1]            ; always reset bg colour to black.
    
    b .2

; Number repeats << 8 | Rasterline, VIDC registers x 4.
; 0xffffffff to end list.
raster_list:
    .long Horizontal_Divider_1,                             VIDC_Col0 | 0xd99,  VIDC_Border | 0xd99, VIDC_Border | 0xd99, VIDC_Border | 0xd99       ; divider 1
    .long MenuArea_Height << 8 | MenuArea_Top,              VIDC_Col0 | 0x733,  VIDC_Border | 0x733, VIDC_Border | 0x733, VIDC_Border | 0x733       ; menu area
    .long Horizontal_Divider_2,                             VIDC_Col0 | 0xd99,  VIDC_Border | 0xd99, VIDC_Border | 0xd99, VIDC_Border | 0xd99       ; divider 2
    .long VU_Bars_Height << 8 | Stave_Top,                  VIDC_Col0 | 0x300,  VIDC_Border | 0x300, VIDC_Border | 0x300, VIDC_Border | 0x300       ; stave 1
    .long VU_Bars_Height << 8 | Stave_Top + 1*VU_Bars_Gap,  VIDC_Col0 | 0x300,  VIDC_Border | 0x300, VIDC_Border | 0x300, VIDC_Border | 0x300       ; stave 2
    .long VU_Bars_Height << 8 | Stave_Top + 2*VU_Bars_Gap,  VIDC_Col0 | 0x300,  VIDC_Border | 0x300, VIDC_Border | 0x300, VIDC_Border | 0x300       ; stave 3
    .long VU_Bars_Height << 8 | Stave_Top + 3*VU_Bars_Gap,  VIDC_Col0 | 0x300,  VIDC_Border | 0x300, VIDC_Border | 0x300, VIDC_Border | 0x300       ; stave 4
    .long VU_Bars_Height << 8 | Stave_Top + 4*VU_Bars_Gap,  VIDC_Col0 | 0x300,  VIDC_Border | 0x300, VIDC_Border | 0x300, VIDC_Border | 0x300       ; stave 5
    .long Horizontal_Divider_3,                             VIDC_Col0 | 0xd99,  VIDC_Border | 0xd99, VIDC_Border | 0xd99, VIDC_Border | 0xd99       ; divider 3

    ; Scroller area. Assume Scroller_Y_Pos == 237.
    .long 238,                                              VIDC_Col0 | 0x000,  VIDC_Col15 | 0xfff, VIDC_Border | 0x000, VIDC_Border | 0x000        ; purple gradient
    .long 239,                                              VIDC_Col0 | 0x000,  VIDC_Col15 | 0xfee, VIDC_Border | 0x000, VIDC_Border | 0x000        ; purple gradient
    .long 240,                                              VIDC_Col0 | 0x000,  VIDC_Col15 | 0xedd, VIDC_Border | 0x000, VIDC_Border | 0x000        ; purple gradient
    .long 241,                                              VIDC_Col0 | 0x000,  VIDC_Col15 | 0xecc, VIDC_Border | 0x000, VIDC_Border | 0x000        ; purple gradient
    .long 242,                                              VIDC_Col0 | 0x000,  VIDC_Col15 | 0xdbb, VIDC_Border | 0x000, VIDC_Border | 0x000        ; purple gradient
    .long 243,                                              VIDC_Col0 | 0x000,  VIDC_Col15 | 0xdaa, VIDC_Border | 0x000, VIDC_Border | 0x000        ; purple gradient
    .long 244,                                              VIDC_Col0 | 0x000,  VIDC_Col15 | 0xc99, VIDC_Border | 0x000, VIDC_Border | 0x000        ; purple gradient
    .long 245,                                              VIDC_Col0 | 0x000,  VIDC_Col15 | 0xc88, VIDC_Border | 0x000, VIDC_Border | 0x000        ; purple gradient
    .long 246,                                              VIDC_Col0 | 0x000,  VIDC_Col15 | 0xb77, VIDC_Border | 0x000, VIDC_Border | 0x000        ; purple gradient
    .long 247,                                              VIDC_Col0 | 0x000,  VIDC_Col15 | 0xb66, VIDC_Border | 0x000, VIDC_Border | 0x000        ; purple gradient
    .long 248,                                              VIDC_Col0 | 0x200,  VIDC_Col15 | 0xa55, VIDC_Border | 0x200, VIDC_Border | 0x200        ; purple gradient
    .long 249,                                              VIDC_Col0 | 0x400,  VIDC_Col15 | 0xa44, VIDC_Border | 0x400, VIDC_Border | 0x400        ; purple gradient
    .long 250,                                              VIDC_Col0 | 0x600,  VIDC_Col15 | 0x933, VIDC_Border | 0x600, VIDC_Border | 0x600        ; purple gradient
    .long 251,                                              VIDC_Col0 | 0x800,  VIDC_Col15 | 0x922, VIDC_Border | 0x800, VIDC_Border | 0x800        ; purple gradient
    .long 252,                                              VIDC_Col0 | 0xa00,  VIDC_Col15 | 0x811, VIDC_Border | 0xa00, VIDC_Border | 0xa00        ; purple gradient
    .long 253,                                              VIDC_Col0 | 0xc00,  VIDC_Col15 | 0x800, VIDC_Border | 0xc00, VIDC_Border | 0xc00        ; purple gradient
    .long 254,                                              VIDC_Col0 | 0xe00,  VIDC_Col15 | 0xfff, VIDC_Border | 0xe00, VIDC_Border | 0xe00        ; purple gradient
    .long 255,                                              VIDC_Col0 | 0x000,  VIDC_Col15 | 0xfff, VIDC_Border | 0x000, VIDC_Border | 0x000        ; last line all black!

    ; End.
    .long 0xffffffff

raster_tables:
	.long vidc_table_1_no_adr
	.long vidc_table_2_no_adr
	.long vidc_table_3_no_adr
	.long memc_table_no_adr
