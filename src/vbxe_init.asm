; ============================================================================
; VBXE Initialization Module
; ============================================================================

.proc vbxe_init
        memb_on 0

        jsr copy_font
        jsr copy_font_inv
        jsr setup_xdl
        jsr setup_bcb

        ; Fill pattern: space + attr 0
        lda #CH_SPACE
        sta MEMB_PATTERN
        lda #0
        sta MEMB_PATTERN+1

        memb_off

        jsr setup_palette

        ; Set XDL address
        ldy #VBXE_XDL_ADR0
        lda #<VRAM_XDL
        sta (zp_vbxe_base),y
        iny
        lda #>VRAM_XDL
        sta (zp_vbxe_base),y
        iny
        lda #0
        sta (zp_vbxe_base),y

        ; Enable VBXE: XDL + XCOLOR (index 0 = transparent → shows ANTIC COLBK)
        ldy #VBXE_VCTL
        lda #VC_XDL_ENABLED | VC_XCOLOR
        sta (zp_vbxe_base),y

        ; Disable ANTIC DMA
        lda #0
        sta SDMCTL

        rts
.endp

; ----------------------------------------------------------------------------
; copy_font - Copy Atari ROM font to VBXE VRAM (MEMAC B must be on)
; Remaps internal->ASCII page order
; ----------------------------------------------------------------------------
.proc copy_font
        lda CHBAS
        sta zp_tmp1

        ldx #0
?pglp   lda zp_tmp1
        clc
        adc int2asc,x
        sta zp_tmp_ptr+1
        lda #0
        sta zp_tmp_ptr

        txa
        clc
        adc #>MEMB_FONT
        sta zp_tmp_ptr2+1
        lda #0
        sta zp_tmp_ptr2

        ldy #0
?bylp   lda (zp_tmp_ptr),y
        sta (zp_tmp_ptr2),y
        iny
        bne ?bylp

        inx
        cpx #4
        bne ?pglp
        rts

; Data AFTER code so it's not executed
int2asc dta 2, 0, 1, 3
.endp

; ----------------------------------------------------------------------------
; copy_font_inv - Create inverse font (XOR $FF)
; ----------------------------------------------------------------------------
.proc copy_font_inv
        lda #<MEMB_FONT
        sta zp_tmp_ptr
        lda #>MEMB_FONT
        sta zp_tmp_ptr+1

        lda #<(MEMB_FONT+$400)
        sta zp_tmp_ptr2
        lda #>(MEMB_FONT+$400)
        sta zp_tmp_ptr2+1

        ldx #4
?pglp   ldy #0
?bylp   lda (zp_tmp_ptr),y
        eor #$FF
        sta (zp_tmp_ptr2),y
        iny
        bne ?bylp
        inc zp_tmp_ptr+1
        inc zp_tmp_ptr2+1
        dex
        bne ?pglp
        rts
.endp

; ----------------------------------------------------------------------------
; setup_xdl - Write XDL to VRAM (MEMAC B must be on)
; ----------------------------------------------------------------------------
.proc setup_xdl
        ldx #0
?lp     lda xdl_data,x
        sta MEMB_XDL,x
        inx
        cpx #XDL_LEN
        bne ?lp
        rts

xdl_data
        ; Entry 1: top border + overlay setup
        dta a(XDLC_OVOFF | XDLC_MAPOFF | XDLC_RPTL | XDLC_OVADR | XDLC_CHBASE | XDLC_OVATT)
        dta 24-1                       ; 24 empty scanlines

        ; Overlay address (3 bytes)
        dta <VRAM_SCREEN, >VRAM_SCREEN, 0

        ; Overlay step
        dta a(SCR_STRIDE)

        ; CHBASE
        dta CHBASE_VAL

        ; OVATT: palette 1 for overlay
        dta %00010001

        ; Priority
        dta $FF

        ; Entry 2: text area
        dta a(XDLC_TMON | XDLC_RPTL | XDLC_END)
        dta SCR_ROWS * 8 - 1          ; 191 scanlines

XDL_LEN = * - xdl_data
.endp

; ----------------------------------------------------------------------------
; setup_bcb - Write blitter command blocks to VRAM
; ----------------------------------------------------------------------------
.proc setup_bcb
        ldx #0
?lp     lda bcb_data,x
        sta MEMB_BCB,x
        inx
        cpx #BCB_DATA_LEN
        bne ?lp
        rts

bcb_data

; BCB 0: Clear screen (21 bytes, offset 0)
        ; Source: fill pattern
        dta <VRAM_PATTERN, >VRAM_PATTERN, 0
        dta a(0)                       ; Source step Y = 0
        dta 1                          ; Source step X
        ; Dest: screen
        dta <VRAM_SCREEN, >VRAM_SCREEN, 0
        dta a(SCR_STRIDE)              ; Dest step Y
        dta 1                          ; Dest step X
        dta a(SCR_STRIDE - 1)          ; Width - 1
        dta SCR_ROWS - 1              ; Height - 1
        dta $FF                        ; AND mask
        dta $00                        ; XOR mask
        dta $00                        ; Collision
        dta 0                          ; Zoom
        dta $81                        ; Pattern: 2-byte repeat
        dta $00                        ; Control: normal

