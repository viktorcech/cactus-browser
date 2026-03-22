; ============================================================================
; HTTP Module - HTTP GET workflow
; URL utilities in url.asm
; ============================================================================

; ----------------------------------------------------------------------------
; http_get - Fetch URL, process response through HTML parser
; Input: url_buffer, url_length set
; Output: C=0 ok, C=1 error
; ----------------------------------------------------------------------------
.proc http_get
        lda #KEY_NONE
        sta CH                 ; clear any leftover keypress
        jsr ui_status_loading
        jsr fn_open
        bcc ?opened
        jmp ?open_err
?opened
        lda #0
        sta http_idle_cnt
        sta http_bytes_lo
        sta http_bytes_hi
        sta http_remain_lo     ; remaining bytes from last STATUS
        sta http_remain_hi

        ; --- Main read loop ---
        ; Optimization: after STATUS reports N bytes, read multiple
        ; 255-byte chunks without re-calling STATUS. Saves ~7ms per
        ; skipped STATUS call (significant for large pages).

?rdlp   ; Check if we still have remaining bytes from previous STATUS
        lda http_remain_lo
        ora http_remain_hi
        bne ?do_read           ; skip STATUS, read directly

        ; No remaining - need STATUS to check state
        jsr fn_status
        bcc ?st_ok
        jmp ?rd_err
?st_ok
        ; Check error byte from FujiNet status
        lda zp_fn_error
        beq ?no_err            ; 0 = no error
        cmp #136
        beq ?jdone             ; 136 ($88) = normal EOF
        bmi ?jrd_err           ; >= 128 = fatal network error
        jmp ?no_err            ; 1-127 = not fatal
?jdone  jmp ?done
?jrd_err jmp ?rd_err
?no_err
        ; Check bytes waiting FIRST (data may be buffered after disconnect)
        lda zp_fn_bytes_lo
        ora zp_fn_bytes_hi
        bne ?has_data
        jmp ?no_data
?has_data

        ; Store remaining bytes from STATUS
        lda zp_fn_bytes_lo
        sta http_remain_lo
        lda zp_fn_bytes_hi
        sta http_remain_hi

?do_read
        ; Data available - reset idle counter
        lda #0
        sta http_idle_cnt

        ; Set fn_read input from remaining (fn_read caps at 255)
        lda http_remain_lo
        sta zp_fn_bytes_lo
        lda http_remain_hi
        sta zp_fn_bytes_hi

        jsr fn_read
        bcc ?rd_ok
        ; Read failed - clear remaining, report error
        lda #0
        sta http_remain_lo
        sta http_remain_hi
        jmp ?rd_err
?rd_ok
        ; Subtract read bytes from remaining
        lda http_remain_lo
        sec
        sbc zp_rx_len
        sta http_remain_lo
        bcs ?no_borrow
        dec http_remain_hi
?no_borrow

        lda zp_rx_len
        beq ?rdlp

        ; Track downloaded bytes and update status bar
        lda http_bytes_lo
        clc
        adc zp_rx_len
        sta http_bytes_lo
        bcc ?no_ov
        inc http_bytes_hi
?no_ov  jsr ui_status_progress

        ; Download limit: 255kB (counter resets at <body>)
        ; User can abort anytime with a key press
        lda http_bytes_hi
        cmp #255
        bcc ?past_limit
        jmp ?done
?past_limit

        jsr html_process_chunk
        lda page_abort
        bne ?done              ; user aborted with Q

        ; Check keyboard abort during active download
        ; (not just idle - user must be able to cancel anytime)
        lda CH
        cmp #KEY_NONE
        bne ?chk_key
        jmp ?rdlp
?chk_key
        cmp #KEY_SPACE         ; ignore Space auto-repeat
        beq ?clr_dl
        cmp #KEY_RETURN        ; ignore Return auto-repeat
        beq ?clr_dl
        lda #1
        sta page_abort
        jmp ?done
?clr_dl lda #KEY_NONE
        sta CH
        jmp ?rdlp

