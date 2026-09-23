; ============================================================================
; Image Fetch Module - Download and display VBXE images via FujiNet
; Format: 2B width(LE) + 1B height + 768B palette + w*h pixels
; Images shown fullscreen one at a time after page loads
; ============================================================================

; ----------------------------------------------------------------------------
; copy_img_src - Copy from (zp_tmp_ptr)+Y to img_src_buf, null-terminated
; Input: Y = start offset, zp_tmp_ptr = source
; ----------------------------------------------------------------------------
.proc copy_img_src
        ldx #0
?lp     lda (zp_tmp_ptr),y
        sta img_src_buf,x
        beq ?done
        iny
        inx
        cpx #IMG_SRC_SIZE-1
        bne ?lp
        lda #0
        sta img_src_buf,x
?done   rts
.endp

img_hdr_w   dta a(0)           ; image width (16-bit LE, 8-320)
img_hdr_h   dta b(0)           ; image height (8-bit, 8-192)
img_pal_cnt dta a(0)           ; palette bytes read so far (16-bit, target=768)
img_timeout dta b(0)           ; idle retries left before giving up
img_pal_leftover dta b(0)      ; pixel bytes after 768th palette byte in same chunk

; Max retries before timeout (each retry ~120ms = ~40 retries = ~5 sec)
IMG_MAX_RETRIES = 40

; ----------------------------------------------------------------------------
; img_check_abort - Non-blocking key check during image download
; Allows user to cancel long image transfers by pressing any key
; Output: C=1 if key pressed (abort), C=0 continue
; ----------------------------------------------------------------------------
.proc img_check_abort
        lda CH
        eor #KEY_NONE          ; 0 = no key
        cmp #1                 ; C = 1: a key was pressed
        bcc ?no
        lda #KEY_NONE          ; consume it (C stays 1)
        sta CH
?no     rts
.endp

; ----------------------------------------------------------------------------
; img_read_header - Read 3-byte image header from converter
; Format: [width_lo] [width_hi] [height]
; Validates: width 8-320, height 8-192 (rejects corrupt/empty streams)
; Error codes: 1=abort, 2=SIO, 3=EOF, 4=fatal, 5=disconnect, 6=timeout,
;              7=SIO read, 8=sanity check
; Output: img_hdr_w, img_hdr_h set, C=0 ok, C=1 error
; ----------------------------------------------------------------------------
.proc img_read_header
        lda #IMG_MAX_RETRIES
        sta img_timeout

?wt     jsr img_check_abort
        bcs ?e_abort

        jsr fn_status
        bcs ?e_sio
        lda zp_fn_error
        bpl ?no_err
        cmp #136
        beq ?e_eof
        bne ?e_fatal           ; always
?no_err
        lda zp_fn_bytes_hi
        bne ?read
        lda zp_fn_bytes_lo
        cmp #3
        bcs ?read
        lda zp_fn_connected
        beq ?e_disc
        dec img_timeout
        beq ?e_tout
        wait_frames 6
        beq ?wt                ; always (wait_frames returns Z = 1)

?read   lda #3
        sta zp_fn_bytes_lo
        lda #0
        sta zp_fn_bytes_hi
        jsr fn_read
        bcs ?e_sio2

        lda rx_buffer
        sta img_hdr_w
        lda rx_buffer+1
        sta img_hdr_w+1
        lda rx_buffer+2
        sta img_hdr_h
        ; Sanity check: width 8-320, height 8-192
        lda img_hdr_w+1
        cmp #2
        bcs ?e_san
        lsr                    ; hi = 1?
        bcc ?chk_lo
        lda img_hdr_w
        cmp #$41
        bcs ?e_san
        bcc ?chk_h             ; always
?chk_lo lda img_hdr_w
        cmp #8
        bcc ?e_san
?chk_h  lda img_hdr_h
        cmp #8
        bcc ?e_san
        cmp #209
        bcs ?e_san
        rts                    ; C = 0
?e_fatal sta img_fn_err
        lda #4
        .byte $2C              ; bit abs: skips the next lda # (RAM read only)
