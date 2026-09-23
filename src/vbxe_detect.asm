; ============================================================================
; VBXE Detection Module
; Base address must be $D600/$D700 (NOT $D640/$D740!)
; Registers are at offsets $40-$5F from base
; ============================================================================

; ----------------------------------------------------------------------------
; memac_patch - VBXE at $D7xx: move every absolute MEMAC B store (assembled
; for $D6xx) to the detected register page
; ----------------------------------------------------------------------------
.proc memac_patch
        lda zp_vbxe_base+1
        cmp #>VBXE_REGS
        beq ?done
 .if 1                          ; 2026-09-23 (6502-loops-tables-smc: index counting up to zero)
        ldx #256-MEMAC_COUNT*2
?lp     lda memac_sites+MEMAC_COUNT*2-256,x
        sta ?st+1
        lda memac_sites+MEMAC_COUNT*2-256+1,x
        sta ?st+2
        lda zp_vbxe_base+1
?st     sta $FFFF              ; (patched: operand high byte of one store)
        inx
        inx
        bne ?lp
 .else
        ldx #0
?lp     lda memac_sites,x
        sta ?st+1
        lda memac_sites+1,x
        sta ?st+2
        lda zp_vbxe_base+1
?st     sta $FFFF              ; (patched: operand high byte of one store)
        inx
        inx
        cpx #MEMAC_COUNT*2
        bne ?lp
 .endif
?done   rts
.endp

.proc vbxe_detect
        ; Try $D600, then $D700 (registers at base+$40..$5F)
        lda #0
        sta zp_vbxe_base       ; both bases are page-aligned
        ldx #>$D600
        ldy #VBXE_CORE_VER     ; Y=$40 -> base+$40 = CORE_VERSION
?try    stx zp_vbxe_base+1
        lda #0
        sta (zp_vbxe_base),y
        lda (zp_vbxe_base),y   ; (a write-then-read of the register)
        cmp #FX_CORE_VER       ; $10 = FX core
        beq ?found             ; C = 1: found
        inx
        cpx #>$D700+1
        bne ?try
        clc                    ; not found
?found  rts
.endp
