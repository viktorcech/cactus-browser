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
        ldx zp_rx_len
        beq ?done
        stx img_chunk_lo       ; rx_buffer[0..n-1] -> img_big_buf, then the
        lda #0                 ; block copy (same pointer / bank handling)
        sta img_chunk_hi
?cp     lda rx_buffer-1,x
        sta img_big_buf-1,x
        dex
        bne ?cp
        jmp vbxe_img_write_big
?done   rts
.endp

; ----------------------------------------------------------------------------
; vbxe_img_write_big - Copy img_big_buf to VRAM, 16-bit count, block copy
; Companion to fn_read_img: handles large (up to 2KB) chunks that
; fn_read_img deposits into img_big_buf.
;
; Input: img_chunk_lo/hi = byte count (PRESERVED), zp_img_ptr/img_wr_bank set
; Source: img_big_buf (at $B724, above $7FFF — unaffected by MEMAC B)
; Dest: VBXE VRAM via MEMAC B window ($4000-$7FFF)
; MUST be below $4000 (executes with MEMAC B active)
; Copies in blocks of up to 256 bytes that never cross the $8000 bank
; boundary — inner loop is ~19 cycles/byte vs ~53 in the old per-byte
; version (saves ~1.3s on a fullscreen 64KB image).
; Uses: zp_tmp_ptr (src), zp_tmp1 (block size, 0=256), zp_tmp2/3 (remaining)
; ----------------------------------------------------------------------------
 .if 1                          ; 2026-09-23 (6502-cycles-layout: the per-block branches to ?haveb
                                ; and the copy loop in one page)
        page_fit vbxe_img_write_big.blk-vbxe_img_write_big, vbxe_img_write_big.cp_end-vbxe_img_write_big.blk
 .else
        page_fit vbxe_img_write_big.cp_loop-vbxe_img_write_big, vbxe_img_write_big.cp_end-vbxe_img_write_big.cp_loop
 .endif
.proc vbxe_img_write_big
        lda img_chunk_lo
        sta zp_tmp2
        ora img_chunk_hi
        bne ?go
        rts
?go     lda img_chunk_hi
        sta zp_tmp3
        lda #<img_big_buf      ; source (16-bit, advanced per block)
        sta ?srcl
        lda #>img_big_buf
        sta ?srch

        sei
        lda img_wr_bank
        ora #$80
        sta zp_memb_shadow     ; shadow FIRST (VBI is NMI!)
        memb_set

blk
?block  ; Block size = min(remaining, 256, space to $8000); 0 means 256
        lda zp_tmp3
        beq ?small
        lda #0                 ; remaining >= 256: candidate = 256
        beq ?cap
?small  lda zp_tmp2            ; candidate = remaining (1-255)
?cap    ; Cap at bank boundary: only possible when dest page = $7F
        ldx zp_img_ptr+1
        cpx #$7F
        bne ?haveb
        ldx zp_img_ptr
        beq ?haveb             ; dest at $7F00: full 256 to boundary
        sta zp_tmp1            ; save candidate
        lda #0
        sec
        sbc zp_img_ptr         ; A = 256 - dest_lo = space to $8000 (1-255)
        ldx zp_tmp1
        beq ?haveb             ; candidate 256 -> take space
        cmp zp_tmp1
        bcc ?haveb             ; space < candidate -> take space
        lda zp_tmp1
?haveb  sta zp_tmp1

        ; Copy with Y counting up to 0: both bases moved back by y0 = 256-n
        eor #$FF
        clc
        adc #1                 ; y0 = -n (n = 256 -> 0)
        sta ?y0
        lda ?srcl
        sec
        sbc ?y0
        sta ?cp+1
        lda ?srch
        sbc #0
        sta ?cp+2
        lda zp_img_ptr
        sec
        sbc ?y0
        sta zp_tmp_ptr2
        lda zp_img_ptr+1
        sbc #0
        sta zp_tmp_ptr2+1
        ldy ?y0
cp_loop
?cp     lda $FFFF,y            ; RAM (above $7FFF)
        sta (zp_tmp_ptr2),y    ; VRAM via MEMAC B
        iny
        bne ?cp
cp_end
        ert >?cp <> >*         ; the per-byte loop must not cross a page

        ; Advance src/dest, decrement remaining (block 0 = 256)
        lda zp_tmp1
        bne ?adv
        inc ?srch
        inc zp_img_ptr+1
        dec zp_tmp3
        jmp ?bank
