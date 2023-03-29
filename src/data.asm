; ============================================================================
; DATA.
; ============================================================================

.data   ; TODO: Do we need an rodata segment?

.p2align 6

; ============================================================================

.include "lib/lib_data.asm"

; ============================================================================

.p2align 2
logo_data_no_adr:
.incbin "build/logo.bin"

.p2align 2
logo_mask_no_adr:
.incbin "build/logo.bin.mask"

; ============================================================================

.p2align 2
rabenauge_pal_block_no_adr:
.incbin "build/rabenauge.bin.pal"

.p2align 2
rabenauge_splash_no_adr:
.incbin "build/rabenauge.lz4"

.p2align 2
endscreen_pal_block_no_adr:
.incbin "build/endscreen.bin.pal"

.p2align 2
endscreen_no_adr:
.incbin "build/endscreen.lz4"

; ============================================================================

.p2align 2
scroller_font_data_no_adr:
.incbin "build/big-font.bin"

; ============================================================================

.p2align 2
new_menu_font_data_no_adr:
.incbin "build/small-font.bin"

.p2align 2
menu_font_data_no_adr:
.incbin "build/small-font.bin"

; ============================================================================

.p2align 2
birdhouse_mod_no_adr:
.incbin "build/birdhouse.mod"

.p2align 2
autumn_mood_mod_no_adr:
.incbin "build/autumn_mood.mod"

.p2align 2
square_circles_mod_no_adr:
.incbin "build/square_circles.mod"

.p2align 2
je_suis_k_mod_no_adr:
.incbin "build/je_suis_k.mod"

.p2align 2
la_soupe_mod_no_adr:
.incbin "build/la_soupe.mod"

.p2align 2
bodoaxian_mod_no_adr:
.incbin "build/bodoaxian.mod"

.p2align 2
sajt_mod_no_adr:
.incbin "build/sajt.mod"

.p2align 2
holodash_mod_no_adr:
.incbin "build/holodash.mod"

.p2align 2
squid_ring_mod_no_adr:
.incbin "build/squid_ring.mod"

.p2align 2
lies_mod_no_adr:
.incbin "build/lies.mod"

.p2align 2
changing_waves_mod_no_adr:
.incbin "build/changing_waves.mod"

.p2align 2
vectrax_mod_no_adr:
.incbin "build/vectrax.mod"

.p2align 2
funky_delicious_mod_no_adr:
.incbin "build/funky_delicious.mod"

.p2align 2
cool_beans_mod_no_adr:
.incbin "build/cool_beans.mod"

.p2align 2
digitags_mod_no_adr:
.incbin "build/digitags.mod"

.p2align 2
splash_mod_no_adr:
.incbin "build/music_splash.mod"

; ============================================================================

.p2align 2
scroller_text_string_no_adr:
; Add 20 blank chars so that scroller begins on RHS of the screen, as per Amiga.
.byte "                    "
.include "src/scrolltxt-final.asm"
scroller_text_string_end_no_adr:
.p2align 2

; ============================================================================