?no_data
        ; No bytes waiting - check if still connected
        lda zp_fn_connected
        beq ?done              ; not connected + no data = truly done

        ; Check keyboard only when idle (no data flowing)
        lda CH
        cmp #KEY_NONE
        beq ?no_key
        cmp #KEY_SPACE         ; ignore Space auto-repeat from --More--
        beq ?clr_sp
        cmp #KEY_RETURN        ; ignore Return auto-repeat too
        beq ?clr_sp
        ; Real key pressed: abort download, keep key in CH
        lda #1
        sta page_abort
        jmp ?done
?clr_sp lda #KEY_NONE
        sta CH                 ; clear auto-repeat Space/Return
?no_key
        ; Idle timeout: ~2.4 sec (120 iterations * 1 frame * 20ms PAL)
        inc http_idle_cnt
        lda http_idle_cnt
        cmp #120
        bcs ?done              ; timeout = done (server keep-alive)

        ; Wait 1 frame (faster idle response)
        wait_frames 1
        jmp ?rdlp

?done   jsr fn_close
        jsr html_flush
        jsr ui_status_done
        clc
        rts

?open_err
        jsr fn_close
        jsr ui_status_error
        lda #<m_operr
        ldx #>m_operr
        jsr ui_show_error
        sec
        rts

?rd_err lda zp_fn_error
        sta m_rderr_code       ; save error code for display
        jsr fn_close
        jsr ui_status_error
        ; Format error code into message
        lda m_rderr_code
        lsr
        lsr
        lsr
        lsr
        jsr ?hex
        sta m_rderr_hex
        lda m_rderr_code
        and #$0F
        jsr ?hex
        sta m_rderr_hex+1
        lda #<m_rderr
        ldx #>m_rderr
        jsr ui_show_error
        sec
        rts
?hex    cmp #10
        bcc ?dig
        clc
        adc #'A'-10
        rts
?dig    clc
        adc #'0'
        rts

m_operr dta c'Connection failed',0
m_rderr dta c'Read err $'
m_rderr_hex dta c'00',0
m_rderr_code dta b(0)
http_idle_cnt dta b(0)
.endp

; Global so html_tags.asm can reset them at <body>
http_bytes_lo dta b(0)
http_bytes_hi dta b(0)
; Global so render_page_pause can reset after img_fetch
http_remain_lo dta b(0)
http_remain_hi dta b(0)

; ----------------------------------------------------------------------------
; http_set_url - Copy URL string to url_buffer (A=lo, X=hi)
; ----------------------------------------------------------------------------
.proc http_set_url
        sta zp_tmp_ptr
        stx zp_tmp_ptr+1
        ldy #0
?lp     lda (zp_tmp_ptr),y
        sta url_buffer,y
        beq ?done
        iny
        cpy #URL_BUF_SIZE-1
        bne ?lp
        lda #0
        sta url_buffer,y
?done   sty url_length
        lda #0
        sta url_length+1
        rts
.endp

; ----------------------------------------------------------------------------
; http_navigate - Navigate: reset parser, fetch, render
; Input: url_buffer already set
; ----------------------------------------------------------------------------
.proc http_navigate
        jsr http_ensure_prefix
        jsr http_url_tolower
        jsr http_save_base

        ; Check if URL points to an image file
        jsr http_check_img_ext
        bcc ?not_img
        ; Image URL: copy to img_src_buf (strip N: prefix) and fetch
        ldy #0
        lda url_buffer
        cmp #'N'
        bne ?ci_nb
        lda url_buffer+1
        cmp #':'
        bne ?ci_nb
        ldy #2
?ci_nb  ldx #0
?ci_cp  lda url_buffer,y
        sta img_src_buf,x
        beq ?ci_go
        iny
        inx
        cpx #IMG_SRC_SIZE-1
        bne ?ci_cp
        lda #0
        sta img_src_buf,x
?ci_go  jsr img_fetch_single
        rts

?not_img
        ; Hide previous image if active
        lda img_active
        beq ?noimg
        jsr vbxe_img_hide
?noimg  jsr html_reset
        jsr render_reset
        jsr ui_clear_content
        jsr ui_show_url

        jsr http_get
        ; Show end-of-page status on status bar
        jsr ui_status_end
        rts
.endp
