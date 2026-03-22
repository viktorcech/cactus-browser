; ============================================================================
; Image Fetch Module - Download and display VBXE images via FujiNet
; Format: 2B width(LE) + 1B height + 768B palette + w*h pixels
; Images shown fullscreen one at a time after page loads
; ============================================================================

img_hdr_w   dta a(0)
img_hdr_h   dta b(0)
img_pal_cnt dta a(0)
img_timeout dta b(0)
img_saved_key dta b($FF)     ; saved key from abort ($FF=none)
img_fetch_idx dta b(0)       ; current image being fetched

; Max retries before timeout (each retry ~120ms = ~40 retries = ~5 sec)
IMG_MAX_RETRIES = 40

; ----------------------------------------------------------------------------
; img_check_abort - Check if user pressed a key (non-blocking)
; Output: C=1 if key pressed (abort), C=0 continue
; ----------------------------------------------------------------------------
.proc img_check_abort
        lda CH
        cmp #KEY_NONE
        beq ?no
        ; Save key for later replay, then clear CH
        sta img_saved_key
        lda #KEY_NONE
        sta CH
        sec
        rts
?no     clc
        rts
.endp

; ----------------------------------------------------------------------------
; img_read_header - Read 3-byte image header
; Output: img_hdr_w, img_hdr_h set, C=0 ok
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
        cmp #193
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
; img_read_palette - Read 768 bytes of palette data
; Output: img_pal_buf filled, C=0 ok
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
        bcc ?lp
?done   clc
        rts

?wait   dec img_timeout
        beq ?err
        wait_frames 6
        jmp ?lp

?err    sec
        rts
.endp

; ----------------------------------------------------------------------------
; img_read_pixels - Stream pixel data into VBXE VRAM
; Output: C=0 ok
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
        lda zp_fn_bytes_lo
        ora zp_fn_bytes_hi
        beq ?no_data

        jsr fn_read
        bcs ?err
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
; img_copy_queue_url - Copy URL from img_queue_urls[img_fetch_idx] to img_src_buf
; ----------------------------------------------------------------------------
.proc img_copy_queue_url
        ; Calculate source: img_queue_urls + idx * 256
        ; idx * 256 = add idx to high byte
        lda #<img_queue_urls
        sta zp_tmp_ptr
        lda #>img_queue_urls
        clc
        adc img_fetch_idx
        sta zp_tmp_ptr+1
        ; Copy to img_src_buf
        ldy #0
?cp     lda (zp_tmp_ptr),y
        sta img_src_buf,y
        beq ?done
        iny
        bne ?cp                ; max 255 chars
?done   rts
.endp

; ----------------------------------------------------------------------------
; img_resolve_and_build_url - Resolve img_src_buf and build vbxe.php URL
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
; Called when user clicks on [N]IMG link
; ----------------------------------------------------------------------------
.proc img_fetch_single
        status_msg COL_YELLOW, m_step1

        ; Resolve relative URL and build vbxe.php converter URL
        jsr img_resolve_and_build_url

        ; Switch to N2: for image download (N1: stays open for page)
        lda #2
        sta fn_cur_unit
        jsr fn_close           ; close N2: in case left open
        wait_frames 10

        status_msg COL_YELLOW, m_step2

        ; Open connection on N2:
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

        ; Read pixels BEFORE setting palette (palette overwrites link colors)
        jsr vbxe_img_begin_write
        jsr img_read_pixels

        jsr fn_close           ; close N2:

        ; Restore N1: as active unit
        lda #FN_UNIT
        sta fn_cur_unit

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
        jsr ui_status_done
        rts

?e_open ; Restore N1: on error
        lda #FN_UNIT
        sta fn_cur_unit
        lda #<me_open
        ldx #>me_open
        jsr ui_show_error
        rts
?e_hdr  jsr fn_close           ; close N2:
        lda #FN_UNIT
        sta fn_cur_unit
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
        jsr ?hex
        sta me_hdr_h
        lda img_fn_err
        and #$0F
        jsr ?hex
        sta me_hdr_h+1
        lda #<me_hdr
        ldx #>me_hdr
        jsr ui_show_error
        rts
?hex    cmp #10
        bcc ?dig
        clc
        adc #'A'-10
        rts
?dig    clc
        adc #'0'
        rts
?e_alloc jsr fn_close
        lda #FN_UNIT
        sta fn_cur_unit
        lda #<me_alloc
        ldx #>me_alloc
        jsr ui_show_error
        rts
