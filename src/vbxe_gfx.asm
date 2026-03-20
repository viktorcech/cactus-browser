; ============================================================================
; VBXE Graphics Mode - Inline Image Display
; Mixed TMON (text) + GMON (graphics) per-scanline via XDL
; Images are 8bpp indexed color, stored in VBXE VRAM
; Based on st2vbxe by Piotr Fusik
; ============================================================================

; Image VRAM layout (after font data at $2000-$2FFF)
VRAM_IMG_BASE  = $3000         ; Image storage starts here
IMG_MAX_WIDTH  = 320           ; Max width = VBXE standard mode

; Image state variables
img_active     dta b(0)        ; 1 = image on screen
img_row        dta b(0)        ; Content row where image starts (text rows)
img_height     dta b(0)        ; Height in scanlines
img_width      dta a(0)        ; Width in bytes per scanline
img_vram       dta b(0),b(0),b(0) ; VRAM address (lo, mid, hi)
img_next_free  dta b(<VRAM_IMG_BASE),b(>VRAM_IMG_BASE),b(0)

; Write pointer for pixel streaming
; img write ptr uses zp_img_ptr ($AD-$AE) for indirect addressing
img_wr_bank    dta b(0)        ; MEMAC B bank number

; ----------------------------------------------------------------------------
; vbxe_img_reset - Reset image state for new page
; ----------------------------------------------------------------------------
.proc vbxe_img_reset
        lda #0
        sta img_active
        lda #<VRAM_IMG_BASE
        sta img_next_free
        lda #>VRAM_IMG_BASE
        sta img_next_free+1
        lda #0
        sta img_next_free+2
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_img_alloc - Reserve VRAM for image
; Input: A = height (scanlines), X/Y = width (lo/hi)
; Output: C=0 ok, C=1 out of VRAM
; ----------------------------------------------------------------------------
.proc vbxe_img_alloc
        sta img_height
        stx img_width
        sty img_width+1

        ; Copy current free ptr as image address
        ldx #2
?cp     lda img_next_free,x
        sta img_vram,x
        dex
        bpl ?cp

        ; Advance free ptr by width * height
        ; Simple: add height pages (height * 256 bytes)
        clc
        lda img_next_free+1
        adc img_height
        sta img_next_free+1
        lda img_next_free+2
        adc #0
        sta img_next_free+2

        ; Check VRAM limit (512KB = $80000, safe limit $70000)
        cmp #7
        bcs ?full
        clc
        rts
?full   sec
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_img_setpal - Set image palette
; Input: zp_tmp_ptr = palette data (256 x 3 bytes: R, G, B)
; Uses overlay palette 1 (same as text)
; Method: write CR, CG, CB - CSEL auto-increments
; ----------------------------------------------------------------------------
.proc vbxe_img_setpal
        ; Select palette 1, start at color 0
        ldy #VBXE_CSEL
        lda #0
        sta (zp_vbxe_base),y
        ldy #VBXE_PSEL
        lda #1
        sta (zp_vbxe_base),y

        ; Write 256 colors (R,G,B each)
        ldx #0
?lp     ldy #0
        lda (zp_tmp_ptr),y     ; Red
        ldy #VBXE_CR
        sta (zp_vbxe_base),y
        ldy #1
        lda (zp_tmp_ptr),y     ; Green
        ldy #VBXE_CG
        sta (zp_vbxe_base),y
        ldy #2
        lda (zp_tmp_ptr),y     ; Blue
        ldy #VBXE_CB
        sta (zp_vbxe_base),y

        ; Advance source pointer by 3
        clc
        lda zp_tmp_ptr
        adc #3
        sta zp_tmp_ptr
        bcc ?nc
        inc zp_tmp_ptr+1