?e_abort lda #1
        .byte $2C
?e_sio  lda #2
        .byte $2C
?e_eof  lda #3
        .byte $2C
?e_disc lda #5
        .byte $2C
?e_tout lda #6
        .byte $2C
?e_sio2 lda #7
        .byte $2C
?e_san  lda #8
?fail   sta img_err_code
        sec
        rts
.endp

img_err_code dta b(0)
img_fn_err   dta b(0)

; ----------------------------------------------------------------------------
; img_read_palette - Read 768 bytes (256 colors * 3 RGB) into img_pal_buf
; Palette may end mid-chunk — leftover bytes are pixel data, saved in
; img_pal_leftover for img_fetch_single to flush to VRAM
; Output: img_pal_buf filled, img_pal_leftover set, C=0 ok
; ----------------------------------------------------------------------------
.proc img_read_palette
        lda #<img_pal_buf
        sta zp_tmp_ptr
        lda #>img_pal_buf
        sta zp_tmp_ptr+1
        lda #0
        sta img_pal_cnt
        sta img_pal_cnt+1
        lda #IMG_MAX_RETRIES
        sta img_timeout

?lp     jsr img_check_abort
        bcs ?err

        jsr fn_status
        bcs ?err
        lda zp_fn_error
        bmi ?err               ; >= 128: EOF (136) or fatal
        lda zp_fn_bytes_lo
        ora zp_fn_bytes_hi
        beq ?wait

        jsr fn_read
        bcs ?err
        lda zp_rx_len
        beq ?lp

        lda #IMG_MAX_RETRIES
        sta img_timeout

        ; n = min(chunk, 768 - count): copy it as one block
        lda #<768
        sec
        sbc img_pal_cnt
        tax
        lda #>768
        sbc img_pal_cnt+1
        bne ?all               ; >= 256 left: the whole chunk
        cpx zp_rx_len
        bcs ?all
        stx ?n                 ; the palette ends inside this chunk
        bcc ?go                ; always
?all    lda zp_rx_len
        sta ?n
?go     ldy #0
?cp     lda rx_buffer,y
        sta (zp_tmp_ptr),y
        iny
        cpy ?n
        bne ?cp
        tya                    ; ptr += n, count += n
        clc
        adc zp_tmp_ptr
        sta zp_tmp_ptr
        bcc ?nc1
        inc zp_tmp_ptr+1
?nc1    tya
        clc
        adc img_pal_cnt
        sta img_pal_cnt
        bcc ?nc2
        inc img_pal_cnt+1
?nc2    lda img_pal_cnt+1
        cmp #3
        bcs ?done_y            ; 768 reached: Y = first leftover byte
        jcc ?lp                ; always

?wait   dec img_timeout
        beq ?err
        wait_frames 6
        jeq ?lp                ; always (wait_frames returns Z = 1)

?err    lda #0
        sta img_pal_leftover   ; no leftover on error
        sec
        rts

?done_y ; Palette complete -- save any leftover pixel bytes in rx_buffer
        cpy zp_rx_len
        bcs ?no_left           ; no leftover pixels in this chunk
        ; Shift rx_buffer[Y..rx_len-1] to rx_buffer[0..]
        ldx #0
?shl    lda rx_buffer,y
        sta rx_buffer,x
        iny
        inx
        cpy zp_rx_len
        bcc ?shl
        stx img_pal_leftover   ; save leftover count
        clc
        rts
?no_left
        lda #0
        sta img_pal_leftover   ; no leftover pixels
        clc
        rts
?n      dta 0
.endp

; ----------------------------------------------------------------------------
; img_read_pixels - Stream pixel data into VBXE VRAM via MEMAC B
; Reads chunks from FujiNet, writes each to VRAM via vbxe_img_write_chunk
; Stops on: EOF (error 136), disconnect, timeout, user abort, or read error
; Output: C=0 ok (image complete or partial), C=1 error
; ----------------------------------------------------------------------------
.proc img_read_pixels
        ; left = width * height - bytes already written (palette leftover)
        lda #0
        sta img_left
        sta img_left+1
        sta img_left+2
        ldx img_hdr_h
