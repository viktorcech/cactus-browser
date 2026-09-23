; ============================================================================
; VBXE Initialization Module
; ============================================================================

.proc vbxe_init
 .if 1                          ; 2026-09-23 (vbxe-blitter: no fill pattern any more, the gradient
                                ; BCB is set up once here)
        memb_on 0

        jsr copy_font
        jsr copy_font_inv
        jsr setup_xdl
        jsr setup_bcb
        jsr setup_grad_bcb

        memb_off

        jsr setup_palette

        ; Set XDL address (VRAM_XDL low byte is 0)
        ldy #VBXE_XDL_ADR0
        lda #<VRAM_XDL
        sta (zp_vbxe_base),y
        iny
        lda #>VRAM_XDL
        sta (zp_vbxe_base),y
        iny
        lda #0
        sta (zp_vbxe_base),y

        ; Enable VBXE: XDL + XCOLOR (index 0 = transparent ??? shows ANTIC COLBK)
        ldy #VBXE_VCTL
        lda #VC_XDL_ENABLED | VC_XCOLOR
        sta (zp_vbxe_base),y

        ; Disable ANTIC DMA
        lda #0
        sta SDMCTL

        rts
 .else
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

        ; Enable VBXE: XDL + XCOLOR (index 0 = transparent ??? shows ANTIC COLBK)
        ldy #VBXE_VCTL
        lda #VC_XDL_ENABLED | VC_XCOLOR
        sta (zp_vbxe_base),y

        ; Disable ANTIC DMA
        lda #0
        sta SDMCTL

        rts
 .endif
.endp

; ----------------------------------------------------------------------------
; copy_font - Copy Atari ROM font to VBXE VRAM (MEMAC B must be on)
; Remaps internal->ASCII page order
; ----------------------------------------------------------------------------
.proc copy_font
 .if 1                          ; 2026-09-23 (6502-loops-tables-smc: absolute SMC source/dest pages,
                                ; 14 cycles a byte instead of 16; count down)
        ldx #3
?pglp   lda CHBAS              ; source page = CHBAS + int2asc[X]
        clc
        adc int2asc,x
        sta ?src+2
        txa                    ; dest page = MEMB_FONT page + X (C = 0)
        adc #>MEMB_FONT
        sta ?dst+2
        ldy #0
?src    lda $FF00,y            ; (pages patched)
?dst    sta $FF00,y
        iny
        bne ?src
        dex
        bpl ?pglp
        rts

; Data AFTER code so it's not executed
int2asc dta 2, 0, 1, 3
 .else
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
 .endif
.endp

; ----------------------------------------------------------------------------
; copy_font_inv - Create inverse font (XOR $FF)
; ----------------------------------------------------------------------------
.proc copy_font_inv
 .if 1                          ; 2026-09-23 (6502-loops-tables-smc: absolute SMC pages; count down)
        ldx #3
?pglp   txa
        clc
        adc #>MEMB_FONT
        sta ?src+2
        adc #4                 ; C = 0: +$400
        sta ?dst+2
        ldy #0
?src    lda $FF00,y            ; (pages patched)
        eor #$FF
?dst    sta $FF00,y
        iny
        bne ?src
        dex
        bpl ?pglp
        rts
 .else
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
 .endif
.endp

; ----------------------------------------------------------------------------
; setup_xdl - Write XDL to VRAM (MEMAC B must be on)
; ----------------------------------------------------------------------------
.proc setup_xdl
 .if 1                          ; 2026-09-23 (6502-idioms: count down, no cpx)
        ldx #XDL_LEN-1
?lp     lda xdl_data,x
        sta MEMB_XDL,x
        dex
        bpl ?lp
        rts
 .else
        ldx #0
?lp     lda xdl_data,x
        sta MEMB_XDL,x
        inx
        cpx #XDL_LEN
        bne ?lp
        rts
 .endif