?e_pal  jsr fn_close
        lda #FN_UNIT
        sta fn_cur_unit
        lda #<me_pal
        ldx #>me_pal
        jsr ui_show_error
        rts

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
; img_fetch_page - Fetch and display all queued images fullscreen
; Called after page loads if img_queue_count > 0
; Each image shown on separate screen, Space=next, Q=quit
; ----------------------------------------------------------------------------
.proc img_fetch_page
        lda img_queue_count
        bne ?go
        rts
?go
        ; Clear any leftover key
        lda #KEY_NONE
        sta CH
        sta img_saved_key
        lda #0
        sta img_fetch_idx
        sta img_count

?loop   lda img_fetch_idx
        cmp img_queue_count
        bcc ?fetch
        jmp ?all_done

?fetch  jsr ui_status_img_loading

        ; Copy URL from queue
        jsr img_copy_queue_url
        ; Resolve and build vbxe.php URL
        jsr img_resolve_and_build_url

        ; Close any previous connection
        jsr fn_close
        ; Delay between connections
        wait_frames 30

        ; Open connection
        jsr fn_open
        bcc ?ok1
        jmp ?img_err

?ok1    ; Read header
        jsr img_read_header
        bcc ?ok2
        jsr fn_close
        jmp ?img_err

?ok2    ; Allocate VRAM (always at VRAM_IMG_BASE)
        lda img_hdr_h
        ldx img_hdr_w
        ldy img_hdr_w+1
        jsr vbxe_img_alloc
        bcc ?ok3
        jsr fn_close
        jmp ?img_err

?ok3    ; Read palette
        jsr img_read_palette
        bcc ?ok4
        jsr fn_close
        jmp ?img_err

?ok4    ; Read pixels BEFORE setting palette (keeps text colors during download)
        jsr vbxe_img_begin_write
        jsr img_read_pixels

        jsr fn_close

        ; Set VBXE palette AFTER pixels
        lda #<img_pal_buf
        sta zp_tmp_ptr
        lda #>img_pal_buf
        sta zp_tmp_ptr+1
        jsr vbxe_img_setpal

        ; Image loaded successfully
        inc img_count

        ; Write status text to status bar (before switching XDL)
        jsr img_show_status

        ; Show image fullscreen
        jsr vbxe_img_show_fullscreen

        ; Wait for user key
        jsr kbd_get
        cmp #'q'
        beq ?quit
        cmp #'Q'
        beq ?quit
        cmp #27                ; ESC
        beq ?quit

        ; Restore text display for next image or end
        jsr vbxe_img_hide
        jsr setup_palette

?img_next
        inc img_fetch_idx
        jmp ?loop

?img_err
        ; Skip this image, continue to next
        jmp ?img_next

?quit   ; User wants to stop - restore text display
        jsr vbxe_img_hide
        jsr setup_palette

?all_done
        jsr ui_status_done

        ; Replay any saved key
        lda img_saved_key
        cmp #KEY_NONE
        beq ?no_key
        sta CH
?no_key rts

.endp

; ----------------------------------------------------------------------------
; img_show_status - Write image status text to status bar
; Shows "Image N/M  Spc:next Q:quit" on STATUS_ROW
; ----------------------------------------------------------------------------
.proc img_show_status
        status_msg COL_YELLOW, m_imgstat
        ; Re-set yellow attr for extra text after macro
        lda #COL_YELLOW
        jsr vbxe_setattr
        ; Current number
        lda img_count
        clc
        adc #'0'
        jsr vbxe_putchar
        ; "/"
        lda #'/'
        jsr vbxe_putchar
        ; Total
        lda img_queue_count
        clc
        adc #'0'
        jsr vbxe_putchar
        ; " Spc:next Q:quit"
        lda #<m_imgkeys
        ldx #>m_imgkeys
        jsr vbxe_print
        lda #ATTR_NORMAL
        jsr vbxe_setattr
        rts

m_imgstat dta c' Image ',0
m_imgkeys dta c'  Spc:next Q:quit',0
.endp

; Image URL prefix/suffix (global, used by img_resolve_and_build_url)
m_prefix dta c'N:https://turiecfoto.sk/vbxe.php?url=',0
m_suffix dta c'&w=320&h=184&iw=320',0

; Palette buffer (768 bytes)
img_pal_buf .ds 768
