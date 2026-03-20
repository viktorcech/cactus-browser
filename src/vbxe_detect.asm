; ============================================================================
; VBXE Detection Module
; Base address must be $D600/$D700 (NOT $D640/$D740!)
; Registers are at offsets $40-$5F from base
; ============================================================================

.proc vbxe_detect
        ; Try $D600 first (registers at $D640-$D65F)
        lda #<$D600
        sta zp_vbxe_base
        lda #>$D600
        sta zp_vbxe_base+1

        ldy #VBXE_CORE_VER    ; Y=$40 -> reads $D600+$40 = $D640
        lda #0
        sta (zp_vbxe_base),y
        lda (zp_vbxe_base),y
        cmp #FX_CORE_VER      ; $10 = FX core
        beq ?found

        ; Try $D700 (registers at $D740-$D75F)
        lda #<$D700
        sta zp_vbxe_base
        lda #>$D700
        sta zp_vbxe_base+1

        ldy #VBXE_CORE_VER
        lda #0
        sta (zp_vbxe_base),y
        lda (zp_vbxe_base),y
        cmp #FX_CORE_VER
        beq ?found

        ; Not found
        clc
        rts

?found  sec
        rts
.endp
