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
m_help  dta c' Mouse:Click link  U:URL  B:Back  Q:Quit',0
.endp

; ----------------------------------------------------------------------------
; ui_main_loop - Main keyboard event loop
; ----------------------------------------------------------------------------
.proc ui_main_loop
        ; Draw initial mouse cursor
        lda zp_mouse_y
        ldx zp_mouse_x
        jsr mouse_invert_char

?loop   ; Wait one frame (vsync)
        lda RTCLOK+2
?vs     cmp RTCLOK+2
        beq ?vs

        ; Update mouse cursor
        jsr mouse_show_cursor

        ; Check mouse button click
        lda zp_mouse_btn
        beq ?no_click
        lda #0
        sta zp_mouse_btn
        ; Is cursor over a link?
        jsr mouse_check_link
        bcs ?no_click
        ; A = link number — follow it
        sta zp_cur_link
        lda #KEY_NONE
        sta CH
        jsr mouse_hide_cursor
        jsr ui_follow_link
        jsr ?chk_pending
        lda #$FF
        sta zp_mouse_prev_x   ; force cursor redraw
        jmp ?loop

?no_click
        ; Check keyboard (non-blocking via CH)
        lda CH
        cmp #KEY_NONE
        beq ?loop              ; no key, loop

        ; Key available — kbd_get returns immediately
        jsr kbd_get

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

        jmp ?loop

        ; Q = return to welcome screen
?quit   jsr mouse_hide_cursor
        jsr net_close
        lda img_active
        beq ?qi1
        jsr vbxe_img_hide
?qi1    jsr html_reset
        jsr render_reset
        jsr ui_init
        jsr show_welcome
        lda #$FF
        sta zp_mouse_prev_x
        jmp ?loop

?url    jsr mouse_hide_cursor
        jsr ui_url_input
        bcs ?url_done
        jsr history_push
        jsr http_navigate
        jsr ?chk_pending
?url_done
        lda #$FF
        sta zp_mouse_prev_x
        jmp ?loop

?back   jsr mouse_hide_cursor
        jsr history_pop
        bcs ?back_done
        jsr http_navigate
        jsr ?chk_pending
?back_done
        lda #$FF
        sta zp_mouse_prev_x
        jmp ?loop

        ; Check if user pressed a link number during --More--
?chk_pending
        lda pending_link
        cmp #$FF
        beq ?no_pend
        sta zp_cur_link
        lda #$FF
        sta pending_link
        jsr ui_follow_link
        jsr ?chk_pending       ; recursive: follow chain of pending links
?no_pend rts
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

        ; Lowercase entire URL (Atari keyboard is uppercase)
        ldy #0
?low    lda url_buffer,y
        beq ?lowd
        cmp #'A'
        bcc ?lon
        cmp #'Z'+1
        bcs ?lon
        ora #$20
        sta url_buffer,y
?lon    iny
        bne ?low
?lowd
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

        ; Save current URL as base for relative link resolution
        jsr http_save_base

        lda zp_cur_link
        jsr calc_link_addr

        ; Check for "I:" prefix (image link)
        ldy #0
        lda (zp_tmp_ptr),y
        cmp #'I'
        bne ?normal_link
        iny
        lda (zp_tmp_ptr),y
        cmp #':'
        bne ?normal_link

        ; Image link: copy URL after "I:" to img_src_buf
        iny                        ; Y=2, skip "I:"
        ldx #0
?icp    lda (zp_tmp_ptr),y
        sta img_src_buf,x
        beq ?icpd
        iny
        inx
        cpx #IMG_SRC_SIZE-1
        bne ?icp
        lda #0
        sta img_src_buf,x
?icpd   jsr img_fetch_single
        rts

?normal_link
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
        status_msg COL_GRAY, ui_init.m_help
        rts

m_err   dta c'ERROR: ',0
.endp

; ----------------------------------------------------------------------------
; ui_status_loading
; ----------------------------------------------------------------------------
.proc ui_status_loading
        lda #$FF
        sta ui_status_progress.prog_last_kb
        status_msg COL_YELLOW, m_load
        rts
m_load  dta c' Loading...',0
.endp

; ----------------------------------------------------------------------------
; ui_status_img_loading - Show "Loading image..." on status bar
; ----------------------------------------------------------------------------
.proc ui_status_img_loading
        status_msg COL_YELLOW, m_iload
        rts
m_iload dta c' Loading image...',0
.endp

; ----------------------------------------------------------------------------
; ui_status_progress - Show "Loading... NNkB" on status bar
; Input: http_bytes_lo/hi = total bytes downloaded (16-bit)
; ----------------------------------------------------------------------------
.proc ui_status_progress
        ; Convert bytes to KB (divide by 256 = just use high byte)
        ; Show update only when KB value changes (avoid flicker)
        lda http_get.http_bytes_hi
        cmp prog_last_kb
        beq ?skip              ; same KB as last time, skip update
        sta prog_last_kb

        status_msg COL_YELLOW, m_prog

        ; Print KB number (0-255) — attr still yellow from fill_row
        lda #COL_YELLOW
        jsr vbxe_setattr
        lda prog_last_kb
        jsr ?print_num

        lda #<m_kb
        ldx #>m_kb
        jsr vbxe_print

        lda #ATTR_NORMAL
        jsr vbxe_setattr
?skip   rts

        ; Print 8-bit number in A as decimal (no leading zeros)
?print_num
        ldx #0                 ; leading zero flag
        ldy #0                 ; digit index

        ; Hundreds
        cmp #100
        bcc ?tens
        ldx #1                 ; got non-zero digit
?h_lp   cmp #100
        bcc ?h_done
        sbc #100
        iny
        jmp ?h_lp
?h_done pha
        tya
        clc
        adc #'0'
        jsr vbxe_putchar
        pla
        ldy #0

        ; Tens
?tens   cmp #10
        bcc ?ones
        ldx #1
?t_lp   cmp #10
        bcc ?t_done
        sbc #10
        iny
        jmp ?t_lp
?t_done pha
        tya
        clc
        adc #'0'
        jsr vbxe_putchar
        pla
        jmp ?do_ones

        ; Ones (always print)
?ones   cpx #0
        beq ?do_ones
        pha
        lda #'0'
        jsr vbxe_putchar
        pla
?do_ones clc
        adc #'0'
        jsr vbxe_putchar
        rts

m_prog  dta c' Loading... ',0
m_kb    dta c'kB',0
prog_last_kb dta b($FF)
.endp

; ----------------------------------------------------------------------------
; ui_status_done - Restore status bar after loading
; ----------------------------------------------------------------------------
.proc ui_status_done
        status_msg COL_GRAY, ui_init.m_help
        lda title_len
        beq ?no
        jsr ui_show_title
?no     rts
.endp

; ----------------------------------------------------------------------------
; ui_status_end - Show end-of-page indicator on status bar
; ----------------------------------------------------------------------------
.proc ui_status_end
        status_msg COL_GRAY, m_end
        lda title_len
        beq ?no
        jsr ui_show_title
?no     rts

m_end   dta c' -- End -- Q:Quit U:URL B:Back',0
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
