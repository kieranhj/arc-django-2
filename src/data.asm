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

.if _DJANGO==1
.p2align 2
rabenauge_pal_block_no_adr:
.incbin "build/rabenauge.bin.pal"

.p2align 2
rabenauge_splash_no_adr:
.incbin "build/rabenauge.lz4"
.endif

.p2align 2
scroller_font_data_no_adr:
.incbin "build/big-font.bin"

.p2align 2
new_menu_font_data_no_adr:
.incbin "build/small-font.bin"

.p2align 2
menu_font_data_no_adr:
.incbin "build/small-font.bin"

.p2align 2
music_01_mod_no_adr:
.incbin "build/music_01.bin"

.p2align 2
music_02_mod_no_adr:
.incbin "build/music_02.bin"

.p2align 2
music_03_mod_no_adr:
.incbin "build/music_03.bin"

.p2align 2
music_04_mod_no_adr:
.incbin "build/music_04.bin"

.p2align 2
music_05_mod_no_adr:
.incbin "build/music_05.bin"

.p2align 2
music_06_mod_no_adr:
.incbin "build/music_06.bin"

.p2align 2
music_07_mod_no_adr:
.incbin "build/music_07.bin"

.p2align 2
music_08_mod_no_adr:
.incbin "build/music_08.bin"

.p2align 2
music_09_mod_no_adr:
.incbin "build/music_09.bin"

.p2align 2
music_10_mod_no_adr:
music_11_mod_no_adr:
.incbin "build/music_10.bin"

; ============================================================================

.p2align 2
scroller_text_string_no_adr:
.include "src/scrolltxt-final.asm"
scroller_text_string_end_no_adr:

; ============================================================================