?mul    lda img_left
        clc
        adc img_hdr_w
        sta img_left
        lda img_left+1
        adc img_hdr_w+1
        sta img_left+1
        bcc ?m1
        inc img_left+2
?m1     dex
        bne ?mul
        lda img_left
        sec
        sbc img_pal_leftover
        sta img_left
        bcs ?m2
        lda img_left+1
        bne ?m3
        dec img_left+2
?m3     dec img_left+1
?m2
        lda #IMG_MAX_RETRIES
        sta img_timeout

?lp     lda img_left           ; whole image received: done
        ora img_left+1
        ora img_left+2
        beq ?done
        jsr img_check_abort
        bcs ?err

        jsr fn_status
        bcs ?err
        ; Read whatever is waiting FIRST: the server closes the connection as
        ; soon as it has sent the image, while the tail still sits in the
        ; FujiNet buffer (stopping on "disconnected" cut the bottom off)
        lda zp_fn_bytes_lo
        ora zp_fn_bytes_hi
        beq ?no_data

        jsr fn_read_img
        bcs ?done              ; read error -> show partial image
        lda img_chunk_lo
        ora img_chunk_hi
        beq ?lp                ; zero bytes read, retry

        lda #IMG_MAX_RETRIES
        sta img_timeout
        lda img_left           ; left -= chunk
        sec
        sbc img_chunk_lo
        sta img_left
        lda img_left+1
        sbc img_chunk_hi
        sta img_left+1
        bcs ?w
        dec img_left+2
        bpl ?w
        lda #0                 ; more than announced: stop after this chunk
        sta img_left
        sta img_left+1
        sta img_left+2
?w      jsr vbxe_img_write_big
        jmp ?lp

?no_data                       ; nothing waiting: end, error or wait
        lda zp_fn_error
        bpl ?live
        cmp #136               ; EOF: the stream is complete
        beq ?done
        bne ?err               ; fatal
?live   lda zp_fn_connected
        beq ?done              ; closed and drained
        dec img_timeout
        beq ?done
        wait_frames 6
        jeq ?lp                ; always (wait_frames returns Z = 1)

?done   clc
        rts
?err    sec
        rts
.endp

img_left dta 0, 0, 0           ; pixel bytes still expected (24-bit)

; ----------------------------------------------------------------------------
; img_resolve_and_build_url - Resolve relative image URL and build converter URL
; Steps: 1) Copy img_src_buf → url_buffer, resolve via http_resolve_url
;        2) Strip N: prefix back to img_src_buf
;        3) Build: m_prefix + img_src_buf + m_suffix → url_buffer
; WARNING: Overwrites url_buffer! Caller must save/restore if needed
; ----------------------------------------------------------------------------
.proc img_resolve_and_build_url
        ; Copy img_src_buf to url_buffer for resolve
        ldy #0
?ri     lda img_src_buf,y
        sta url_buffer,y
        beq ?rid
        iny
        bne ?ri
?rid    sty url_length
        jsr http_resolve_url
        ; Strip N: prefix back to img_src_buf
        ldy #0
        lda url_buffer
        cmp #'N'
        bne ?nb
        lda url_buffer+1
        cmp #':'
        bne ?nb
        ldy #2
?nb     ldx #0
?rc     lda url_buffer,y
        sta img_src_buf,x
        beq ?rcd
        iny
        inx
        cpx #IMG_SRC_SIZE-1
        bne ?rc
        lda #0
        sta img_src_buf,x
?rcd
        ; Build: prefix + img_src_buf + suffix
        ldy #0
?pfx    lda m_prefix,y
        beq ?pfxd
        sta url_buffer,y
        iny
        bne ?pfx
?pfxd   ldx #0
?src    lda img_src_buf,x
        beq ?srcd
        sta url_buffer,y
        iny
        inx
        cpy #URL_BUF_SIZE-20
        bcc ?src
