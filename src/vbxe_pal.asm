; ============================================================================
; VBXE Palette Routines
; Pure register I/O -- no MEMAC B window access, so this code may live
; ABOVE $4000. Writing CB selects the next colour (CSEL + 1), so a run of
; colours needs one CSEL write. The CR/CG/CB stores are absolute, patched
; with the detected register page ($D6xx or $D7xx).
; ============================================================================

; ----------------------------------------------------------------------------
; pal_regs - Patch the CR/CG/CB store operands of both routines below
; ----------------------------------------------------------------------------
.proc pal_regs
        lda zp_vbxe_base+1     ; register page (base low byte is 0)
        sta setup_palette.st_r+2
        sta setup_palette.st_g+2
        sta setup_palette.st_b+2
        sta setup_palette.st_lr+2
        sta setup_palette.st_lg+2
        sta setup_palette.st_lb+2
        sta vbxe_img_setpal.st_r+2
        sta vbxe_img_setpal.st_g+2
        sta vbxe_img_setpal.st_b+2
        rts
.endp

; ----------------------------------------------------------------------------
; setup_palette - Init VBXE overlay palette 1: colours 0-31 from pal_*,
; 32-95 (link colours with embedded link#) all blue
; ----------------------------------------------------------------------------
.proc setup_palette
        jsr pal_regs
        ldy #VBXE_PSEL
        lda #1
        sta (zp_vbxe_base),y
        ldy #VBXE_CSEL
        lda #0
        sta (zp_vbxe_base),y

 .if 1                          ; 2026-09-23 (6502-loops-tables-smc: index counting up to zero,
                                ; same colour order for the CSEL auto-increment)
        ldx #256-PAL_N
?lp     lda pal_r+PAL_N-256,x
st_r    sta $D600+VBXE_CR      ; (page patched)
        lda pal_g+PAL_N-256,x
st_g    sta $D600+VBXE_CG
        lda pal_b+PAL_N-256,x
st_b    sta $D600+VBXE_CB      ; CSEL + 1
        inx
        bne ?lp
 .else
        ldx #0
?lp     lda pal_r,x
st_r    sta $D600+VBXE_CR      ; (page patched)
        lda pal_g,x
st_g    sta $D600+VBXE_CG
        lda pal_b,x
st_b    sta $D600+VBXE_CB      ; CSEL + 1
        inx
        cpx #PAL_N
        bne ?lp
 .endif

        ; Palette entries $20-$5F: blue (same as COL_BLUE)
        ldx #MAX_LINKS
?lnk    lda #$00
st_lr   sta $D600+VBXE_CR
        lda #$AA
st_lg   sta $D600+VBXE_CG
        lda #$FF
st_lb   sta $D600+VBXE_CB
        dex
        bne ?lnk
        rts

; Colours 0-31 in index order:
;   0-7 text (blk wht blue org grn red gray yel), 8-11 title gradient
;   (dark blue top -> medium blue bottom), 12-15 extra text colours
;   (cyan pink ltgray lime), 16-31 ANSI CGA colours (black, red, green,
;   yellow, blue, magenta, cyan, white; then the same bright, for ESC[1m)
pal_r   dta $00, $FF, $00, $FF, $00, $FF, $88, $FF
        dta $10, $20, $30, $50
        dta $00, $FF, $BB, $88
        dta $00, $AA, $00, $AA, $00, $AA, $00, $AA, $55, $FF, $55, $FF, $55, $FF, $55, $FF
PAL_N = * - pal_r
pal_g   dta $00, $FF, $AA, $AA, $FF, $44, $88, $FF
        dta $10, $30, $60, $90
        dta $DD, $88, $BB, $FF
        dta $00, $00, $AA, $55, $00, $00, $AA, $AA, $55, $55, $FF, $FF, $55, $55, $FF, $FF
pal_b   dta $00, $FF, $FF, $00, $00, $44, $88, $00
        dta $40, $80, $C0, $FF
        dta $FF, $CC, $BB, $44
        dta $00, $00, $00, $00, $AA, $AA, $AA, $AA, $55, $55, $55, $55, $FF, $FF, $FF, $FF
        ert PAL_N<>ATTR_LINK_BASE
.endp

; ----------------------------------------------------------------------------
; vbxe_img_setpal - Set image palette (always palette 1)
; Input: zp_tmp_ptr = palette data (768 bytes, above $7FFF)
; Preserves colors 0-7 (text), writes colors 8-255 from image data
; ----------------------------------------------------------------------------
.proc vbxe_img_setpal
        jsr pal_regs
        ldy #VBXE_PSEL
        lda #1
        sta (zp_vbxe_base),y
        ldy #VBXE_CSEL
        lda #8                 ; start at color 8 (preserve text colors 0-7)
        sta (zp_vbxe_base),y

        ldy #24                ; skip the first 8 entries of the source
        ldx #256-8             ; colours 8-255
?write  lda (zp_tmp_ptr),y     ; Red
st_r    sta $D600+VBXE_CR
        iny
        bne ?g0
        inc zp_tmp_ptr+1
?g0     lda (zp_tmp_ptr),y     ; Green
st_g    sta $D600+VBXE_CG
        iny
        bne ?b0
        inc zp_tmp_ptr+1
?b0     lda (zp_tmp_ptr),y     ; Blue
st_b    sta $D600+VBXE_CB      ; CSEL + 1
        iny
        bne ?nx
        inc zp_tmp_ptr+1
?nx     dex
        bne ?write
        rts
.endp
