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
; ----------------------------------------------------------------------------
.proc render_do_nl
        lda #0
        sta zp_render_col
        sta last_was_sp

        inc zp_render_row
        lda zp_render_row
        cmp #CONTENT_BOT+1
        bcc ?ok
        jsr scroll_content
        dec zp_render_row
?ok     rts
.endp

; ----------------------------------------------------------------------------
; scroll_content - Scroll content area (rows 2-22) up by 1
; ----------------------------------------------------------------------------
.proc scroll_content
        memb_on 0

        ldx #CONTENT_TOP
?rowlp  cpx #CONTENT_BOT
        beq ?clrlast

        stx zp_tmp1
        ; Source = row X+1
        inx
        lda row_addr_lo,x
        sta zp_tmp_ptr
        lda row_addr_hi,x
        sta zp_tmp_ptr+1
        ; Dest = row X (tmp1)
        ldx zp_tmp1
        lda row_addr_lo,x
        sta zp_tmp_ptr2
        lda row_addr_hi,x
        sta zp_tmp_ptr2+1

        ldy #0
?cp     lda (zp_tmp_ptr),y
        sta (zp_tmp_ptr2),y
        iny
        cpy #SCR_STRIDE
        bne ?cp

        inx
        bne ?rowlp

?clrlast
        lda row_addr_lo,x
        sta zp_tmp_ptr2
        lda row_addr_hi,x
        sta zp_tmp_ptr2+1

        ldy #0
?cl     lda #CH_SPACE
        sta (zp_tmp_ptr2),y
        iny
        lda #COL_BLACK
        sta (zp_tmp_ptr2),y
        iny
        cpy #SCR_STRIDE
        bne ?cl

        memb_off

        inc zp_page_lines
        bne ?ok
        inc zp_page_lines+1
?ok     rts
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

WORD_BUF_SZ = 80
word_buf    .ds WORD_BUF_SZ
title_buf   .ds 80
