; ============================================================================
; Renderer Module - Word-wrap, attributes, link numbering
; ============================================================================

; ----------------------------------------------------------------------------
; render_reset
; ----------------------------------------------------------------------------
.proc render_reset
        lda #CONTENT_TOP
        sta zp_render_row
        lda #0
        sta zp_render_col
        sta zp_word_len
        sta zp_indent
        sta zp_in_link
        sta zp_link_num
        sta zp_in_heading
        sta zp_in_list
        sta zp_in_bold
        sta last_was_sp
        sta title_len

        lda #ATTR_NORMAL
        sta zp_cur_attr

        lda #0
        sta zp_scroll_pos
        sta zp_scroll_pos+1
        sta zp_page_lines
        sta zp_page_lines+1
        sta page_abort
        lda #$FF
        sta pending_link
        rts
.endp

; ----------------------------------------------------------------------------
; render_char - Process char for word-wrapped output
; Input: A = character
; ----------------------------------------------------------------------------
.proc render_char
        ldx in_title
        bne ?title

        cmp #CH_SPACE
        beq ?space

        ; Non-space: add to word buffer
        ldx #0
        stx last_was_sp
        ldx zp_word_len
        cpx #WORD_BUF_SZ-1
        bcs ?skip
        sta word_buf,x
        inc zp_word_len
?skip   rts

?space  ldx last_was_sp
        bne ?skip2
        jsr render_flush_word
        lda #1
        sta last_was_sp
        lda #CH_SPACE
        jsr render_out_char
?skip2  rts

?title  ldx title_len
        cpx #78
        bcs ?skip
        sta title_buf,x
        inc title_len
        rts
.endp

; ----------------------------------------------------------------------------
; render_flush_word - Output buffered word with word-wrap
; ----------------------------------------------------------------------------
.proc render_flush_word
        lda zp_word_len
        beq ?done

        ; Check if word fits
        lda zp_render_col
        clc
        adc zp_word_len
        cmp #SCR_COLS
        bcc ?fits

        jsr render_do_nl
        jsr render_indent_out

?fits   ldx #0
?lp     cpx zp_word_len
        beq ?clr
        lda word_buf,x
        stx zp_tmp2
        jsr render_out_char
        ldx zp_tmp2
        inx
        bne ?lp

?clr    lda #0
        sta zp_word_len
        sta last_was_sp

?done   rts
.endp

; ----------------------------------------------------------------------------
; render_out_char - Put char on screen at render position
; Input: A = char
; ----------------------------------------------------------------------------
.proc render_out_char
        pha
        lda zp_render_row
        ldx zp_render_col
        jsr vbxe_setpos
        pla
        jsr vbxe_putchar

        inc zp_render_col
        lda zp_render_col
        cmp #SCR_COLS
        bcc ?ok

        jsr render_do_nl
        jsr render_indent_out
?ok     rts
.endp

; ----------------------------------------------------------------------------
; render_newline
; ----------------------------------------------------------------------------
.proc render_newline
        jsr render_flush_word
        jsr render_do_nl
        rts
.endp

; ----------------------------------------------------------------------------
; render_do_nl - Internal: advance to next line
; When content area is full, pause for user input (pagination)
; ----------------------------------------------------------------------------
.proc render_do_nl
        lda #0
        sta zp_render_col
        sta last_was_sp

        inc zp_render_row
        lda zp_render_row
        cmp #CONTENT_BOT+1
        bcc ?ok

        ; Page full - wait for user
        jsr render_page_pause
        bcs ?abort

        ; User wants next page - clear content and reset
        jsr ui_clear_content
        lda #CONTENT_TOP
        sta zp_render_row

        inc zp_page_lines
        bne ?ok
        inc zp_page_lines+1
?ok     rts

?abort  ; User pressed Q - set abort flag
        lda #1
        sta page_abort
        dec zp_render_row
        rts
.endp

; ----------------------------------------------------------------------------
; render_page_pause - Show "--More--" prompt, wait for key
; Output: C=0 continue, C=1 abort
; ----------------------------------------------------------------------------
.proc render_page_pause
        status_msg COL_YELLOW, m_more

?wait   ; Non-blocking loop: check keyboard and mouse
        ; Wait one frame (vsync)
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
        bcs ?click_cont        ; not on link — treat as "next page"
        ; A = link number — store as pending
        sta pending_link
        jmp ?next              ; continue page (will follow link after)
