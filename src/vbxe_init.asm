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

BCB_DATA_LEN = * - bcb_data
.endp

BCB_CLS_OFS    = 0
BCB_SCROLL_OFS = 21

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

        ; --- Gradient palette (indices 8-11) for title banner ---
        ; CSEL=8 here (from main loop above)
        ldx #0
?grad   ldy #VBXE_CR
        lda grad_pal_r,x
        sta (zp_vbxe_base),y
        iny
        lda grad_pal_g,x
        sta (zp_vbxe_base),y
        iny
        lda grad_pal_b,x
        sta (zp_vbxe_base),y

        ldy #VBXE_CSEL
        txa
        clc
        adc #9
        sta (zp_vbxe_base),y

        inx
        cpx #4
        bne ?grad

        ; --- Extra text colors (indices 12-15) ---
        ; CSEL=12 here (from gradient loop: 3+9=12)
        ldx #0
?ext    ldy #VBXE_CR
        lda ext_pal_r,x
        sta (zp_vbxe_base),y
        iny
        lda ext_pal_g,x
        sta (zp_vbxe_base),y
        iny
        lda ext_pal_b,x
        sta (zp_vbxe_base),y

        ldy #VBXE_CSEL
        txa
        clc
        adc #13
        sta (zp_vbxe_base),y

        inx
        cpx #4
        bne ?ext

        ; --- ANSI color palette (indices $10-$1F, 16 colors) ---
        ldy #VBXE_CSEL
        lda #ATTR_ANSI_BASE
        sta (zp_vbxe_base),y

        ldx #0
?ansi   ldy #VBXE_CR
        lda ansi_pal_r,x
        sta (zp_vbxe_base),y
        iny
        lda ansi_pal_g,x
        sta (zp_vbxe_base),y
        iny
        lda ansi_pal_b,x
        sta (zp_vbxe_base),y

        ldy #VBXE_CSEL
        txa
        clc
        adc #ATTR_ANSI_BASE+1
        sta (zp_vbxe_base),y

        inx
        cpx #16
        bne ?ansi

        ; Set palette entries $20-$3F to blue (link colors with embedded link#)
        ldy #VBXE_CSEL
        lda #ATTR_LINK_BASE
        sta (zp_vbxe_base),y

        ldx #0
?lnk    ldy #VBXE_CR
        lda #$00               ; R = same as COL_BLUE
        sta (zp_vbxe_base),y
        iny
        lda #$AA               ; G
        sta (zp_vbxe_base),y
        iny
        lda #$FF               ; B
        sta (zp_vbxe_base),y

        ; Set CSEL to next entry
        ldy #VBXE_CSEL
        txa
        clc
        adc #ATTR_LINK_BASE+1
        sta (zp_vbxe_base),y

        inx
        cpx #64
        bne ?lnk
        rts

;            blk  wht  blue org  grn  red  gray yel
pal_r dta   $00, $FF, $00, $FF, $00, $FF, $88, $FF
pal_g dta   $00, $FF, $AA, $AA, $FF, $44, $88, $FF
pal_b dta   $00, $FF, $FF, $00, $00, $44, $88, $00

;            cyan  pink  ltgray lime
ext_pal_r dta $00,  $FF,  $BB,  $88
ext_pal_g dta $DD,  $88,  $BB,  $FF
ext_pal_b dta $FF,  $CC,  $BB,  $44

; Gradient: dark blue (top) -> medium blue (bottom)
grad_pal_r dta $10, $20, $30, $50
grad_pal_g dta $10, $30, $60, $90
grad_pal_b dta $40, $80, $C0, $FF

; ANSI CGA colors at palette indices $10-$1F
; Standard 8 colors ($10-$17): black, red, green, yellow, blue, magenta, cyan, white
; Bright 8 colors ($18-$1F): same order, higher intensity (used with ESC[1m bold)
; Values match IBM CGA/EGA palette for correct ANSI art rendering
;              blk  red  grn  yel  blu  mag  cyn  wht  Bblk Bred Bgrn Byel Bblu Bmag Bcyn Bwht
ansi_pal_r dta $00, $AA, $00, $AA, $00, $AA, $00, $AA, $55, $FF, $55, $FF, $55, $FF, $55, $FF
ansi_pal_g dta $00, $00, $AA, $55, $00, $00, $AA, $AA, $55, $55, $FF, $FF, $55, $55, $FF, $FF
ansi_pal_b dta $00, $00, $00, $00, $AA, $AA, $AA, $AA, $55, $55, $55, $55, $FF, $FF, $FF, $FF
.endp