?adv    clc
        adc ?srcl
        sta ?srcl
        bcc ?n1
        inc ?srch
?n1     lda zp_tmp1
        clc
        adc zp_img_ptr
        sta zp_img_ptr
        bcc ?n2
        inc zp_img_ptr+1
?n2     lda zp_tmp2
        sec
        sbc zp_tmp1
        sta zp_tmp2
        bcs ?bank
        dec zp_tmp3

?bank   ; Dest reached $8000 -> wrap to $4000, switch to next bank
        lda zp_img_ptr+1
        cmp #$80
        bne ?rem
        lda #$40
        sta zp_img_ptr+1
        inc img_wr_bank
        lda img_wr_bank
        ora #$80
        sta zp_memb_shadow     ; shadow FIRST
        memb_set

?rem    lda zp_tmp2
        ora zp_tmp3
        jne ?block
        memb_off
        cli
        rts
?srcl   dta 0
?srch   dta 0
?y0     dta 0
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
; vbxe_pb_write_big - Copy img_big_buf to VRAM page buffer, 16-bit count
; Input: img_chunk_lo/hi = byte count (preserved by vbxe_img_write_big)
; Used by http_download: page data arrives via fn_read_img in up-to-2KB
; SIO chunks (8x fewer SIO calls than the old 255-byte fn_read path).
; Loads page-buffer write state into the image write pointer, copies via
; the fast vbxe_img_write_big block routine, then stores the state back.
; Safe: page download and image fetch never run concurrently (dl_active).
; Plain RAM ops + jsr, so this proc itself has no below-$4000 requirement.
; ----------------------------------------------------------------------------
.proc vbxe_pb_write_big
        lda zp_pb_wr_ptr
        sta zp_img_ptr
        lda zp_pb_wr_ptr+1
        sta zp_img_ptr+1
        lda pb_wr_bank
        sta img_wr_bank
        jsr vbxe_img_write_big
        lda zp_img_ptr
        sta zp_pb_wr_ptr
        lda zp_img_ptr+1
        sta zp_pb_wr_ptr+1
        lda img_wr_bank
        sta pb_wr_bank
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_pb_write_chunk - Copy rx_buffer to VRAM page buffer
; Input: zp_rx_len = number of bytes in rx_buffer (1-255)
; Block copy: since len <= 255, the $8000 bank boundary can only be hit
; when the write pointer is in page $7F — split the copy there instead of
; testing per byte (~18 cycles/byte vs ~28 in the old loop).
; ----------------------------------------------------------------------------
.proc vbxe_pb_write_chunk
        lda zp_rx_len
        beq ?done

        sei
        lda pb_wr_bank
        ora #$80
        sta zp_memb_shadow     ; shadow FIRST (VBI is NMI!)
        memb_set

        ldy #0
        lda zp_pb_wr_ptr+1
        cmp #$7F
        bne ?copy              ; below page $7F: cannot cross boundary
        lda zp_pb_wr_ptr
        beq ?copy              ; $7F00 + <=255 ends at most at $7FFF
        eor #$FF
        clc
        adc #1                 ; A = 256 - ptr_lo = bytes until $8000
        cmp zp_rx_len
        bcs ?copy              ; whole chunk fits before boundary
        sta ?split
        ; Part 1: Y = 0..split-1 (up to the bank boundary)
?lp1    lda rx_buffer,y
        sta (zp_pb_wr_ptr),y
        iny
        cpy ?split
        bne ?lp1
        ; Switch bank, bias pointer so (ptr+Y) continues at $4000
        inc pb_wr_bank
        lda pb_wr_bank
        ora #$80
        sta zp_memb_shadow     ; shadow FIRST
        memb_set
        lda #0
        sec
        sbc ?split
        sta zp_pb_wr_ptr       ; ptr = $4000 - split
        lda #$40
        sbc #0
        sta zp_pb_wr_ptr+1
        ldy ?split
        ; Part 2 continues in ?copy with Y = split

?copy   cpy zp_rx_len
        beq ?adv
?lp2    lda rx_buffer,y
        sta (zp_pb_wr_ptr),y
        iny
        cpy zp_rx_len
        bne ?lp2

?adv    ; Advance pointer; exact $8000 wraps to $4000 + next bank
        lda zp_pb_wr_ptr
        clc
        adc zp_rx_len
        sta zp_pb_wr_ptr
        bcc ?nc
        inc zp_pb_wr_ptr+1