?srcd   ldx #0
?sfx    lda m_suffix,x
        sta url_buffer,y
        beq ?sfxd
        iny
        inx
        bne ?sfx
?sfxd   sty url_length
        rts
.endp

; ----------------------------------------------------------------------------
; img_fetch_single - Fetch and display a single image from img_src_buf
; Called from: ui_follow_link (main menu), render_page_pause (--More-- prompt),
;             http_download (deferred after page download closes N1:)
; Flow: save url → resolve → OPEN N1: → header → alloc → palette → pixels →
;       CLOSE → set palette → show fullscreen → wait key → restore → return
; Saves/restores url_buffer (converter URL would corrupt page URL)
; ----------------------------------------------------------------------------
.proc img_fetch_single
        ; Save page URL (img_resolve_and_build_url overwrites url_buffer)
        jsr img_save_url

        status_msg COL_YELLOW, m_step1

        ; Resolve relative URL and build vbxe.php converter URL
        jsr img_resolve_and_build_url

        ; N1: is already closed (http_download closed it after buffering page)
        ; fn_close is harmless on already-closed connection
        lda #FN_UNIT
        sta fn_cur_unit
        jsr fn_close

        status_msg COL_YELLOW, m_step2

        ; Open N1: with image converter URL
        jsr fn_open
        jcs ?e_open

        status_msg COL_YELLOW, m_step3

        ; Read header
        jsr img_read_header
        jcs ?e_hdr
        ; Allocate VRAM
        lda img_hdr_h
        ldx img_hdr_w
        ldy img_hdr_w+1
        jsr vbxe_img_alloc
        jcs ?e_alloc

        status_msg COL_YELLOW, m_step5

        ; Read palette
        jsr img_read_palette
        jcs ?e_pal

        status_msg COL_YELLOW, m_step6

        ; Init write pointer (a compact image streams to the end of the
        ; image area, img_center moves it into place afterwards)
        jsr img_stage
        jsr vbxe_img_begin_write

        ; Write any leftover pixel bytes from palette read
        ; (palette may end mid-chunk, remaining bytes are pixel data)
        lda img_pal_leftover
        sta zp_rx_len
        jsr vbxe_img_write_chunk   ; no-op if zp_rx_len=0

        ; Read pixels BEFORE setting palette (palette overwrites link colors)
        jsr img_read_pixels

        jsr fn_close           ; close N1: image connection
        jsr img_center         ; compact image -> centred 320-wide rows

        ; Set VBXE palette AFTER pixels (keeps text colors during download)
        lda #<img_pal_buf
        sta zp_tmp_ptr
        lda #>img_pal_buf
        sta zp_tmp_ptr+1
        jsr vbxe_img_setpal

        ; Write status text
 .if 1                          ; 2026-09-23 (one status bar for everything)
        status_msg COL_BLUE, m_imgview
 .else
        status_msg COL_YELLOW, m_imgview
 .endif

        ; Show image fullscreen
        jsr vbxe_img_show_fullscreen

        ; Wait for user key
        jsr kbd_get

        ; Clear mouse state (VBI may have set btn during image view)
        lda #0
        sta zp_mouse_btn
        lda #KEY_NONE
        sta CH

        ; Restore text display (vbxe_img_hide ends with jmp setup_palette)
        jsr vbxe_img_hide
        jsr img_restore_url
        jmp ui_status_done

?e_open lda #<me_open
        ldx #>me_open
        bne ?err_exit          ; always (hi byte != 0)
?e_hdr  jsr ?err_cleanup
        ; Patch error code digit into message string
        lda img_err_code
        ora #'0'               ; 1-8
        sta me_hdr_n
        ; Patch FN error as hex into message
        lda img_fn_err
        jsr byte_to_hex
        sta me_hdr_h
        stx me_hdr_h+1
        lda #<me_hdr
        ldx #>me_hdr
        jmp ui_show_error
?e_alloc lda #<me_alloc
        ldx #>me_alloc
        bne ?err_exit          ; always
?e_pal  lda #<me_pal
        ldx #>me_pal
