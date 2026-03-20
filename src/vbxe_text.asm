; ============================================================================
; VBXE Text Output Module
; ============================================================================

; Row address lookup tables (MEMB_SCREEN + row * SCR_STRIDE)
row_addr_lo
        :24 dta <(MEMB_SCREEN + # * SCR_STRIDE)

row_addr_hi
        :24 dta >(MEMB_SCREEN + # * SCR_STRIDE)

; ----------------------------------------------------------------------------
; calc_scr_ptr - Calculate screen pointer for cursor position
; ----------------------------------------------------------------------------
.proc calc_scr_ptr
        ldx zp_cursor_row
        lda row_addr_lo,x
        sta zp_scr_ptr
        lda row_addr_hi,x
        sta zp_scr_ptr+1
        lda zp_cursor_col
        asl
        clc
        adc zp_scr_ptr
        sta zp_scr_ptr
        bcc ?ok
        inc zp_scr_ptr+1
?ok     rts
.endp

; ----------------------------------------------------------------------------
; vbxe_setpos - Set cursor position (A=row, X=col)
; ----------------------------------------------------------------------------
.proc vbxe_setpos
        sta zp_cursor_row
        stx zp_cursor_col
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_setattr - Set text attribute (A=color index)
; ----------------------------------------------------------------------------
.proc vbxe_setattr
        sta zp_cur_attr
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_putchar - Write char at cursor with current attribute
; Input: A = ASCII character. Advances cursor, wraps lines.
; ----------------------------------------------------------------------------
.proc vbxe_putchar
        pha
        memb_on 0
        jsr calc_scr_ptr

        pla
        ldy #0
        sta (zp_scr_ptr),y
        iny
        lda zp_cur_attr
        sta (zp_scr_ptr),y

        memb_off

        inc zp_cursor_col
        lda zp_cursor_col
        cmp #SCR_COLS
        bcc ?done

        lda #0
        sta zp_cursor_col
        inc zp_cursor_row
        lda zp_cursor_row
        cmp #SCR_ROWS
        bcc ?done

        dec zp_cursor_row
        jsr vbxe_scroll_up

?done   rts
.endp

; ----------------------------------------------------------------------------
; vbxe_print - Write ASCIIZ string (A=lo, X=hi of pointer)
; ----------------------------------------------------------------------------
.proc vbxe_print
        sta zp_tmp_ptr
        stx zp_tmp_ptr+1
        lda #0
        sta zp_tmp3
?lp     ldy zp_tmp3
        lda (zp_tmp_ptr),y
        beq ?done
        jsr vbxe_putchar
        inc zp_tmp3
        bne ?lp
?done   rts
.endp

; ----------------------------------------------------------------------------
; vbxe_cls - Clear screen using blitter
; ----------------------------------------------------------------------------
.proc vbxe_cls
        memb_on 0
        lda #CH_SPACE
        sta MEMB_PATTERN
        lda #COL_BLACK
        sta MEMB_PATTERN+1
        memb_off

        blit_start (VRAM_BCB + BCB_CLS_OFS)
        blit_wait

        lda #0
        sta zp_cursor_row
        sta zp_cursor_col
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_scroll_up - Scroll screen up 1 row via chained blitter
; ----------------------------------------------------------------------------
.proc vbxe_scroll_up
        blit_start (VRAM_BCB + BCB_SCROLL_OFS)
        blit_wait
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_newline - Move cursor to start of next line, scroll if needed
; ----------------------------------------------------------------------------
.proc vbxe_newline
        lda #0
        sta zp_cursor_col
        inc zp_cursor_row
        lda zp_cursor_row
        cmp #SCR_ROWS
        bcc ?ok
        dec zp_cursor_row
        jsr vbxe_scroll_up
?ok     rts
.endp

; ----------------------------------------------------------------------------
; vbxe_clear_row - Clear one row (A=row number)
; ----------------------------------------------------------------------------
.proc vbxe_clear_row
        sta zp_tmp1
        memb_on 0

        ldx zp_tmp1
        lda row_addr_lo,x
        sta zp_scr_ptr
        lda row_addr_hi,x
        sta zp_scr_ptr+1

        ldy #0
?lp     lda #CH_SPACE
        sta (zp_scr_ptr),y
        iny
        lda #COL_BLACK
        sta (zp_scr_ptr),y
        iny
        cpy #SCR_STRIDE
        bne ?lp

        memb_off
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_fill_row - Fill row with color (A=row, X=color index)
; ----------------------------------------------------------------------------
.proc vbxe_fill_row
        sta zp_tmp1
        stx zp_tmp2
        memb_on 0

        ldx zp_tmp1
        lda row_addr_lo,x
        sta zp_scr_ptr
        lda row_addr_hi,x
        sta zp_scr_ptr+1

        ldy #0
?lp     lda #CH_SPACE
        sta (zp_scr_ptr),y
        iny
        lda zp_tmp2
        sta (zp_scr_ptr),y
        iny
        cpy #SCR_STRIDE
        bne ?lp

        memb_off
        rts
.endp
