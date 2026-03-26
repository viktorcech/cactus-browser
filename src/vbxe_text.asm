; ============================================================================
; VBXE Text Output Module
; ============================================================================

; Row address lookup tables (MEMB_SCREEN + row * SCR_STRIDE)
row_addr_lo
        :29 dta <(MEMB_SCREEN + # * SCR_STRIDE)

row_addr_hi
        :29 dta >(MEMB_SCREEN + # * SCR_STRIDE)

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

; ----------------------------------------------------------------------------
; vbxe_read_vram - Read byte from VRAM via MEMAC B
; MUST be below $4000! Called by code above $4000 (mouse module).
; Input: zp_tmp_ptr = MEMAC B window address, Y = byte offset
; Output: A = byte read
; Clobbers: Y (via memb_on/memb_off)
; ----------------------------------------------------------------------------
.proc vbxe_read_vram
        sty vbxe_rw_off
        memb_on 0
        ldy vbxe_rw_off
        lda (zp_tmp_ptr),y
        sta vbxe_rw_val
        memb_off
        lda vbxe_rw_val
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_write_vram - Write byte to VRAM via MEMAC B
; Input: zp_tmp_ptr = MEMAC B window address, Y = byte offset, A = value
; Clobbers: A, Y (via memb_on/memb_off)
; ----------------------------------------------------------------------------
.proc vbxe_write_vram
        sta vbxe_rw_val
        sty vbxe_rw_off
        memb_on 0
        ldy vbxe_rw_off
        lda vbxe_rw_val
        sta (zp_tmp_ptr),y
        memb_off
        rts
.endp

vbxe_rw_val dta 0
vbxe_rw_off dta 0

; ----------------------------------------------------------------------------
; tab_find_next - Find next link on screen after current cursor position
; Scans VRAM attrs for any link attr ($20-$5F) different from current link.
; Wraps around to top once if no link found below current position.
; MUST be below $4000 (uses MEMAC B directly)
; Input: zp_tab_link = current link ($FF = none), zp_mouse_x/y = position
; Output: C=0 found (zp_mouse_x/y set), C=1 no link found
; ----------------------------------------------------------------------------
.proc tab_find_next
        ; Compute attr to skip (same link's continuation)
        lda zp_tab_link
        cmp #$FF
        beq ?no_cur
        clc
        adc #ATTR_LINK_BASE    ; skip current link's attr
        bne ?set_cur           ; always (result $20+)
?no_cur lda #$FF               ; $FF won't match any link attr
?set_cur sta ?skip_attr

        memb_on 0

        ; Start position: top-left if no selection, else next col
        lda zp_tab_link
        cmp #$FF
        bne ?from_cur
        ldx #CONTENT_TOP
        ldy #1                 ; first attr byte
        lda #0
        beq ?set_wrap          ; always
?from_cur
        ldx zp_mouse_y
        lda zp_mouse_x
        asl
        clc
        adc #3                 ; next column's attr offset
        tay
        cpy #SCR_STRIDE
        bcc ?ok_col
        ldy #1                 ; wrap to next row
        inx
        cpx #CONTENT_BOT+1
        bcc ?ok_col
        ldx #CONTENT_TOP       ; wrap to top
?ok_col lda #0
?set_wrap
        sta ?did_wrap

?scan_row
        lda row_addr_lo,x
        sta zp_scr_ptr
        lda row_addr_hi,x
        sta zp_scr_ptr+1

?col    lda (zp_scr_ptr),y
        cmp #ATTR_LINK_BASE
        bcc ?next
        cmp #ATTR_LINK_BASE+MAX_LINKS
        bcs ?next
        cmp ?skip_attr         ; skip same link's text
        beq ?next
        jmp ?found

?next   iny
        iny
        cpy #SCR_STRIDE
        bcc ?col

        ldy #1
        inx
        cpx #CONTENT_BOT+1
        bcc ?scan_row

        ; Bottom reached — wrap to top (once only)
        lda ?did_wrap
        bne ?none
        lda #1
        sta ?did_wrap
        ldx #CONTENT_TOP
        jmp ?scan_row

?none   memb_off
        sec
        rts

?found  ; X = row, Y = attr offset; col = (Y-1) / 2
        stx zp_mouse_y
        dey
        tya
        lsr
        sta zp_mouse_x
        memb_off
        clc
        rts

?skip_attr dta 0
?did_wrap  dta 0
.endp

; ----------------------------------------------------------------------------
; vbxe_restore_xdl - Restore normal 30-row text XDL
; MUST be below $4000 (uses MEMAC B)
; Called from ui_init (above $4000) to switch from title/image XDL
; ----------------------------------------------------------------------------
.proc vbxe_restore_xdl
        memb_on 0
        jsr setup_xdl
        memb_off
        rts
.endp