?nc     inx
        bne ?lp
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_img_begin_write - Prepare to stream pixels into VRAM
; Call after vbxe_img_alloc
; ----------------------------------------------------------------------------
.proc vbxe_img_begin_write
        ; Bank = VRAM address >> 14
        lda img_vram+2         ; high byte
        asl
        asl
        sta img_wr_bank
        lda img_vram+1         ; mid byte
        rol
        rol
        and #$03
        ora img_wr_bank
        sta img_wr_bank

        ; CPU ptr = $4000 + (VRAM & $3FFF)
        lda img_vram
        sta zp_img_ptr
        lda img_vram+1
        and #$3F
        ora #$40
        sta zp_img_ptr+1

        ; Enable MEMAC B
        ldy #VBXE_MEMAC_B
        lda img_wr_bank
        ora #$80
        sta (zp_vbxe_base),y
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_img_write_byte - Write one pixel byte to VRAM
; Input: A = pixel value (palette index)
; Handles bank crossing automatically
; ----------------------------------------------------------------------------
.proc vbxe_img_write_byte
        ldy #0
        sta (zp_img_ptr),y

        ; Advance pointer
        inc zp_img_ptr
        bne ?done
        inc zp_img_ptr+1
        lda zp_img_ptr+1
        cmp #$80               ; Crossed $8000 = end of 16KB window
        bne ?done
        ; Next bank
        lda #$40
        sta zp_img_ptr+1
        inc img_wr_bank
        ldy #VBXE_MEMAC_B
        lda img_wr_bank
        ora #$80
        sta (zp_vbxe_base),y
?done   rts
.endp

; ----------------------------------------------------------------------------
; vbxe_img_end_write - Finish pixel streaming, disable MEMAC B
; ----------------------------------------------------------------------------
.proc vbxe_img_end_write
        memb_off
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_img_show - Build XDL with mixed text + image
; Input: A = text row where image starts (CONTENT_TOP to CONTENT_BOT)
; Uses img_height, img_width, img_vram from alloc
; XDL structure:
;   Entry 1: init (OVOFF) - 24 scanlines top border
;   Entry 2: TMON - text rows above image
;   Entry 3: GMON - image scanlines
;   Entry 4: TMON + END - text rows below image
; ----------------------------------------------------------------------------
.proc vbxe_img_show
        sta img_row
        lda #1
        sta img_active

        memb_on 0

        ; X = write index into XDL
        ldx #0

        ; --- Entry 1: top border + overlay init (same as setup_xdl) ---
        lda #<(XDLC_OVOFF|XDLC_MAPOFF|XDLC_RPTL|XDLC_OVADR|XDLC_CHBASE|XDLC_OVATT)
        sta MEMB_XDL,x
        inx
        lda #>(XDLC_OVOFF|XDLC_MAPOFF|XDLC_RPTL|XDLC_OVADR|XDLC_CHBASE|XDLC_OVATT)
        sta MEMB_XDL,x
        inx
        lda #24-1
        sta MEMB_XDL,x
        inx
        ; Overlay address, step, chbase, ovatt, priority
        lda #<VRAM_SCREEN
        sta MEMB_XDL,x
        inx
        lda #>VRAM_SCREEN
        sta MEMB_XDL,x
        inx
        lda #0
        sta MEMB_XDL,x
        inx
        lda #<SCR_STRIDE
        sta MEMB_XDL,x
        inx
        lda #>SCR_STRIDE
        sta MEMB_XDL,x
        inx
        lda #CHBASE_VAL
        sta MEMB_XDL,x
        inx
        lda #$11
        sta MEMB_XDL,x
        inx
        lda #$FF
        sta MEMB_XDL,x
        inx

        ; --- Entry 2: TMON text above image ---
        lda img_row
        asl
        asl
        asl                    ; img_row * 8 scanlines
        beq ?no_top
        sec
        sbc #1
        pha
        lda #<(XDLC_TMON|XDLC_RPTL)
        sta MEMB_XDL,x
        inx
        lda #>(XDLC_TMON|XDLC_RPTL)
        sta MEMB_XDL,x
        inx
        pla
        sta MEMB_XDL,x
        inx