?nc     lda zp_pb_wr_ptr+1
        cmp #$80
        bne ?fin
        lda #$40
        sta zp_pb_wr_ptr+1
        inc pb_wr_bank         ; bank register is reloaded on next call
?fin    memb_off
        cli
?done   rts
?split  dta 0
.endp

; ----------------------------------------------------------------------------
; vbxe_pb_read_chunk - Copy VRAM page buffer to rx_buffer
; Input: A = number of bytes to read (max 255)
; Output: zp_rx_len = bytes read, rx_buffer filled
; Same block-copy structure as vbxe_pb_write_chunk, direction reversed.
; ----------------------------------------------------------------------------
 .if 1                          ; 2026-09-23 (6502-cycles-layout: the branches to ?whole and the
                                ; copy loop in one page)
        page_fit vbxe_pb_read_chunk.wh_s-vbxe_pb_read_chunk, vbxe_pb_read_chunk.rd_end-vbxe_pb_read_chunk.wh_s
 .else
        page_fit vbxe_pb_read_chunk.rd_loop-vbxe_pb_read_chunk, vbxe_pb_read_chunk.rd_end-vbxe_pb_read_chunk.rd_loop
 .endif
.proc vbxe_pb_read_chunk
        sta zp_rx_len
        beq ?done
        sta ?n

        sei
        lda pb_rd_bank
        ora #$80
        sta zp_memb_shadow     ; shadow FIRST (VBI is NMI!)
        memb_set
        lda #<(rx_buffer-1)
        sta ?dst+1
        lda #>(rx_buffer-1)
        sta ?dst+2

        ; len <= 255: the $8000 bank end can only be hit from page $7F
wh_s
        lda zp_pb_rd_ptr+1
        cmp #$7F
        bne ?whole
        lda zp_pb_rd_ptr
        beq ?whole             ; $7F00 + <=255 ends at most at $7FFF
        eor #$FF
        adc #0                 ; C = 1 (cmp #$7F equal): A = 256 - ptr_lo
        cmp zp_rx_len
        bcs ?whole             ; whole chunk fits before boundary
        sta ?n
        jsr ?copy              ; part 1: up to the bank boundary
        inc pb_rd_bank
        lda pb_rd_bank
        ora #$80
        sta zp_memb_shadow     ; shadow FIRST
        memb_set
        lda #>MEMB_BASE        ; continue at $4000 (lo byte is 0 after ?copy)
        sta zp_pb_rd_ptr+1
        lda ?dst+1             ; dst += part 1
        clc
        adc ?n
        sta ?dst+1
        bcc ?d2
        inc ?dst+2
?d2
        lda zp_rx_len
        sec
        sbc ?n
        sta ?n                 ; part 2 (>= 1)
        jsr ?copy
        jmp ?fin

?whole  jsr ?copy
        lda zp_pb_rd_ptr+1     ; exact $8000: wrap to $4000 + next bank
        cmp #$80
        bne ?fin
        lda #$40
        sta zp_pb_rd_ptr+1
        inc pb_rd_bank         ; bank register is reloaded on next call
?fin    memb_off
        cli
?done   rts

?copy   ; ?n bytes (1-255) from (zp_pb_rd_ptr) to ?dst+1..., Y counting down
        lda zp_pb_rd_ptr
        sec
        sbc #1
        sta zp_tmp_ptr2
        lda zp_pb_rd_ptr+1
        sbc #0
        sta zp_tmp_ptr2+1
        ldy ?n
rd_loop
?cp     lda (zp_tmp_ptr2),y
?dst    sta $FFFF,y
        dey
        bne ?cp
rd_end
        ert >?cp <> >*         ; hot loop: keep it in one page
        lda zp_pb_rd_ptr       ; ptr += n
        clc
        adc ?n
        sta zp_pb_rd_ptr
        bcc ?nc
        inc zp_pb_rd_ptr+1
?nc     rts
?n      dta 0
.endp

; vbxe_img_setpal moved to vbxe_pal.asm (register I/O only, no MEMAC B needed)

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
        ; Entries 1 (top border + overlay init) and 2 (GMON image) from the
        ; template, then the image height and address patched in
        ldx #IMG_XDL_LEN-1