?err_exit
        jsr ?err_cleanup
        jmp ui_show_error
?err_cleanup
        jsr fn_close
        jmp img_restore_url

 .if 1                          ; 2026-09-23 (one status bar for everything)
m_imgview dta c' Image',1,c'any key  Back',0
m_step1  dta c' Image: resolving the URL...',1,c'Key  Stop',0
m_step2  dta c' Image: connecting...',1,c'Key  Stop',0
m_step3  dta c' Image: reading the header...',1,c'Key  Stop',0
m_step5  dta c' Image: reading the palette...',1,c'Key  Stop',0
m_step6  dta c' Image: reading pixels...',1,c'Key  Stop',0
me_open  dta c' Image: cannot open it',1,c'any key',0
me_hdr   dta c' Image: bad header '
me_hdr_n dta c'? FN=$'
me_hdr_h dta c'??',1,c'any key',0
me_alloc dta c' Image: too big for VRAM',1,c'any key',0
me_pal   dta c' Image: palette error',1,c'any key',0
 .else
m_imgview dta c' Image - press any key',0
m_step1  dta c' IMG: resolving URL...',0
m_step2  dta c' IMG: connecting...',0
m_step3  dta c' IMG: reading header...',0
m_step5  dta c' IMG: reading palette...',0
m_step6  dta c' IMG: reading pixels...',0
me_open  dta c'IMG err: OPEN failed',0
me_hdr   dta c'IMG err: hdr '
me_hdr_n dta c'? FN=$'
me_hdr_h dta c'??',0
me_alloc dta c'IMG err: VRAM alloc',0
me_pal   dta c'IMG err: palette',0
 .endif
.endp

; ----------------------------------------------------------------------------
; img_save_url / img_restore_url - Save/restore url_buffer around image fetch
; (img_resolve_and_build_url overwrites url_buffer with converter URL)
; ----------------------------------------------------------------------------
.proc img_save_url
        ldy #0
?lp     lda url_buffer,y
        sta url_save_buf,y
        iny
        bne ?lp
        lda url_length
        sta url_save_len
        rts
.endp

.proc img_restore_url
        ldy #0
?lp     lda url_save_buf,y
        sta url_buffer,y
        iny
        bne ?lp
        lda url_save_len
        sta url_length
        rts
.endp

; ----------------------------------------------------------------------------
; Compact images (vbxe.php &c=1): the converter sends only the image's own
; width w (<= 320) instead of black-padded 320-byte rows, so narrow images
; cross SIO in fewer bytes. The rows stream to the END of the image area
; (img_stage) and one blit list moves them to centred 320-byte rows and
; blacks the margins (img_center). The move runs forward with every
; destination below its source, so no unread byte is overwritten.
; ----------------------------------------------------------------------------
IMG_ROW   = 320

.proc img_stage
        jsr img_margin         ; m = 320 - w (0: full width, nothing to do)
        beq ?done
        ; img_vram = VRAM_IMG_BASE + h * m (24-bit)
        ldx img_hdr_h
?mul    lda img_vram
        clc
        adc img_m
        sta img_vram
        lda img_vram+1
        adc img_m+1
        sta img_vram+1
        bcc ?nc
        inc img_vram+2
?nc     dex
        bne ?mul
?done   rts
.endp

; img_m = 320 - img_hdr_w; Z=1 when 0
.proc img_margin
        lda #<IMG_ROW
        sec
        sbc img_hdr_w
        sta img_m
        lda #>IMG_ROW
        sbc img_hdr_w+1
        sta img_m+1
        ora img_m
        rts
.endp