?no_top

        ; --- Entry 3: GMON image (like st2vbxe) ---
        ; GMON + RPTL + OVADR + OVATT = $0862
        lda #<(XDLC_GMON|XDLC_RPTL|XDLC_OVADR|XDLC_OVATT)
        sta MEMB_XDL,x
        inx
        lda #>(XDLC_GMON|XDLC_RPTL|XDLC_OVADR|XDLC_OVATT)
        sta MEMB_XDL,x
        inx
        lda img_height
        sec
        sbc #1
        sta MEMB_XDL,x
        inx
        ; VRAM address (3 bytes) + width (2 bytes)
        lda img_vram
        sta MEMB_XDL,x
        inx
        lda img_vram+1
        sta MEMB_XDL,x
        inx
        lda img_vram+2
        sta MEMB_XDL,x
        inx
        lda img_width
        sta MEMB_XDL,x
        inx
        lda img_width+1
        sta MEMB_XDL,x
        inx
        ; OVATT: palette 1, normal width
        lda #$11
        sta MEMB_XDL,x
        inx
        ; Priority: overlay over everything
        lda #$FF
        sta MEMB_XDL,x
        inx

        ; --- Entry 4: TMON text below image + OVADR + END ---
        ; Remaining = (SCR_ROWS - img_row) * 8 - img_height
        lda #SCR_ROWS
        sec
        sbc img_row
        asl
        asl
        asl
        sec
        sbc img_height
        beq ?jnb
        bmi ?jnb
        jmp ?has_bottom
?jnb    jmp ?no_bottom
?has_bottom
        sec
        sbc #1
        pha

        ; Need OVADR to reset text position after graphics
        lda #<(XDLC_TMON|XDLC_RPTL|XDLC_OVADR|XDLC_CHBASE|XDLC_END)
        sta MEMB_XDL,x
        inx
        lda #>(XDLC_TMON|XDLC_RPTL|XDLC_OVADR|XDLC_CHBASE|XDLC_END)
        sta MEMB_XDL,x
        inx
        pla
        sta MEMB_XDL,x
        inx

        ; Calculate text VRAM offset for rows below image
        ; Row after image = img_row + (img_height / 8)
        lda img_height
        lsr
        lsr
        lsr                    ; / 8 = text rows used by image
        clc
        adc img_row            ; first text row after image

        ; VRAM offset = row * SCR_STRIDE
        sta zp_tmp1
        lda #0
        sta zp_tmp2
        ; Multiply by 160 (SCR_STRIDE)
        ; row * 160 = row * 128 + row * 32
        lda zp_tmp1
        asl                    ; *2
        asl                    ; *4
        asl                    ; *8
        asl                    ; *16
        asl                    ; *32
        sta zp_tmp2
        lda zp_tmp1
        lsr                    ; for *128, shift differently
        ; Calculate VRAM offset for text below image
        ; Save XDL index
        stx zp_tmp3
        ; Row after image = img_row + img_height/8
        lda img_height
        lsr
        lsr
        lsr
        clc
        adc img_row
        ; Multiply by SCR_STRIDE (160) using addition loop
        tax
        lda #0
        sta zp_tmp1
        sta zp_tmp2
        cpx #0
        beq ?zoff
?alp    clc
        lda zp_tmp1
        adc #<SCR_STRIDE
        sta zp_tmp1
        lda zp_tmp2
        adc #>SCR_STRIDE
        sta zp_tmp2
        dex
        bne ?alp
?zoff   ; Restore XDL index
        ldx zp_tmp3
        ; Write OVADR
        lda zp_tmp1
        sta MEMB_XDL,x
        inx
        lda zp_tmp2
        sta MEMB_XDL,x
        inx
        lda #0
        sta MEMB_XDL,x
        inx
        lda #<SCR_STRIDE
        sta MEMB_XDL,x
        inx
        lda #>SCR_STRIDE
        sta MEMB_XDL,x
        inx
        lda #CHBASE_VAL
        sta MEMB_XDL,x
        inx
        jmp ?done

?no_bottom
        ; No text below - just end XDL
        lda #<(XDLC_END)
        sta MEMB_XDL,x
        inx
        lda #>(XDLC_END)
        sta MEMB_XDL,x
        inx
        lda #0
        sta MEMB_XDL,x
        inx