xdl_data
        ; Entry 1: top border (8 scanlines for CRT overscan)
        ; Initialize overlay params but display off (OVOFF)
        dta a(XDLC_OVOFF | XDLC_MAPOFF | XDLC_RPTL | XDLC_OVADR | XDLC_CHBASE | XDLC_OVATT)
        dta 8-1                        ; 8 blank scanlines
        dta <VRAM_SCREEN, >VRAM_SCREEN, 0
        dta a(SCR_STRIDE)
        dta CHBASE_VAL
        dta %00010001                  ; palette 1, NORMAL width
        dta $FF                        ; priority

        ; Entry 2: text mode (29 rows = 232 scanlines)
        ; Re-set OVADR to row 0 (OVOFF advanced it during border)
        dta a(XDLC_TMON | XDLC_MAPOFF | XDLC_RPTL | XDLC_OVADR | XDLC_END)
        dta SCR_ROWS * 8 - 1          ; 231 scanlines
        dta <VRAM_SCREEN, >VRAM_SCREEN, 0
        dta a(SCR_STRIDE)

XDL_LEN = * - xdl_data
.endp

; ----------------------------------------------------------------------------
; setup_bcb - Write blitter command blocks to VRAM
; ----------------------------------------------------------------------------
.proc setup_bcb
 .if 1                          ; 2026-09-23 (6502-idioms: count down, no cpx)
        ldx #BCB_DATA_LEN      ; <= 256 bytes
?lp     lda bcb_data-1,x
        sta MEMB_BCB-1,x
        dex
        bne ?lp
        rts
 .else
        ldx #0
?lp     lda bcb_data,x
        sta MEMB_BCB,x
        inx
        cpx #BCB_DATA_LEN
        bne ?lp
        rts
 .endif

 .if 1                          ; 2026-09-23 (vbxe-blitter: every fill a constant fill, AND 0 / XOR
                                ; value, 1 cycle a byte: cls, scroll row, row fill, content clear).
                                ; Pairs with vbxe_cls/fill_row/ui_clear_content: flip together
bcb_data

; BCB 0: clear screen, characters (offset 0)
        dta 0, 0, 0, a(0), 0           ; source unused (AND = 0)
        dta <(VRAM_SCREEN), >(VRAM_SCREEN), 0
        dta a(SCR_STRIDE)              ; dest step Y
        dta 2                          ; dest step X: every other byte
        dta a(SCR_COLS - 1)            ; width - 1
        dta SCR_ROWS - 1                 ; height - 1
        dta $00, CH_SPACE, $00, 0, $00    ; AND 0, XOR = value: constant fill
        dta $08
; BCB 1: clear screen, attributes
        dta 0, 0, 0, a(0), 0           ; source unused (AND = 0)
        dta <(VRAM_SCREEN+1), >(VRAM_SCREEN+1), 0
        dta a(SCR_STRIDE)              ; dest step Y
        dta 2                          ; dest step X: every other byte
        dta a(SCR_COLS - 1)            ; width - 1
        dta SCR_ROWS - 1                 ; height - 1
        dta $00, COL_BLACK, $00, 0, $00    ; AND 0, XOR = value: constant fill
        dta $00
; BCB 2: Scroll up (offset 42): rows 1..28 -> 0..27
        dta <(VRAM_SCREEN + SCR_STRIDE), >(VRAM_SCREEN + SCR_STRIDE), 0
        dta a(SCR_STRIDE)
        dta 1
        dta <VRAM_SCREEN, >VRAM_SCREEN, 0
        dta a(SCR_STRIDE)
        dta 1
        dta a(SCR_STRIDE - 1)
        dta SCR_ROWS - 2
        dta $FF, $00, $00, 0, $00
        dta $08                        ; chain: clear the last row
; BCB 3: last row, characters
        dta 0, 0, 0, a(0), 0           ; source unused (AND = 0)
        dta <(VRAM_SCREEN + (SCR_ROWS-1) * SCR_STRIDE), >(VRAM_SCREEN + (SCR_ROWS-1) * SCR_STRIDE), 0
        dta a(SCR_STRIDE)              ; dest step Y
        dta 2                          ; dest step X: every other byte
        dta a(SCR_COLS - 1)            ; width - 1
        dta 1 - 1                 ; height - 1
        dta $00, CH_SPACE, $00, 0, $00    ; AND 0, XOR = value: constant fill
        dta $08
; BCB 4: last row, attributes
        dta 0, 0, 0, a(0), 0           ; source unused (AND = 0)
        dta <(VRAM_SCREEN + (SCR_ROWS-1) * SCR_STRIDE + 1), >(VRAM_SCREEN + (SCR_ROWS-1) * SCR_STRIDE + 1), 0
        dta a(SCR_STRIDE)              ; dest step Y
        dta 2                          ; dest step X: every other byte
        dta a(SCR_COLS - 1)            ; width - 1
        dta 1 - 1                 ; height - 1
        dta $00, COL_BLACK, $00, 0, $00    ; AND 0, XOR = value: constant fill
        dta $00
