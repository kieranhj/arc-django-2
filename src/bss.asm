; ============================================================================
; BSS.
; ============================================================================

.bss

.p2align 6

; ============================================================================

stack_no_adr:
    .skip 1024
stack_base_no_adr:

; ============================================================================

new_font_map_no_adr:
	.skip 256			; maps ASCII to small font glyph no.

; ============================================================================

scroller_font_data_shifted_no_adr:
	.skip Scroller_Max_Glyphs * Scroller_Glyph_Height * 12 * 8

; ============================================================================

.include "lib/lib_bss.asm"

; ============================================================================