?click_cont
        ; Click not on link = "next page" (like Space)
        jmp ?next

?no_click
        ; Check keyboard (non-blocking via CH)
        lda CH
        cmp #KEY_NONE
        beq ?wait              ; no input, loop
        ; Key available — kbd_get returns immediately via CIO
        jsr kbd_get
        cmp #CH_SPACE
        beq ?next
        cmp #155               ; ATASCII Return
        beq ?next
        cmp #'q'
        beq ?quit
        cmp #'Q'
        beq ?quit
        jmp ?wait

?next   ; Hide mouse cursor and force redraw on next show
        jsr mouse_hide_cursor
        lda #$FF
        sta zp_mouse_prev_x   ; force full redraw in next mouse_show_cursor

        ; Restore status bar to loading
        status_msg COL_YELLOW, m_loading
        clc
        rts

?quit   jsr mouse_hide_cursor
        lda #$FF
        sta zp_mouse_prev_x   ; force full redraw
        sta pending_link       ; $FF = no pending link
        sec
        rts

m_more    dta c' -- More -- (Spc/Q)',0
m_loading dta c' Loading...',0
.endp

; ----------------------------------------------------------------------------
; render_indent_out - Output indentation spaces
; ----------------------------------------------------------------------------
.proc render_indent_out
        ldx zp_indent
        beq ?done
?lp     lda #CH_SPACE
        stx zp_tmp2
        jsr render_out_char
        ldx zp_tmp2
        dex
        bne ?lp
?done   rts
.endp

; ----------------------------------------------------------------------------
; render_set_attr - Set text attribute (A = color index)
; ----------------------------------------------------------------------------
.proc render_set_attr
        sta zp_cur_attr
        rts
.endp

; ----------------------------------------------------------------------------
; render_link_prefix - Output [N] for link
; ----------------------------------------------------------------------------
.proc render_link_prefix
        lda #'['
        jsr render_out_char
        lda zp_link_num
        jsr render_number
        lda #']'
        jsr render_out_char
        rts
.endp

; ----------------------------------------------------------------------------
; render_number - Output number 0-99 as ASCII digits
; Input: A = number
; ----------------------------------------------------------------------------
.proc render_number
        cmp #10
        bcc ?one

        ldx #0
?tens   cmp #10
        bcc ?got
        sbc #10
        inx
        bne ?tens
?got    pha
        txa
        clc
        adc #'0'
        jsr render_out_char
        pla

?one    clc
        adc #'0'
        jsr render_out_char
        rts
.endp

; ----------------------------------------------------------------------------
; render_list_bullet - Output bullet (* or number.)
; ----------------------------------------------------------------------------
.proc render_list_bullet
        jsr render_indent_out

        lda zp_list_type
        bne ?num

        lda #'*'
        jsr render_out_char
        lda #CH_SPACE
        jsr render_out_char
        rts

?num    inc zp_list_item
        lda zp_list_item
        jsr render_number
        lda #'.'
        jsr render_out_char
        lda #CH_SPACE
        jsr render_out_char
        rts
.endp

; ----------------------------------------------------------------------------
; render_string - Output ASCIIZ string (A=lo, X=hi)
; ----------------------------------------------------------------------------
.proc render_string
        sta zp_tmp_ptr
        stx zp_tmp_ptr+1
        ldy #0
?lp     lda (zp_tmp_ptr),y
        beq ?done
        sty zp_tmp2
        jsr render_out_char
        ldy zp_tmp2
        iny
        bne ?lp
?done   rts
.endp

; ----------------------------------------------------------------------------
; render_hr_line - Draw horizontal rule
; ----------------------------------------------------------------------------
.proc render_hr_line
        lda #ATTR_DECOR
        sta zp_cur_attr
        ldx #SCR_COLS
?lp     lda #'-'
        stx zp_tmp2
        jsr render_out_char
        ldx zp_tmp2
        dex
        bne ?lp
        lda #ATTR_NORMAL
        sta zp_cur_attr
        rts
.endp

; Renderer state
last_was_sp dta 0
title_len   dta 0
page_abort  dta 0
pending_link dta $FF           ; $FF = none, 0-31 = link number to follow

WORD_BUF_SZ = 80
word_buf    .ds WORD_BUF_SZ
title_buf   .ds 80