; BCB 5: fill one row, characters (offset 105; dest set per fill)
        dta 0, 0, 0, a(0), 0           ; source unused (AND = 0)
        dta <(VRAM_SCREEN), >(VRAM_SCREEN), 0
        dta a(SCR_STRIDE)              ; dest step Y
        dta 2                          ; dest step X: every other byte
        dta a(SCR_COLS - 1)            ; width - 1
        dta 1 - 1                 ; height - 1
        dta $00, CH_SPACE, $00, 0, $00    ; AND 0, XOR = value: constant fill
        dta $08
; BCB 6: fill one row, attributes (dest + XOR colour set per fill)
        dta 0, 0, 0, a(0), 0           ; source unused (AND = 0)
        dta <(VRAM_SCREEN+1), >(VRAM_SCREEN+1), 0
        dta a(SCR_STRIDE)              ; dest step Y
        dta 2                          ; dest step X: every other byte
        dta a(SCR_COLS - 1)            ; width - 1
        dta 1 - 1                 ; height - 1
        dta $00, COL_BLACK, $00, 0, $00    ; AND 0, XOR = value: constant fill
        dta $00
; BCB 7: clear content rows, characters (offset 147)
        dta 0, 0, 0, a(0), 0           ; source unused (AND = 0)
        dta <(VRAM_SCREEN + CONTENT_TOP * SCR_STRIDE), >(VRAM_SCREEN + CONTENT_TOP * SCR_STRIDE), 0
        dta a(SCR_STRIDE)              ; dest step Y
        dta 2                          ; dest step X: every other byte
        dta a(SCR_COLS - 1)            ; width - 1
        dta CONTENT_BOT - CONTENT_TOP + 1 - 1                 ; height - 1
        dta $00, CH_SPACE, $00, 0, $00    ; AND 0, XOR = value: constant fill
        dta $08
; BCB 8: clear content rows, attributes
        dta 0, 0, 0, a(0), 0           ; source unused (AND = 0)
        dta <(VRAM_SCREEN + CONTENT_TOP * SCR_STRIDE + 1), >(VRAM_SCREEN + CONTENT_TOP * SCR_STRIDE + 1), 0
        dta a(SCR_STRIDE)              ; dest step Y
        dta 2                          ; dest step X: every other byte
        dta a(SCR_COLS - 1)            ; width - 1
        dta CONTENT_BOT - CONTENT_TOP + 1 - 1                 ; height - 1
        dta $00, COL_BLACK, $00, 0, $00    ; AND 0, XOR = value: constant fill
        dta $00

BCB_DATA_LEN = * - bcb_data
        ert VRAM_BCB+BCB_DATA_LEN > VRAM_GRAD
        ert BCB_DATA_LEN > 256
 .else
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

BCB_DATA_LEN = * - bcb_data
 .endif
.endp

 .if 1                          ; 2026-09-23 (vbxe-blitter: offsets of the table above)
BCB_CLS_OFS     = 0
BCB_SCROLL_OFS  = 42
BCB_ROW_OFS     = 105
BCB_CONTENT_OFS = 147
 .else
BCB_CLS_OFS    = 0
BCB_SCROLL_OFS = 21
 .endif

 .if 1                          ; 2026-09-23 (vbxe-blitter: constant fills, see setup_grad_bcb)
BCB_GRAD_OFS    = VRAM_GRAD_BCB-VRAM_BCB
 .else
BCB_GRAD_OFS    = VRAM_GRAD+4-VRAM_BCB   ; after the 4 colour bytes
 .endif

; ----------------------------------------------------------------------------
; setup_grad_bcb - Title gradient colours + BCB at VRAM_GRAD (after the text
; BCBs). One blit fills the 4 bands: the source steps one colour byte per
; row (step Y 1) and repeats it along the row (step X 0).
; ----------------------------------------------------------------------------
.proc setup_grad_bcb
 .if 1                          ; 2026-09-23 (vbxe-blitter: a constant fill is AND 0 / XOR colour,
                                ; 1 cycle a byte: 4 x (320+22) = 1368 blitter cycles against
                                ; 4 x (320+320) + 21 = 2581 for the copy from a colour column)
        ldx #GRAD_DATA_LEN-1