.proc img_center
        lda img_vram           ; source = the staged rows
        sta ?b_src
        lda img_vram+1
        sta ?b_src+1
        lda img_vram+2
        sta ?b_src+2
        lda #<VRAM_IMG_BASE    ; the image is shown from the base again
        sta img_vram
        lda #>VRAM_IMG_BASE
        sta img_vram+1
        lda #0
        sta img_vram+2
        jsr img_margin
        jeq ?done

        ; left = m / 2, right = m - left (>= 1)
        lda img_m+1
        lsr
        lda img_m
        ror
        sta ?left              ; m <= 312: left <= 156
        lda img_m
        sec
        sbc ?left
        sta ?right             ; right <= 156 (8-bit)

        ; BCB 1: move w x h, source step w, dest step 320, dest base+left
        lda img_hdr_w
        sta ?b_sstep
        sec
        sbc #1
        sta ?b_w1
        lda img_hdr_w+1
        sta ?b_sstep+1
        sbc #0
        sta ?b_w1+1
        ldx img_hdr_h
        dex
        stx ?b_h1
        stx ?r_h1
        stx ?l_h1
        lda #<VRAM_IMG_BASE
        clc
        adc ?left
        sta ?b_dst
        lda #>VRAM_IMG_BASE
        adc #0
        sta ?b_dst+1
        ; BCB 2: right margin at base + left + w, width right
        lda ?b_dst
        clc
        adc img_hdr_w
        sta ?r_dst
        lda ?b_dst+1
        adc img_hdr_w+1
        sta ?r_dst+1
        ldx ?right
        dex
        stx ?r_w1
        ; BCB 3: left margin at base, width left (chained only if left > 0)
        lda #0                 ; no left margin: the list ends at BCB 2
        ldx ?left
        beq ?noleft
        dex
        stx ?l_w1
        lda #8                 ; chain on
?noleft sta ?r_ctl             ; A = 0 when left = 0: the list ends here

        ; Copy the 3 BCBs to VRAM through the image writer, then run them
        ldx #?bcb_len-1
?cp     lda ?bcb,x
        sta img_big_buf,x
        dex
        bpl ?cp
        lda #?bcb_len
        sta img_chunk_lo
        lda #0
        sta img_chunk_hi
        sta img_wr_bank        ; VRAM_IMG_BCB is in bank 0
        lda #<(MEMB_BASE + VRAM_IMG_BCB)
        sta zp_img_ptr
        lda #>(MEMB_BASE + VRAM_IMG_BCB)
        sta zp_img_ptr+1
        jsr vbxe_img_write_big
        lda #<VRAM_IMG_BCB     ; started, not waited for: palette and
        ldx #>VRAM_IMG_BCB     ; status bar go on meanwhile (the next
        jmp blit_go            ; blit_run waits for it first)
?done   rts

?left   dta 0
?right  dta 0
?bcb
        ; move: staged rows -> centred rows
?b_src  dta 0, 0, 0
?b_sstep dta a(0)              ; source step Y = w
        dta 1
?b_dst  dta 0, 0, 0
        dta a(IMG_ROW)
        dta 1
?b_w1   dta a(0)               ; width - 1 = w - 1
?b_h1   dta 0
        dta $FF, $00, $00, 0, $00
        dta $08                ; chain
        ; right margin: black
        dta 0, 0, 0, a(0), 0
?r_dst  dta 0, 0, 0
        dta a(IMG_ROW)
        dta 1
?r_w1   dta a(0)
?r_h1   dta 0
        dta $00, COL_BLACK, $00, 0, $00   ; AND 0, XOR = colour: fill
?r_ctl  dta $08
        ; left margin: black
        dta 0, 0, 0, a(0), 0
        dta <VRAM_IMG_BASE, >VRAM_IMG_BASE, 0
        dta a(IMG_ROW)
        dta 1
?l_w1   dta a(0)
?l_h1   dta 0
        dta $00, COL_BLACK, $00, 0, $00
        dta $00
?bcb_len = * - ?bcb
        ert VRAM_IMG_BCB + ?bcb_len > VRAM_FONT
.endp

img_m   dta a(0)

; Image URL prefix/suffix (global, used by img_resolve_and_build_url)
m_prefix dta c'N:https://turiecfoto.sk/cactus/vbxe.php?url=',0   ; http -> 301
m_suffix dta c'&w=320&h=208&iw=320&c=1',0  ; c=1: image-wide rows (img_center)
