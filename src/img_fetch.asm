; ============================================================================
; Image Fetch Module - Download and display VBXE images via FujiNet
; Format: 2B width(LE) + 1B height + 768B palette + w*h pixels
; Images shown fullscreen one at a time after page loads
; ============================================================================

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
        cmp #KEY_NONE
        beq ?no
        lda #KEY_NONE
        sta CH
        sec
        rts
?no     clc
        rts
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
        bmi ?chk_fatal
        jmp ?no_err
?chk_fatal
        cmp #136
        beq ?e_eof
        jmp ?e_fatal
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
        jmp ?wt

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
        cmp #1
        bne ?chk_lo
        lda img_hdr_w
        cmp #$41
        bcs ?e_san
        jmp ?chk_h
?chk_lo lda img_hdr_w
        cmp #8
        bcc ?e_san
?chk_h  lda img_hdr_h
        cmp #8
        bcc ?e_san
        cmp #209
        bcs ?e_san
        clc
        rts
?e_abort lda #1
        jmp ?fail
?e_sio  lda #2
        jmp ?fail
?e_eof  lda #3
        jmp ?fail
?e_fatal sta img_fn_err
        lda #4
        jmp ?fail
?e_disc lda #5
        jmp ?fail
?e_tout lda #6
        jmp ?fail
?e_sio2 lda #7
        jmp ?fail
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
        cmp #136
        beq ?err
        cmp #128
        bcs ?err
        lda zp_fn_bytes_lo
        ora zp_fn_bytes_hi
        beq ?wait

        jsr fn_read
        bcs ?err
        lda zp_rx_len
        beq ?lp

        lda #IMG_MAX_RETRIES
        sta img_timeout

        ldy #0
?cp     cpy zp_rx_len
        beq ?chk
        lda rx_buffer,y
        sty zp_tmp3
        ldy #0
        sta (zp_tmp_ptr),y
        ldy zp_tmp3

        inc zp_tmp_ptr
        bne ?nc1
        inc zp_tmp_ptr+1
?nc1    inc img_pal_cnt
        bne ?nc2
        inc img_pal_cnt+1
?nc2    lda img_pal_cnt+1
        cmp #3
        bcs ?done
        iny
        jmp ?cp

?chk    lda img_pal_cnt+1
        cmp #3
        bcs ?done
        jmp ?lp

?wait   dec img_timeout
        beq ?err
        wait_frames 6
        jmp ?lp

?err    lda #0
        sta img_pal_leftover   ; no leftover on error
        sec
        rts

?done   ; Palette complete — save any leftover pixel bytes in rx_buffer
        iny                    ; Y was on last palette byte, advance past it
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
.endp

; ----------------------------------------------------------------------------
; img_read_pixels - Stream pixel data into VBXE VRAM via MEMAC B
; Reads chunks from FujiNet, writes each to VRAM via vbxe_img_write_chunk
; Stops on: EOF (error 136), disconnect, timeout, user abort, or read error
; Output: C=0 ok (image complete or partial), C=1 error
; ----------------------------------------------------------------------------
.proc img_read_pixels
        lda #IMG_MAX_RETRIES
        sta img_timeout

?lp     jsr img_check_abort
        bcs ?err

        jsr fn_status
        bcs ?err
        lda zp_fn_error
        bmi ?chk_fatal
        jmp ?no_err
?chk_fatal
        cmp #136
        beq ?done
        jmp ?err
?no_err
        ; Check connected FIRST for images (unlike http_get which
        ; reads buffered data after disconnect, here TLS errors
        ; mean the buffer is unreadable → skip to avoid SIO errors)
        lda zp_fn_connected
        beq ?done

        lda zp_fn_bytes_lo
        ora zp_fn_bytes_hi
        beq ?no_data

        jsr fn_read
        bcs ?done              ; read error → show partial image
        lda zp_rx_len
        beq ?lp

        lda #IMG_MAX_RETRIES
        sta img_timeout

        jsr vbxe_img_write_chunk
        jmp ?lp

?no_data
        lda zp_fn_connected
        beq ?done

        dec img_timeout
        beq ?done

        wait_frames 6
        jmp ?lp

?done   clc
        rts
?err    sec
        rts
.endp

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
        lda #0
        sta url_length+1
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
        lda #0
        sta url_length+1
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
        bcc ?open_ok
        jmp ?e_open
?open_ok

        status_msg COL_YELLOW, m_step3

        ; Read header
        jsr img_read_header
        bcc ?hdr_ok
        jmp ?e_hdr
?hdr_ok
        ; Allocate VRAM
        lda img_hdr_h
        ldx img_hdr_w
        ldy img_hdr_w+1
        jsr vbxe_img_alloc
        bcc ?alloc_ok
        jmp ?e_alloc
?alloc_ok

        status_msg COL_YELLOW, m_step5

        ; Read palette
        jsr img_read_palette
        bcc ?pal_ok
        jmp ?e_pal
?pal_ok

        status_msg COL_YELLOW, m_step6

        ; Init write pointer
        jsr vbxe_img_begin_write

        ; Write any leftover pixel bytes from palette read
        ; (palette may end mid-chunk, remaining bytes are pixel data)
        lda img_pal_leftover
        sta zp_rx_len
        jsr vbxe_img_write_chunk   ; no-op if zp_rx_len=0

        ; Read pixels BEFORE setting palette (palette overwrites link colors)
        jsr img_read_pixels

        jsr fn_close           ; close N1: image connection

        ; Set VBXE palette AFTER pixels (keeps text colors during download)
        lda #<img_pal_buf
        sta zp_tmp_ptr
        lda #>img_pal_buf
        sta zp_tmp_ptr+1
        jsr vbxe_img_setpal

        ; Write status text
        status_msg COL_YELLOW, m_imgview

        ; Show image fullscreen
        jsr vbxe_img_show_fullscreen

        ; Wait for user key
        jsr kbd_get

        ; Clear mouse state (VBI may have set btn during image view)
        lda #0
        sta zp_mouse_btn
        lda #KEY_NONE
        sta CH

        ; Restore text display
        jsr vbxe_img_hide
        jsr setup_palette
        jsr img_restore_url
        jmp ui_status_done

?e_open jsr fn_close
        jsr img_restore_url
        lda #<me_open
        ldx #>me_open
        jmp ui_show_error
?e_hdr  jsr fn_close
        jsr img_restore_url
        ; Patch error code digit into message string
        lda img_err_code
        clc
        adc #'0'
        sta me_hdr_n
        ; Patch FN error as hex into message
        lda img_fn_err
        lsr
        lsr
        lsr
        lsr
        jsr nibble_to_hex
        sta me_hdr_h
        lda img_fn_err
        and #$0F
        jsr nibble_to_hex
        sta me_hdr_h+1
        lda #<me_hdr
        ldx #>me_hdr
        jmp ui_show_error
?e_alloc jsr fn_close
        jsr img_restore_url
        lda #<me_alloc
        ldx #>me_alloc
        jmp ui_show_error
?e_pal  jsr fn_close
        jsr img_restore_url
        lda #<me_pal
        ldx #>me_pal
        jmp ui_show_error

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
        lda url_length+1
        sta url_save_len+1
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
        lda url_save_len+1
        sta url_length+1
        rts
.endp

; Image URL prefix/suffix (global, used by img_resolve_and_build_url)
m_prefix dta c'N:http://turiecfoto.sk/vbxe.php?url=',0
m_suffix dta c'&w=320&h=208&iw=320',0