; BCB 1: Scroll up (offset 21)
        ; Source: row 1
        dta <(VRAM_SCREEN + SCR_STRIDE), >(VRAM_SCREEN + SCR_STRIDE), 0
        dta a(SCR_STRIDE)
        dta 1
        ; Dest: row 0
        dta <VRAM_SCREEN, >VRAM_SCREEN, 0
        dta a(SCR_STRIDE)
        dta 1
        dta a(SCR_STRIDE - 1)
        dta SCR_ROWS - 2              ; Copy 23 rows
        dta $FF
        dta $00
        dta $00
        dta 0
        dta $00
        dta $08                        ; Control: chain to next BCB

; BCB 2: Clear last row after scroll (offset 42)
        ; Source: fill pattern
        dta <VRAM_PATTERN, >VRAM_PATTERN, 0
        dta a(0)
        dta 1
        ; Dest: last row
        dta <(VRAM_SCREEN + (SCR_ROWS-1) * SCR_STRIDE)
        dta >(VRAM_SCREEN + (SCR_ROWS-1) * SCR_STRIDE)
        dta 0
        dta a(SCR_STRIDE)
        dta 1
        dta a(SCR_STRIDE - 1)
        dta 0                          ; 1 row
        dta $FF
        dta $00
        dta $00
        dta 0
        dta $81                        ; Pattern
        dta $00                        ; Control: normal

; BCB 3: Scroll content area only (rows 2-22), offset 63
        ; Source: row CONTENT_TOP+1 (row 3)
        dta <(VRAM_SCREEN + (CONTENT_TOP+1) * SCR_STRIDE)
        dta >(VRAM_SCREEN + (CONTENT_TOP+1) * SCR_STRIDE)
        dta 0
        dta a(SCR_STRIDE)
        dta 1
        ; Dest: row CONTENT_TOP (row 2)
        dta <(VRAM_SCREEN + CONTENT_TOP * SCR_STRIDE)
        dta >(VRAM_SCREEN + CONTENT_TOP * SCR_STRIDE)
        dta 0
        dta a(SCR_STRIDE)
        dta 1
        dta a(SCR_STRIDE - 1)
        dta CONTENT_BOT - CONTENT_TOP - 1  ; 19 = copy 20 rows (3→2 .. 22→21)
        dta $FF
        dta $00
        dta $00
        dta 0
        dta $00
        dta $08                        ; Control: chain to next BCB

; BCB 4: Clear last content row (row 22), offset 84
        dta <VRAM_PATTERN, >VRAM_PATTERN, 0
        dta a(0)
        dta 1
        dta <(VRAM_SCREEN + CONTENT_BOT * SCR_STRIDE)
        dta >(VRAM_SCREEN + CONTENT_BOT * SCR_STRIDE)
        dta 0
        dta a(SCR_STRIDE)
        dta 1
        dta a(SCR_STRIDE - 1)
        dta 0                          ; 1 row
        dta $FF
        dta $00
        dta $00
        dta 0
        dta $81                        ; Pattern: 2-byte repeat
        dta $00                        ; Control: normal (end)

BCB_DATA_LEN = * - bcb_data
.endp

BCB_CLS_OFS    = 0
BCB_SCROLL_OFS = 21
BCB_CLRLAST_OFS = 42
BCB_CONTENT_SCROLL_OFS = 63

; ----------------------------------------------------------------------------
; setup_palette - Init VBXE overlay palette 1 (8 colors)
; ----------------------------------------------------------------------------
.proc setup_palette
        ldy #VBXE_PSEL
        lda #1
        sta (zp_vbxe_base),y

        ldy #VBXE_CSEL
        lda #0
        sta (zp_vbxe_base),y

        ldx #0
?lp     ldy #VBXE_CR
        lda pal_r,x
        sta (zp_vbxe_base),y
        iny
        lda pal_g,x
        sta (zp_vbxe_base),y
        iny
        lda pal_b,x
        sta (zp_vbxe_base),y

        ; Increment CSEL manually
        ldy #VBXE_CSEL
        txa
        clc
        adc #1
        sta (zp_vbxe_base),y

        inx
        cpx #8
        bne ?lp
        rts

;            blk  wht  blue org  grn  red  gray yel
pal_r dta   $00, $FF, $00, $FF, $00, $FF, $88, $FF
pal_g dta   $00, $FF, $AA, $AA, $FF, $44, $88, $FF
pal_b dta   $00, $FF, $FF, $00, $00, $44, $88, $00
.endp