?cp     lda img_xdl,x
        sta MEMB_XDL,x
        dex
        bpl ?cp
        ldx img_height
        dex
        stx MEMB_XDL+13        ; RPTL = height - 1
        lda img_vram
        sta MEMB_XDL+14
        lda img_vram+1
        sta MEMB_XDL+15
        lda img_vram+2
        sta MEMB_XDL+16
        ldx #IMG_XDL_LEN

        ; --- Remaining scanlines below image ---
        ; remaining = 240 - 24 (border) - img_height
        lda #240 - 24
        sec
        sbc img_height
        beq ?no_text           ; image fills screen exactly
        bmi ?no_text           ; image taller than screen (shouldn't happen)
        cmp #9
        bcc ?status_only       ; remaining <= 8, just status bar

        ; --- Entry 3: OVOFF gap (black area between image and status) ---
        sbc #8+1               ; C = 1: RPTL = remaining - 8 - 1
        tay
        lda #<(XDLC_OVOFF|XDLC_MAPOFF|XDLC_RPTL)
        sta MEMB_XDL,x
        lda #>(XDLC_OVOFF|XDLC_MAPOFF|XDLC_RPTL)
        sta MEMB_XDL+1,x
        tya
        sta MEMB_XDL+2,x
        inx
        inx
        inx

?status_only
        ; --- Status bar: TMON 8 scanlines (1 text row) + END ---
 .if 1                          ; 2026-09-23 (6502-loops-tables-smc: index counting up to zero)
        ldy #256-11
?st     lda img_xdl_status+11-256,y
        sta MEMB_XDL,x
        inx
        iny
        bne ?st
        beq ?done              ; always (Z = 1)
 .else
        ldy #0
?st     lda img_xdl_status,y
        sta MEMB_XDL,x
        inx
        iny
        cpy #11
        bne ?st
        beq ?done              ; always
 .endif

?no_text
        ; Image fills full screen - just add END
        lda #<(XDLC_OVOFF|XDLC_END)
        sta MEMB_XDL,x
        lda #>(XDLC_OVOFF|XDLC_END)
        sta MEMB_XDL+1,x

?done   memb_off
        rts

img_xdl
        ; Entry 1: top border + overlay init (24 lines)
        dta a(XDLC_OVOFF|XDLC_MAPOFF|XDLC_RPTL|XDLC_OVADR|XDLC_CHBASE|XDLC_OVATT)
        dta 24-1
        dta <VRAM_SCREEN, >VRAM_SCREEN, 0
        dta a(SCR_STRIDE)
        dta CHBASE_VAL
        dta $11, $FF           ; palette 1 + NORMAL, priority
        ; Entry 2: GMON image (RPTL and OVADR patched)
        dta a(XDLC_GMON|XDLC_MAPOFF|XDLC_RPTL|XDLC_OVADR|XDLC_OVATT)
        dta 0
        dta 0, 0, 0
        dta a(320)             ; converter always returns 320 px wide
        dta $11, $FF
IMG_XDL_LEN = * - img_xdl
img_xdl_status
        dta a(XDLC_TMON|XDLC_MAPOFF|XDLC_RPTL|XDLC_OVADR|XDLC_CHBASE|XDLC_OVATT|XDLC_END)
        dta 8-1                ; always 8 scanlines = 1 text row
        dta <(STATUS_ROW * SCR_STRIDE), >(STATUS_ROW * SCR_STRIDE), 0
        dta a(SCR_STRIDE)
        dta CHBASE_VAL
        dta $11, $FF
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
        ; Copy title XDL to VRAM
        memb_on 0
        ldx #TITLE_XDL_LEN-1
?xdl    lda title_xdl_data,x
        sta MEMB_XDL,x
        dex
        bpl ?xdl
        memb_off
        ; 4 gradient bands (320 bytes each at VRAM_GRADIENT): one blit, the
        ; source steps one colour byte per row with X step 0 (vbxe_init).
        ; Started, not waited for: the text that follows goes to the screen
        ; area, not the gradient
        lda #<(VRAM_BCB+BCB_GRAD_OFS)
        ldx #>(VRAM_BCB+BCB_GRAD_OFS)
        jmp blit_go

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

; ============================================================================
; MEMAC B boundary guard: everything above (vbxe_text, find, vbxe_gfx)
; runs with the MEMAC B window ($4000-$7FFF) enabled and MUST stay below
; $4000. Build fails here if code growth pushes it over the boundary.
; ============================================================================
        ert *>$4000
