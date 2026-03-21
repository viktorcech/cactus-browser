; ============================================================================
; HTTP Module - HTTP GET workflow
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
        jsr net_open
        bcc ?opened
        jmp ?open_err
?opened
        lda #0
        sta http_idle_cnt
        sta http_bytes_lo
        sta http_bytes_hi

?rdlp   jsr net_status
        bcc ?st_ok
        jmp ?rd_err
?st_ok

        ; Check for EOF: error == 136 ($88) means end of data
        lda zp_fn_error
        cmp #136
        beq ?done

        ; Check for network error (error >= 128 is fatal, except 136=EOF)
        lda zp_fn_error
        bmi ?chk_fatal         ; bit 7 set = value >= 128
        jmp ?no_err            ; 0-127 = not an error
?chk_fatal
        cmp #136
        beq ?done              ; 136 = normal EOF
        jmp ?rd_err            ; other >= 128 = real error
?no_err
        ; Check bytes waiting FIRST (data may be buffered after disconnect)
        lda zp_fn_bytes_lo
        ora zp_fn_bytes_hi
        beq ?no_data

        ; Data available - reset idle counter
        lda #0
        sta http_idle_cnt

        jsr net_read
        bcs ?rd_err
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

        jsr html_process_chunk
        lda page_abort
        bne ?done              ; user aborted with Q
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
        ; Idle timeout: ~2 sec (30 iterations * 4 frames * 16ms)
        inc http_idle_cnt
        lda http_idle_cnt
        cmp #30
        bcs ?done              ; timeout = done (server keep-alive)

        ; Wait ~4 frames
        wait_frames 4
        jmp ?rdlp

?done   jsr net_close
        jsr html_flush
        jsr ui_status_done
        clc
        rts

?open_err
        jsr net_close
        jsr ui_status_error
        lda #<m_operr
        ldx #>m_operr
        jsr ui_show_error
        sec
        rts

?rd_err jsr net_close
        jsr ui_status_error
        lda #<m_rderr
        ldx #>m_rderr
        jsr ui_show_error
        sec
        rts

m_operr dta c'Connection failed',0
m_rderr dta c'Read error',0
http_idle_cnt dta b(0)
http_bytes_lo dta b(0)
http_bytes_hi dta b(0)
.endp

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
; http_ensure_prefix - Add "N:http://" to url_buffer if missing
; ----------------------------------------------------------------------------
.proc http_ensure_prefix
        ; Check if url_buffer starts with "N:" (already has FujiNet prefix)
        lda url_buffer
        cmp #'N'
        bne ?chkhttp
        lda url_buffer+1
        cmp #':'
        beq ?ok
?chkhttp
        ; Check if starts with "http" - need to prepend "N:" only
        lda url_buffer
        cmp #'h'
        beq ?addN
        cmp #'H'
        beq ?addN
        jmp ?addFull

        ; Has "http://..." but missing "N:" - shift by 2 and prepend "N:"
?addN   ldy url_length
        cpy #URL_BUF_SIZE-3
        bcc ?sh2
        ldy #URL_BUF_SIZE-3
?sh2    clc
        tya
        adc #2
        tax
        stx url_length
?sh2lp  dex
        dey
        bmi ?cp2
        lda url_buffer,y
        sta url_buffer,x
        jmp ?sh2lp
?cp2    lda #'N'
        sta url_buffer
        lda #':'
        sta url_buffer+1
        ldy url_length
        lda #0
        sta url_buffer,y
        sta url_length+1
        jmp ?ok

?addFull
        ; No http prefix - shift buffer right by 9 and prepend "N:http://"
        ldy url_length
        cpy #URL_BUF_SIZE-10
        bcc ?shift
        ldy #URL_BUF_SIZE-10
?shift
        clc
        tya
        adc #9
        tax                     ; X = new end position
        stx url_length
?shlp   dex
        dey
        bmi ?copy
        lda url_buffer,y
        sta url_buffer,x
        jmp ?shlp

?copy   ; Copy "N:http://" to start
        ldx #0
?cplp   lda ?prefix,x
        sta url_buffer,x
        inx
        cpx #9
        bne ?cplp
        ; Null-terminate
        ldy url_length
        lda #0
        sta url_buffer,y
        sta url_length+1
?ok     rts

?prefix dta c'N:http://'
.endp

; ----------------------------------------------------------------------------
; http_save_base - Save current url_buffer as base URL (up to last '/')
; Call BEFORE overwriting url_buffer with a new link URL
; ----------------------------------------------------------------------------
.proc http_save_base
        ; Find last '/' in url_buffer, but ignore "://" slashes
        ; Strategy: find position after "://", then last '/' after that
        ldy #0
        sty zp_tmp1            ; zp_tmp1 = index after last path '/'
        sty zp_tmp2            ; zp_tmp2 = position after "://"

        ; First find "://" to know where host starts
?find_scheme
        lda url_buffer,y
        beq ?check
        cmp #':'
        bne ?fs_next
        ; Check if followed by "//"
        iny
        lda url_buffer,y
        cmp #'/'
        bne ?fs_next
        iny
        lda url_buffer,y
        cmp #'/'
        bne ?fs_next
        iny                    ; Y = position after "://"
        sty zp_tmp2
        jmp ?scan_path
?fs_next
        iny
        bne ?find_scheme

?scan_path
        ; Now scan for '/' in the path portion (after host)
        lda url_buffer,y
        beq ?check
        cmp #'/'
        bne ?sp_next
        iny
        sty zp_tmp1            ; save position after this '/'
        dey
?sp_next
        iny
        bne ?scan_path

