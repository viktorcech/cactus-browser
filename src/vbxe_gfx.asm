; ============================================================================
; VBXE Graphics Mode - Fullscreen Image Display
; Single image at a time, 8bpp indexed color, stored in VBXE VRAM
; Images shown fullscreen one by one after page loads
; ============================================================================

; Image VRAM layout (after font data at $2000-$2FFF)
VRAM_IMG_BASE  = $3000         ; Image storage starts here

; Image state
img_active     dta b(0)        ; 1 = image on screen

; Working variables for current image
img_height     dta b(0)
img_vram       dta b(0),b(0),b(0)

; Write pointer for pixel streaming
img_wr_bank    dta b(0)        ; MEMAC B bank number

; ----------------------------------------------------------------------------
; vbxe_img_alloc - Allocate VRAM for image (always at VRAM_IMG_BASE)
; Input: A=height, X=width lo, Y=width hi
; Output: C=0 ok, img_vram/img_height set
; ----------------------------------------------------------------------------
.proc vbxe_img_alloc
        sta img_height
        ; Always start at VRAM_IMG_BASE (overwrite previous image)
        lda #<VRAM_IMG_BASE
        sta img_vram
        lda #>VRAM_IMG_BASE
        sta img_vram+1
        lda #0
        sta img_vram+2
        clc
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_img_begin_write - Initialize write pointer for current image
; Uses img_vram (set by alloc)
; ----------------------------------------------------------------------------
.proc vbxe_img_begin_write
        ; Bank = VRAM address >> 14
        ; = (vram+2 << 2) | (vram+1 >> 6)
        lda img_vram+2         ; high byte (bits 16-23)
        asl
        asl
        sta img_wr_bank        ; bits 18+ in positions 2+
        lda img_vram+1         ; mid byte (bits 8-15)
        asl                    ; bit 15 -> carry
        rol img_wr_bank        ; carry -> bank bit 0
        asl                    ; bit 14 -> carry
        rol img_wr_bank        ; carry -> bank bit 1

        ; CPU ptr = $4000 + (VRAM & $3FFF)
        lda img_vram
        sta zp_img_ptr
        lda img_vram+1
        and #$3F
        ora #$40
        sta zp_img_ptr+1
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_img_write_chunk - Copy rx_buffer to VRAM, handles MEMAC B safely
; Input: zp_rx_len = number of bytes in rx_buffer
; ----------------------------------------------------------------------------
.proc vbxe_img_write_chunk
        lda zp_rx_len
        beq ?done

        sei
        lda img_wr_bank
        ora #$80
        sta zp_memb_shadow     ; shadow FIRST (VBI is NMI, can't mask!)
        ldy #VBXE_MEMAC_B
        sta (zp_vbxe_base),y

        ldx #0
?lp     ldy #0
        lda rx_buffer,x
        sta (zp_img_ptr),y
        inc zp_img_ptr
        bne ?nc
        inc zp_img_ptr+1
        lda zp_img_ptr+1
        cmp #$80
        bne ?nc
        lda #$40
        sta zp_img_ptr+1
        inc img_wr_bank
        lda img_wr_bank
        ora #$80
        sta zp_memb_shadow     ; shadow FIRST
        ldy #VBXE_MEMAC_B
        sta (zp_vbxe_base),y
?nc     inx
        cpx zp_rx_len
        bne ?lp
        memb_off
        cli
?done   rts
.endp

; ----------------------------------------------------------------------------
; vbxe_img_write_big - Copy img_big_buf to VRAM, 16-bit count
; Companion to fn_read_img: handles large (up to 2KB) chunks that
; fn_read_img deposits into img_big_buf. Uses 16-bit byte counter
; instead of 8-bit zp_rx_len used by vbxe_img_write_chunk.
;
; Input: img_chunk_lo/hi = byte count, zp_img_ptr/img_wr_bank set
; Source: img_big_buf (at $B724, above $7FFF — unaffected by MEMAC B)
; Dest: VBXE VRAM via MEMAC B window ($4000-$7FFF)
; MUST be below $4000 (executes with MEMAC B active)
; Auto-switches VRAM banks when write pointer crosses $8000 boundary
; ----------------------------------------------------------------------------
.proc vbxe_img_write_big
        lda img_chunk_lo
        ora img_chunk_hi
        beq ?done

        ; Set source pointer
        lda #<img_big_buf
        sta zp_tmp_ptr
        lda #>img_big_buf
        sta zp_tmp_ptr+1

        sei
        lda img_wr_bank
        ora #$80
        sta zp_memb_shadow     ; shadow FIRST (VBI is NMI!)
        ldy #VBXE_MEMAC_B
        sta (zp_vbxe_base),y

?lp     ldy #0
        lda (zp_tmp_ptr),y    ; read from RAM (above $7FFF, safe)
        sta (zp_img_ptr),y    ; write to VRAM via MEMAC B

        ; Advance source
        inc zp_tmp_ptr
        bne ?ns
        inc zp_tmp_ptr+1
?ns
        ; Advance VRAM dest (bank switch on $8000 boundary)
        inc zp_img_ptr
        bne ?nc
        inc zp_img_ptr+1
        lda zp_img_ptr+1
        cmp #$80
        bne ?nc
        lda #$40
        sta zp_img_ptr+1
        inc img_wr_bank
        lda img_wr_bank
        ora #$80
        sta zp_memb_shadow
        ldy #VBXE_MEMAC_B
        sta (zp_vbxe_base),y
?nc
        ; Decrement 16-bit counter
        lda img_chunk_lo
        bne ?dl
        dec img_chunk_hi
?dl     dec img_chunk_lo
        lda img_chunk_lo
        ora img_chunk_hi
        bne ?lp

        memb_off
        cli
?done   rts
.endp

; ============================================================================
; Page Buffer - VRAM storage for downloaded HTML pages
; Download entire page to VRAM, then render from VRAM (N1: free for images)
; ALL page buffer code MUST be below $4000 (uses MEMAC B)
; ============================================================================

; Page buffer state variables
pb_wr_bank     dta b(0)        ; MEMAC B bank for writing
pb_rd_bank     dta b(0)        ; MEMAC B bank for reading
pb_total       dta b(0),b(0),b(0)   ; 24-bit total bytes buffered
pb_read        dta b(0),b(0),b(0)   ; 24-bit bytes read so far

; ----------------------------------------------------------------------------
; vbxe_pb_init_write - Initialize page buffer write pointer
; ----------------------------------------------------------------------------
.proc vbxe_pb_init_write
        lda #PAGE_BUF_BANK
        sta pb_wr_bank
        lda #<MEMB_BASE
        sta zp_pb_wr_ptr
        lda #>MEMB_BASE
        sta zp_pb_wr_ptr+1
        lda #0
        sta pb_total
        sta pb_total+1
        sta pb_total+2
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_pb_init_read - Initialize page buffer read pointer
; ----------------------------------------------------------------------------
.proc vbxe_pb_init_read
        lda #PAGE_BUF_BANK
        sta pb_rd_bank
        lda #<MEMB_BASE
        sta zp_pb_rd_ptr
        lda #>MEMB_BASE
        sta zp_pb_rd_ptr+1
        lda #0
        sta pb_read
        sta pb_read+1
        sta pb_read+2
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_pb_write_chunk - Copy rx_buffer to VRAM page buffer
; Input: zp_rx_len = number of bytes in rx_buffer
; Pattern identical to vbxe_img_write_chunk
; ----------------------------------------------------------------------------
.proc vbxe_pb_write_chunk
        lda zp_rx_len
        beq ?done

        sei
        lda pb_wr_bank
        ora #$80
        sta zp_memb_shadow     ; shadow FIRST (VBI is NMI!)
        ldy #VBXE_MEMAC_B
        sta (zp_vbxe_base),y

        ldx #0
?lp     ldy #0
        lda rx_buffer,x
        sta (zp_pb_wr_ptr),y
        inc zp_pb_wr_ptr
        bne ?nc
        inc zp_pb_wr_ptr+1
        lda zp_pb_wr_ptr+1
        cmp #$80
        bne ?nc
        lda #$40
        sta zp_pb_wr_ptr+1
        inc pb_wr_bank
        lda pb_wr_bank
        ora #$80
        sta zp_memb_shadow     ; shadow FIRST
        ldy #VBXE_MEMAC_B
        sta (zp_vbxe_base),y
?nc     inx
        cpx zp_rx_len
        bne ?lp
        memb_off
        cli
?done   rts
.endp

; ----------------------------------------------------------------------------
; vbxe_pb_read_chunk - Copy VRAM page buffer to rx_buffer
; Input: A = number of bytes to read (max 255)
; Output: zp_rx_len = bytes read, rx_buffer filled
; ----------------------------------------------------------------------------
.proc vbxe_pb_read_chunk
        sta zp_rx_len
        beq ?done

        sei
        lda pb_rd_bank
        ora #$80
        sta zp_memb_shadow     ; shadow FIRST (VBI is NMI!)
        ldy #VBXE_MEMAC_B
        sta (zp_vbxe_base),y

        ldx #0
?lp     ldy #0
        lda (zp_pb_rd_ptr),y
        sta rx_buffer,x
        inc zp_pb_rd_ptr
        bne ?nc
        inc zp_pb_rd_ptr+1
        lda zp_pb_rd_ptr+1
        cmp #$80
        bne ?nc
        lda #$40
        sta zp_pb_rd_ptr+1
        inc pb_rd_bank
        lda pb_rd_bank
        ora #$80
        sta zp_memb_shadow     ; shadow FIRST
        ldy #VBXE_MEMAC_B
        sta (zp_vbxe_base),y
?nc     inx
        cpx zp_rx_len
        bne ?lp
        memb_off
        cli
?done   rts
.endp

; ----------------------------------------------------------------------------
; vbxe_img_setpal - Set image palette (always palette 1)
; Input: zp_tmp_ptr = palette data (768 bytes)
; Preserves colors 0-7 (text), writes colors 8-255 from image data
; ----------------------------------------------------------------------------
.proc vbxe_img_setpal
        ; Select palette 1
        ldy #VBXE_PSEL
        lda #1
        sta (zp_vbxe_base),y

        ; Start at color 8 (preserve text colors 0-7)
        ldy #VBXE_CSEL
        lda #8
        sta (zp_vbxe_base),y

        ; Skip first 8 palette entries (24 bytes) in source data
        clc
        lda zp_tmp_ptr
        adc #24
        sta zp_tmp_ptr
        bcc ?ns
        inc zp_tmp_ptr+1
?ns     ldx #8

?write  ; Write colors from X to 255
        ldy #0
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

        clc
        lda zp_tmp_ptr
        adc #3
        sta zp_tmp_ptr
        bcc ?nc
        inc zp_tmp_ptr+1
?nc     inx
        bne ?write             ; loops until X wraps to 0
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_img_show_fullscreen - Show current image fullscreen
; Uses img_vram, img_height (set by alloc)
; XDL: init(24 border) + GMON(image) + TMON(status bar) + END
; Status bar shows last text row (STATUS_ROW) below the image
; ----------------------------------------------------------------------------
.proc vbxe_img_show_fullscreen
        lda #1
        sta img_active

        memb_on 0
        ldx #0

        ; --- Entry 1: top border + overlay init ---
        lda #<(XDLC_OVOFF|XDLC_MAPOFF|XDLC_RPTL|XDLC_OVADR|XDLC_CHBASE|XDLC_OVATT)
        sta MEMB_XDL,x
        inx
        lda #>(XDLC_OVOFF|XDLC_MAPOFF|XDLC_RPTL|XDLC_OVADR|XDLC_CHBASE|XDLC_OVATT)
        sta MEMB_XDL,x
        inx
        lda #24-1
        sta MEMB_XDL,x
        inx
        ; OVADR = VRAM_SCREEN
        lda #<VRAM_SCREEN
        sta MEMB_XDL,x
        inx
        lda #>VRAM_SCREEN
        sta MEMB_XDL,x
        inx
        lda #0
        sta MEMB_XDL,x
        inx
        ; STEP
        lda #<SCR_STRIDE
        sta MEMB_XDL,x
        inx
        lda #>SCR_STRIDE
        sta MEMB_XDL,x
        inx
        ; CHBASE
        lda #CHBASE_VAL
        sta MEMB_XDL,x
        inx
        ; OVATT (palette 1 + NORMAL)
        lda #$11
        sta MEMB_XDL,x
        inx
        ; Priority
        lda #$FF
        sta MEMB_XDL,x
        inx

        ; --- Entry 2: GMON image ---
        lda #<(XDLC_GMON|XDLC_MAPOFF|XDLC_RPTL|XDLC_OVADR|XDLC_OVATT)
        sta MEMB_XDL,x
        inx
        lda #>(XDLC_GMON|XDLC_MAPOFF|XDLC_RPTL|XDLC_OVADR|XDLC_OVATT)
        sta MEMB_XDL,x
        inx
        ; RPTL = height - 1
        lda img_height
        sec
        sbc #1
        sta MEMB_XDL,x
        inx
        ; OVADR = image VRAM address
        lda img_vram
        sta MEMB_XDL,x
        inx
        lda img_vram+1
        sta MEMB_XDL,x
        inx
        lda img_vram+2
        sta MEMB_XDL,x
        inx
        ; STEP = 320 (NORMAL mode, converter always returns 320px wide)
        lda #<320
        sta MEMB_XDL,x
        inx
        lda #>320
        sta MEMB_XDL,x
        inx
        ; OVATT: palette 1 + NORMAL
        lda #$11
        sta MEMB_XDL,x
        inx
        ; Priority
        lda #$FF
        sta MEMB_XDL,x
        inx

        ; --- Remaining scanlines below image ---
        ; Calculate: remaining = 240 - 24 (border) - img_height
        ; Total screen = 240 scanlines always (8 OVOFF + 232 TMON)
        lda #240 - 24
        sec
        sbc img_height
        beq ?no_text           ; image fills screen exactly
        bmi ?no_text           ; image taller than screen (shouldn't happen)
        ; If remaining > 8, add OVOFF gap entry first
        cmp #9
        bcc ?status_only       ; remaining <= 8, just status bar

        ; --- Entry 3: OVOFF gap (black area between image and status) ---
        sec
        sbc #8                 ; gap = remaining - 8 (status bar)
        sec
        sbc #1                 ; RPTL = gap - 1
        pha
        lda #<(XDLC_OVOFF|XDLC_MAPOFF|XDLC_RPTL)
        sta MEMB_XDL,x
        inx
        lda #>(XDLC_OVOFF|XDLC_MAPOFF|XDLC_RPTL)
        sta MEMB_XDL,x
        inx
        pla
        sta MEMB_XDL,x
        inx

?status_only
        ; --- Status bar: TMON 8 scanlines (1 text row) + END ---
        lda #<(XDLC_TMON|XDLC_MAPOFF|XDLC_RPTL|XDLC_OVADR|XDLC_CHBASE|XDLC_OVATT|XDLC_END)
        sta MEMB_XDL,x
        inx
        lda #>(XDLC_TMON|XDLC_MAPOFF|XDLC_RPTL|XDLC_OVADR|XDLC_CHBASE|XDLC_OVATT|XDLC_END)
        sta MEMB_XDL,x
        inx
        lda #8-1               ; always 8 scanlines = 1 text row
        sta MEMB_XDL,x
        inx
        ; OVADR = STATUS_ROW * SCR_STRIDE
        lda #<(STATUS_ROW * SCR_STRIDE)
        sta MEMB_XDL,x
        inx
        lda #>(STATUS_ROW * SCR_STRIDE)
        sta MEMB_XDL,x
        inx
        lda #0
        sta MEMB_XDL,x
        inx
        ; STEP
        lda #<SCR_STRIDE
        sta MEMB_XDL,x
        inx
        lda #>SCR_STRIDE
        sta MEMB_XDL,x
        inx
        ; CHBASE
        lda #CHBASE_VAL
        sta MEMB_XDL,x
        inx
        ; OVATT (palette 1 + NORMAL)
        lda #$11
        sta MEMB_XDL,x
        inx
        ; Priority
        lda #$FF
        sta MEMB_XDL,x
        jmp ?done

?no_text
        ; Image fills full screen - just add END
        lda #<(XDLC_OVOFF|XDLC_END)
        sta MEMB_XDL,x
        inx
        lda #>(XDLC_OVOFF|XDLC_END)
        sta MEMB_XDL,x

?done   memb_off
        rts

.endp


; ----------------------------------------------------------------------------
; vbxe_img_hide - Restore text-only XDL
; ----------------------------------------------------------------------------
.proc vbxe_img_hide
        lda #0
        sta img_active
        ; Wait for VBI to avoid XDL tearing
        lda RTCLOK+2
?wv     cmp RTCLOK+2
        beq ?wv
        memb_on 0
        jsr setup_xdl
        memb_off
        jmp setup_palette
.endp

; ============================================================================
; Title Screen Graphics - GMON gradient banner
; ============================================================================

VRAM_GRADIENT  = VRAM_IMG_BASE   ; Reuses image VRAM space ($3000)
GRAD_BAND_W    = 320             ; Pixels per scanline (NORMAL mode)
GRAD_BANDS     = 4
GRAD_BAND_H    = 8              ; Scanlines per band
TITLE_TEXT_ROWS = (240 - GRAD_BANDS * GRAD_BAND_H) / 8  ; = 26

; ----------------------------------------------------------------------------
; title_gfx_init - Fill gradient VRAM + set up title XDL (GMON+TMON)
; MUST be below $4000 (uses MEMAC B)
; ----------------------------------------------------------------------------
.proc title_gfx_init
        memb_on 0

        ; Fill 4 gradient bands at MEMB_BASE + VRAM_GRADIENT ($7000)
        lda #<(MEMB_BASE + VRAM_GRADIENT)
        sta zp_tmp_ptr
        lda #>(MEMB_BASE + VRAM_GRADIENT)
        sta zp_tmp_ptr+1

        ldx #0
?band   lda grad_colors,x
        stx zp_tmp1            ; save band index

        ; Fill 256 bytes
        ldy #0
?f1     sta (zp_tmp_ptr),y
        iny
        bne ?f1

        ; Advance pointer by 256
        inc zp_tmp_ptr+1

        ; Fill remaining 64 bytes (320-256)
        ldy #0
?f2     sta (zp_tmp_ptr),y
        iny
        cpy #64
        bne ?f2

        ; Advance pointer by 64
        clc
        lda zp_tmp_ptr
        adc #64
        sta zp_tmp_ptr
        bcc ?nc
        inc zp_tmp_ptr+1
?nc     ldx zp_tmp1
        inx
        cpx #GRAD_BANDS
        bne ?band

        ; Copy title XDL to VRAM
        ldx #0
?xdl    lda title_xdl_data,x
        sta MEMB_XDL,x
        inx
        cpx #TITLE_XDL_LEN
        bne ?xdl

        memb_off
        rts

; Gradient colors: palette indices, top (dark) to bottom (light)
grad_colors dta 8, 9, 10, 11

title_xdl_data
        ; Band 0 (top, darkest)
        dta a(XDLC_GMON | XDLC_MAPOFF | XDLC_RPTL | XDLC_OVADR | XDLC_OVATT)
        dta GRAD_BAND_H - 1
        dta <VRAM_GRADIENT, >VRAM_GRADIENT, 0
        dta a(0)                       ; step=0 (repeat scanline)
        dta $11, $FF                   ; palette 1 + NORMAL, priority

        ; Band 1
        dta a(XDLC_GMON | XDLC_MAPOFF | XDLC_RPTL | XDLC_OVADR | XDLC_OVATT)
        dta GRAD_BAND_H - 1
        dta <(VRAM_GRADIENT + GRAD_BAND_W), >(VRAM_GRADIENT + GRAD_BAND_W), 0
        dta a(0)
        dta $11, $FF

        ; Band 2
        dta a(XDLC_GMON | XDLC_MAPOFF | XDLC_RPTL | XDLC_OVADR | XDLC_OVATT)
        dta GRAD_BAND_H - 1
        dta <(VRAM_GRADIENT + GRAD_BAND_W*2), >(VRAM_GRADIENT + GRAD_BAND_W*2), 0
        dta a(0)
        dta $11, $FF

        ; Band 3 (bottom, lightest)
        dta a(XDLC_GMON | XDLC_MAPOFF | XDLC_RPTL | XDLC_OVADR | XDLC_OVATT)
        dta GRAD_BAND_H - 1
        dta <(VRAM_GRADIENT + GRAD_BAND_W*3), >(VRAM_GRADIENT + GRAD_BAND_W*3), 0
        dta a(0)
        dta $11, $FF

        ; Text section (26 rows = 208 scanlines)
        dta a(XDLC_TMON | XDLC_MAPOFF | XDLC_RPTL | XDLC_OVADR | XDLC_CHBASE | XDLC_OVATT | XDLC_END)
        dta TITLE_TEXT_ROWS * 8 - 1
        dta <VRAM_SCREEN, >VRAM_SCREEN, 0
        dta a(SCR_STRIDE)
        dta CHBASE_VAL
        dta $11                        ; palette 1 + NORMAL
        dta $FF                        ; priority

TITLE_XDL_LEN = * - title_xdl_data
.endp
