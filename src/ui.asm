; ============================================================================
; UI Module - URL bar, status bar, navigation
; ============================================================================

; ----------------------------------------------------------------------------
; ui_init - Initialize UI layout
; ----------------------------------------------------------------------------
.proc ui_init
        jsr vbxe_cls

        ; URL bar (row 0, green)
        lda #URL_ROW
        ldx #COL_GREEN
        jsr vbxe_fill_row
        lda #URL_ROW
        ldx #0
        jsr vbxe_setpos
        lda #COL_GREEN
        jsr vbxe_setattr
        lda #<m_urlp
        ldx #>m_urlp
        jsr vbxe_print

        ; Status bar (row 23, gray)
        lda #STATUS_ROW
        ldx #COL_GRAY
        jsr vbxe_fill_row
        lda #STATUS_ROW
        ldx #0
        jsr vbxe_setpos
        lda #COL_GRAY
        jsr vbxe_setattr
        lda #<m_help
        ldx #>m_help
        jsr vbxe_print

        lda #ATTR_NORMAL
        jsr vbxe_setattr
        rts

m_urlp  dta c'URL: ',0
m_help  dta c' #:Link  U:URL  B:Back  Q:Quit  ',0
.endp

; ----------------------------------------------------------------------------
; ui_main_loop - Main keyboard event loop
; ----------------------------------------------------------------------------
.proc ui_main_loop
?loop   jsr kbd_get
        ; A = ATASCII character from K: device

        cmp #'q'
        beq ?quit
        cmp #'Q'
        beq ?quit
        cmp #'u'
        beq ?url
        cmp #'U'
        beq ?url
        cmp #'b'
        beq ?back
        cmp #'B'
        beq ?back

        cmp #'0'
        bcc ?loop
        cmp #'9'+1
        bcc ?link

        jmp ?loop

?quit   rts

?url    jsr ui_url_input
        bcs ?loop
        jsr history_push
        jsr http_navigate
        jmp ?loop

?back   jsr history_pop
        bcs ?loop
        jsr http_navigate
        jmp ?loop

?link   sec
        sbc #'0'
        sta zp_cur_link
        jsr ui_follow_link
        jmp ?loop
.endp

; ----------------------------------------------------------------------------
; ui_url_input - Prompt for URL
; Output: url_buffer set, C=0 ok, C=1 cancelled
; ----------------------------------------------------------------------------
.proc ui_url_input
        lda #URL_ROW
        ldx #COL_GREEN
        jsr vbxe_fill_row

        lda #URL_ROW
        ldx #0
        jsr vbxe_setpos
        lda #COL_GREEN
        jsr vbxe_setattr

        lda #<m_go
        ldx #>m_go
        jsr vbxe_print

        lda #<url_buffer
        sta zp_tmp_ptr
        lda #>url_buffer
        sta zp_tmp_ptr+1
        ldx #250
        jsr kbd_get_line
        bcs ?cancel

        sty url_length
        lda #0
        sta url_length+1

        jsr ui_show_url
        clc
        rts

?cancel jsr ui_show_url
        sec
        rts

m_go    dta c'Go to: ',0
.endp

; ----------------------------------------------------------------------------
; ui_follow_link - Navigate to link# in zp_cur_link
; ----------------------------------------------------------------------------
.proc ui_follow_link
        lda zp_cur_link
        cmp zp_link_num
        bcs ?bad

        ; Calculate link_urls + cur_link * 128
        lda zp_cur_link
        lsr
        tax
        lda #0
        ror
        clc
        adc #<link_urls
        sta zp_tmp_ptr
        txa
        adc #>link_urls
        sta zp_tmp_ptr+1

        ldy #0
?cp     lda (zp_tmp_ptr),y
        sta url_buffer,y
        beq ?cpdone
        iny
        cpy #URL_BUF_SIZE-1
        bne ?cp
        lda #0
        sta url_buffer,y
?cpdone sty url_length
        lda #0
        sta url_length+1

        jsr history_push
        jsr http_navigate
        rts

?bad    lda #<m_badlnk
        ldx #>m_badlnk
        jsr ui_show_error
        rts

