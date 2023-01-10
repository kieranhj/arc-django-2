; ============================================================================
; BSS.
; ============================================================================

.bss

; ============================================================================

stack:
    .skip 1024
stack_base:

; ============================================================================

.p2align 2
vidc_table_1:
	.skip 256*4*4

; TODO: Can we get rid of these?
vidc_table_2:
	.skip 256*4*4

vidc_table_3:
	.skip 256*8*4

memc_table:
	.skip 256*2*4

; ============================================================================