?lp     lda grad_data,x
        sta MEMB_BASE+VRAM_GRAD_BCB,x
        dex
        bpl ?lp
        rts

grad_data                       ; top (dark) to bottom, palette indices 8-11
        dta 0, 0, 0, a(0), 0           ; band 0: source unused (AND = 0)
        dta <(VRAM_GRADIENT+GRAD_BAND_W*0), >(VRAM_GRADIENT+GRAD_BAND_W*0), 0
        dta a(GRAD_BAND_W), 1
        dta a(GRAD_BAND_W - 1), 0      ; width - 1 (9 bits), one row
        dta $00, 8, $00, 0, $00        ; AND 0, XOR = palette index
        dta $08
        dta 0, 0, 0, a(0), 0           ; band 1: source unused (AND = 0)
        dta <(VRAM_GRADIENT+GRAD_BAND_W*1), >(VRAM_GRADIENT+GRAD_BAND_W*1), 0
        dta a(GRAD_BAND_W), 1
        dta a(GRAD_BAND_W - 1), 0      ; width - 1 (9 bits), one row
        dta $00, 9, $00, 0, $00        ; AND 0, XOR = palette index
        dta $08
        dta 0, 0, 0, a(0), 0           ; band 2: source unused (AND = 0)
        dta <(VRAM_GRADIENT+GRAD_BAND_W*2), >(VRAM_GRADIENT+GRAD_BAND_W*2), 0
        dta a(GRAD_BAND_W), 1
        dta a(GRAD_BAND_W - 1), 0      ; width - 1 (9 bits), one row
        dta $00, 10, $00, 0, $00        ; AND 0, XOR = palette index
        dta $08
        dta 0, 0, 0, a(0), 0           ; band 3: source unused (AND = 0)
        dta <(VRAM_GRADIENT+GRAD_BAND_W*3), >(VRAM_GRADIENT+GRAD_BAND_W*3), 0
        dta a(GRAD_BAND_W), 1
        dta a(GRAD_BAND_W - 1), 0      ; width - 1 (9 bits), one row
        dta $00, 11, $00, 0, $00        ; AND 0, XOR = palette index
        dta $00
hline_bcb                       ; vbxe_hline: chars, then attributes; dest,
        dta 0, 0, 0, a(0), 0           ; width and XOR written per line
        dta 0, 0, 0
        dta a(SCR_STRIDE), 2
        dta a(0), 0                    ; width - 1, one row
        dta $00, $00, $00, 0, $00      ; AND 0, XOR = char: constant fill
        dta $08
        dta 0, 0, 0, a(0), 0
        dta 0, 0, 0
        dta a(SCR_STRIDE), 2
        dta a(0), 0
        dta $00, $00, $00, 0, $00      ; XOR = attribute
        dta $00
GRAD_DATA_LEN = * - grad_data
        ert GRAD_DATA_LEN > 128
        ert VRAM_GRAD_BCB+GRAD_DATA_LEN > VRAM_FONT
        ert VRAM_GRAD_BCB + hline_bcb - grad_data <> VRAM_HLINE_BCB
 .else
        ldx #GRAD_DATA_LEN-1
?lp     lda grad_data,x
        sta MEMB_BASE+VRAM_GRAD,x
        dex
        bpl ?lp
        rts

grad_data
        dta 8, 9, 10, 11               ; palette indices, top (dark) to bottom
        dta <VRAM_GRAD, >VRAM_GRAD, 0
        dta a(1)                       ; source step Y: next colour per row
        dta 0                          ; source step X: repeat it
        dta <VRAM_GRADIENT, >VRAM_GRADIENT, 0
        dta a(GRAD_BAND_W)             ; dest step Y
        dta 1
        dta a(GRAD_BAND_W - 1)         ; width - 1 (9 bits)
        dta GRAD_BANDS - 1
        dta $FF, $00, $00, 0, $00, $00
GRAD_DATA_LEN = * - grad_data
        ert VRAM_GRAD+GRAD_DATA_LEN > VRAM_XDL
 .endif
.endp

; setup_palette moved to vbxe_pal.asm (register I/O only, no MEMAC B needed)