m_badlnk dta c'Invalid link number',0
.endp

; ----------------------------------------------------------------------------
; ui_show_url - Display current URL in URL bar
; ----------------------------------------------------------------------------
.proc ui_show_url
        lda #URL_ROW
        ldx #COL_GREEN
        jsr vbxe_fill_row
        lda #URL_ROW
        ldx #0
        jsr vbxe_setpos
        lda #COL_GREEN
        jsr vbxe_setattr
        lda #<ui_init.m_urlp
        ldx #>ui_init.m_urlp
        jsr vbxe_print
        lda #<url_buffer
        ldx #>url_buffer
        jsr vbxe_print
        rts
.endp

; ----------------------------------------------------------------------------
; ui_show_title - Show page title on title row
; ----------------------------------------------------------------------------
.proc ui_show_title
        lda #TITLE_ROW
        jsr vbxe_clear_row
        lda #TITLE_ROW
        ldx #0
        jsr vbxe_setpos
        lda #ATTR_HEADING
        jsr vbxe_setattr
        lda #<title_buf
        ldx #>title_buf
        jsr vbxe_print
        lda #ATTR_NORMAL
        jsr vbxe_setattr
        rts
.endp

; ----------------------------------------------------------------------------
; ui_clear_content - Clear rows 2-22
; ----------------------------------------------------------------------------
.proc ui_clear_content
        ldx #CONTENT_TOP
?lp     txa
        pha
        jsr vbxe_clear_row
        pla
        tax
        inx
        cpx #CONTENT_BOT+1
        bne ?lp
        rts
.endp

; ----------------------------------------------------------------------------
; ui_show_error - Display error on status bar (A=lo, X=hi of msg)
; Waits for keypress, then restores status bar
; ----------------------------------------------------------------------------
.proc ui_show_error
        pha
        txa
        pha

        lda #STATUS_ROW
        ldx #COL_RED
        jsr vbxe_fill_row
        lda #STATUS_ROW
        ldx #0
        jsr vbxe_setpos
        lda #ATTR_ERROR
        jsr vbxe_setattr

        lda #<m_err
        ldx #>m_err
        jsr vbxe_print

        pla
        tax
        pla
        jsr vbxe_print
        lda #ATTR_NORMAL
        jsr vbxe_setattr

        jsr kbd_get

        ; Restore status bar
        lda #STATUS_ROW
        ldx #COL_GRAY
        jsr vbxe_fill_row
        lda #STATUS_ROW
        ldx #0
        jsr vbxe_setpos
        lda #COL_GRAY
        jsr vbxe_setattr
        lda #<ui_init.m_help
        ldx #>ui_init.m_help
        jsr vbxe_print
        rts

m_err   dta c'ERROR: ',0
.endp

; ----------------------------------------------------------------------------
; ui_status_loading
; ----------------------------------------------------------------------------
.proc ui_status_loading
        lda #STATUS_ROW
        ldx #COL_YELLOW
        jsr vbxe_fill_row
        lda #STATUS_ROW
        ldx #0
        jsr vbxe_setpos
        lda #COL_YELLOW
        jsr vbxe_setattr
        lda #<m_load
        ldx #>m_load
        jsr vbxe_print
        lda #ATTR_NORMAL
        jsr vbxe_setattr
        rts
m_load  dta c' Loading...',0
.endp

; ----------------------------------------------------------------------------
; ui_status_done - Restore status bar after loading
; ----------------------------------------------------------------------------
.proc ui_status_done
        lda #STATUS_ROW
        ldx #COL_GRAY
        jsr vbxe_fill_row
        lda #STATUS_ROW
        ldx #0
        jsr vbxe_setpos
        lda #COL_GRAY
        jsr vbxe_setattr
        lda #<ui_init.m_help
        ldx #>ui_init.m_help
        jsr vbxe_print

        lda title_len
        beq ?no
        jsr ui_show_title
?no     rts
.endp

; ----------------------------------------------------------------------------
; ui_status_error
; ----------------------------------------------------------------------------
.proc ui_status_error
        lda #STATUS_ROW
        ldx #COL_RED
        jsr vbxe_fill_row
        rts
.endp
