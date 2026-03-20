; ============================================================================
; HTTP Module - HTTP GET workflow
; ============================================================================

; ----------------------------------------------------------------------------
; http_get - Fetch URL, process response through HTML parser
; Input: url_buffer, url_length set
; Output: C=0 ok, C=1 error
; ----------------------------------------------------------------------------
.proc http_get
        jsr ui_status_loading
        jsr net_open
        bcs ?open_err

?rdlp   jsr net_status
        bcs ?rd_err

        ; Check for EOF: error == 136 ($88) means end of data
        lda zp_fn_error
        cmp #136
        beq ?done

        lda zp_fn_connected
        beq ?done

        lda zp_fn_bytes_lo
        ora zp_fn_bytes_hi
        beq ?wait

        jsr net_read
        bcs ?rd_err
        lda zp_rx_len
        beq ?rdlp

        jsr html_process_chunk
        jmp ?rdlp

?wait   ldx #2
?dly    lda RTCLOK+2
?dw     cmp RTCLOK+2
        beq ?dw
        dex
        bne ?dly
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
; http_ensure_prefix - Add "http://" to url_buffer if missing
; ----------------------------------------------------------------------------
.proc http_ensure_prefix
        ; Modem mode: only need http:// prefix, no N:
        lda zp_net_device
        beq ?fujinet
        jmp ?modem_prefix

?fujinet
        ; === FujiNet mode ===
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

        ; Has "http://" but missing "N:" - shift by 2 and prepend "N:"
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

        ; No http prefix - shift buffer right by 7 and prepend "http://"
        ; First find end of string
        ldy url_length
        cpy #URL_BUF_SIZE-10
        bcc ?shift
        ; URL too long, truncate
        ldy #URL_BUF_SIZE-10
?shift
        ; Shift bytes right by 9 (from end to start)
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

        ; === Modem mode: just ensure http:// is present ===
?modem_prefix
        lda url_buffer
        cmp #'h'
        beq ?ok
        cmp #'H'
        beq ?ok
        ; Need to prepend "http://"
        ldy url_length
        cpy #URL_BUF_SIZE-8
        bcc ?mshift
        ldy #URL_BUF_SIZE-8
?mshift clc
        tya
        adc #7
        tax
        stx url_length
?mshlp  dex
        dey
        bmi ?mcopy
        lda url_buffer,y
        sta url_buffer,x
        jmp ?mshlp
?mcopy  ldx #0
?mcplp  lda ?mprefix,x
        sta url_buffer,x
        inx
        cpx #7
        bne ?mcplp
        ldy url_length
        lda #0
        sta url_buffer,y
        sta url_length+1
        rts

?mprefix dta c'http://'
.endp

; ----------------------------------------------------------------------------
; http_navigate - Navigate: reset parser, fetch, render
; Input: url_buffer already set
; ----------------------------------------------------------------------------
.proc http_navigate
        jsr http_ensure_prefix
        jsr html_reset
        jsr render_reset
        jsr ui_clear_content
        jsr ui_show_url
        jsr http_get
        rts
.endp