?check  ; If no path '/' found (zp_tmp1 <= zp_tmp2), use whole URL + "/"
        lda zp_tmp1
        cmp zp_tmp2
        bcc ?use_all
        beq ?use_all
        ; Good - copy up to last path '/'
        jmp ?copy

?use_all
        ; No path slash - copy whole URL and append "/"
        ldy #0
?ua     lda url_buffer,y
        beq ?ua_slash
        sta base_url,y
        iny
        bne ?ua
?ua_slash
        lda #'/'
        sta base_url,y
        iny
        lda #0
        sta base_url,y
        rts

?copy   ; Copy url_buffer[0..zp_tmp1-1] to base_url
        ldy #0
?cplp   cpy zp_tmp1
        beq ?term
        lda url_buffer,y
        sta base_url,y
        iny
        bne ?cplp
?term   lda #0
        sta base_url,y
        rts
.endp

; ----------------------------------------------------------------------------
; http_resolve_url - Resolve relative URL in url_buffer against base_url
; Absolute URLs (http://...) pass through unchanged
; Relative URLs get base_url prepended
; ----------------------------------------------------------------------------
.proc http_resolve_url
        ; Check if already absolute
        lda url_buffer
        cmp #'h'
        beq ?done
        cmp #'H'
        beq ?done
        cmp #'N'
        beq ?done

        ; Check if root-relative (starts with '/')
        cmp #'/'
        beq ?root_rel

        ; --- Relative URL: prepend base_url ---
        ; Step 1: copy url_buffer to rx_buffer (temp)
        ldy #0
?s1     lda url_buffer,y
        sta rx_buffer,y
        beq ?s1d
        iny
        bne ?s1
?s1d
        ; Step 2: copy base_url to url_buffer
        ldy #0
?s2     lda base_url,y
        beq ?s2d
        sta url_buffer,y
        iny
        bne ?s2
?s2d    ; Y = length of base_url
        ; Step 3: append relative URL from rx_buffer
        ldx #0
?s3     lda rx_buffer,x
        sta url_buffer,y
        beq ?upd
        iny
        inx
        cpy #URL_BUF_SIZE-1
        bne ?s3
        lda #0
        sta url_buffer,y
?upd    sty url_length
        lda #0
        sta url_length+1
?done   rts

?root_rel
        ; Root-relative: find host part in base_url
        ; Look for "://" then the next "/" after that
        ldy #0
?rr1    lda base_url,y
        beq ?rr_use_all        ; no "://" found, use whole base
        cmp #':'
        bne ?rr1n
        iny
        lda base_url,y
        cmp #'/'
        bne ?rr1n
        iny
        lda base_url,y
        cmp #'/'
        beq ?rr_found_scheme
        dey
?rr1n   iny
        bne ?rr1

?rr_found_scheme
        ; Y points to 2nd '/' of "://", skip to find host end
        iny                    ; skip past "//"
?rr2    lda base_url,y
        beq ?rr_host_end       ; end of base = host only, no path
        cmp #'/'
        beq ?rr_host_end
        iny
        bne ?rr2

?rr_host_end
        ; Y = position of '/' after host (or end of string)
        sty zp_tmp1

        ; Save original url_buffer to rx_buffer
        ldy #0
?rr3    lda url_buffer,y
        sta rx_buffer,y
        beq ?rr3d
        iny
        bne ?rr3
?rr3d
        ; Copy host part of base_url
        ldy #0
?rr4    cpy zp_tmp1
        beq ?rr4d
        lda base_url,y
        sta url_buffer,y
        iny
        bne ?rr4
?rr4d
        ; Append root-relative path from rx_buffer
        ldx #0
?rr5    lda rx_buffer,x
        sta url_buffer,y
        beq ?rr_upd
        iny
        inx
        cpy #URL_BUF_SIZE-1
        bne ?rr5
        lda #0
        sta url_buffer,y
?rr_upd sty url_length
        lda #0
        sta url_length+1
        rts

?rr_use_all
        ; Fallback: use whole base_url + url_buffer
        jmp ?s1                ; treat as relative
.endp

; ----------------------------------------------------------------------------
; http_navigate - Navigate: reset parser, fetch, render
; Input: url_buffer already set
; ----------------------------------------------------------------------------
.proc http_navigate
        jsr http_resolve_url
        jsr http_ensure_prefix
        jsr http_url_tolower
        jsr http_save_base
        ; Hide previous image if active
        lda img_active
        beq ?noimg
        jsr vbxe_img_hide
?noimg  jsr html_reset
        jsr render_reset
        jsr ui_clear_content
        jsr ui_show_url
        jsr http_get
        ; Images are now fetched on-demand via [N]IMG link clicks
        ; Show end-of-page status on status bar
        jsr ui_status_end
        rts
.endp

; ----------------------------------------------------------------------------
; http_url_tolower - Convert DOMAIN part of url_buffer to lowercase
; Only lowercases up to first '/' after "://" (path is case-sensitive!)
; ----------------------------------------------------------------------------
.proc http_url_tolower
        ldy #0
        ; Find "://" first
?fs     lda url_buffer,y
        beq ?done
        cmp #':'
        bne ?fs_n
        iny
        lda url_buffer,y
        cmp #'/'
        bne ?fs_n
        iny
        lda url_buffer,y
        cmp #'/'
        beq ?found
        dey
?fs_n   iny
        bne ?fs
        rts                    ; no "://" found, don't touch
?found  iny                    ; skip past "//"
        ; Lowercase until end of domain (next '/' or end)
?lp     lda url_buffer,y
        beq ?done
        cmp #'/'
        beq ?done              ; reached path, stop lowercasing
        cmp #'A'
        bcc ?next
        cmp #'Z'+1
        bcs ?next
        ora #$20
        sta url_buffer,y
?next   iny
        bne ?lp
?done   rts
.endp