?done   memb_off
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_img_hide - Restore text-only XDL
; ----------------------------------------------------------------------------
.proc vbxe_img_hide
        lda #0
        sta img_active
        memb_on 0              ; Enable MEMAC B for XDL write
        jsr setup_xdl          ; Rebuild original text-only XDL
        memb_off
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_test_image - Display color bar test pattern
; Press T in browser to trigger
; ----------------------------------------------------------------------------
.proc vbxe_test_image
        ; Allocate 256x64 test image
        lda #64                ; height
        ldx #0                 ; width lo (256 & $FF = 0)
        ldy #1                 ; width hi (256 >> 8 = 1)
        jsr vbxe_img_alloc
        bcc ?alloc_ok
        rts
?alloc_ok

        ; Set test palette at indices 8-15 (0-7 used by text)
        ldy #VBXE_CSEL
        lda #8
        sta (zp_vbxe_base),y
        ldy #VBXE_PSEL
        lda #1
        sta (zp_vbxe_base),y

        ; Color 0: black
        ldy #VBXE_CR
        lda #0
        sta (zp_vbxe_base),y
        ldy #VBXE_CG
        sta (zp_vbxe_base),y
        ldy #VBXE_CB
        sta (zp_vbxe_base),y

        ; Color 1: red
        ldy #VBXE_CR
        lda #$FF
        sta (zp_vbxe_base),y
        ldy #VBXE_CG
        lda #0
        sta (zp_vbxe_base),y
        ldy #VBXE_CB
        sta (zp_vbxe_base),y

        ; Color 2: green
        ldy #VBXE_CR
        lda #0
        sta (zp_vbxe_base),y
        ldy #VBXE_CG
        lda #$FF
        sta (zp_vbxe_base),y
        ldy #VBXE_CB
        lda #0
        sta (zp_vbxe_base),y

        ; Color 3: yellow
        ldy #VBXE_CR
        lda #$FF
        sta (zp_vbxe_base),y
        ldy #VBXE_CG
        lda #$FF
        sta (zp_vbxe_base),y
        ldy #VBXE_CB
        lda #0
        sta (zp_vbxe_base),y

        ; Color 4: blue
        ldy #VBXE_CR
        lda #0
        sta (zp_vbxe_base),y
        ldy #VBXE_CG
        lda #0
        sta (zp_vbxe_base),y
        ldy #VBXE_CB
        lda #$FF
        sta (zp_vbxe_base),y

        ; Color 5: magenta
        ldy #VBXE_CR
        lda #$FF
        sta (zp_vbxe_base),y
        ldy #VBXE_CG
        lda #0
        sta (zp_vbxe_base),y
        ldy #VBXE_CB
        lda #$FF
        sta (zp_vbxe_base),y

        ; Color 6: cyan
        ldy #VBXE_CR
        lda #0
        sta (zp_vbxe_base),y
        ldy #VBXE_CG
        lda #$FF
        sta (zp_vbxe_base),y
        ldy #VBXE_CB
        lda #$FF
        sta (zp_vbxe_base),y

        ; Color 7: white
        ldy #VBXE_CR
        lda #$FF
        sta (zp_vbxe_base),y
        ldy #VBXE_CG
        lda #$FF
        sta (zp_vbxe_base),y
        ldy #VBXE_CB
        lda #$FF
        sta (zp_vbxe_base),y

        ; Write pixel data: 8 vertical color bars, 10px wide each
        jsr vbxe_img_begin_write

        ldx #64                ; 64 scanlines
?row    stx zp_tmp1
        lda #0
        sta zp_tmp2            ; pixel column counter lo
        sta zp_tmp3            ; pixel column counter hi
?col    lda zp_tmp2
        lsr
        lsr
        lsr
        lsr
        lsr                    ; /32 gives 8 bars across 256px
        and #$07
        clc
        adc #8                 ; offset to palette 8-15
        jsr vbxe_img_write_byte
        inc zp_tmp2
        bne ?col               ; 256 pixels (wraps at 0)
        ldx zp_tmp1
        dex
        bne ?row

        jsr vbxe_img_end_write

        ; Show image at content row 4 (below title)
        lda #4
        jsr vbxe_img_show
        rts
.endp
