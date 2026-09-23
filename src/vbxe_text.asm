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
 .if 1                          ; 2026-09-23 (6502-idioms: compute in A, store once): col*2 added
                                ; to the row low byte in A, no inc in memory; asl of col <= 79 leaves C = 0
        ldx zp_cursor_row
        lda zp_cursor_col
        asl                    ; col <= 79: C = 0
        adc row_addr_lo,x
        sta zp_scr_ptr
        lda row_addr_hi,x
        adc #0
        sta zp_scr_ptr+1
        rts
 .else
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
 .endif
.endp

; ----------------------------------------------------------------------------
; vbxe_setpos - Set cursor position (A=row, X=col)
; ----------------------------------------------------------------------------
.proc vbxe_setpos
        sta zp_cursor_row
        stx zp_cursor_col
        jmp calc_scr_ptr       ; precalculate screen pointer
.endp

; ----------------------------------------------------------------------------
; vbxe_putchar - Write char at cursor with current attribute
; Input: A = ASCII character. Advances cursor, wraps lines. Preserves X.
; ----------------------------------------------------------------------------
.proc vbxe_putchar
 .if 1                          ; 2026-09-23 (6502-idioms: jsr X / rts -> jmp X)
        pha
        memb_on 0
        pla
        ldy #0
        sta (zp_scr_ptr),y    ; write char (ptr precalculated by setpos)
        iny
        lda zp_cur_attr
        sta (zp_scr_ptr),y    ; write attr
        memb_off

        ; Advance screen pointer by 2 (next char+attr position)
        lda zp_scr_ptr
        clc
        adc #2
        sta zp_scr_ptr
        bcc ?nc
        inc zp_scr_ptr+1
?nc     inc zp_cursor_col
        lda zp_cursor_col
        cmp #SCR_COLS
        bcc ?done
        lda #0
        sta zp_cursor_col
        inc zp_cursor_row
        lda zp_cursor_row
        cmp #SCR_ROWS
        bcc ?recalc
        dec zp_cursor_row
        jsr vbxe_scroll_up
?recalc jmp calc_scr_ptr       ; recalculate for new row
?done   rts
 .else
        pha
        memb_on 0

        pla
        ldy #0
        sta (zp_scr_ptr),y    ; write char (ptr precalculated by setpos)
        iny
        lda zp_cur_attr
        sta (zp_scr_ptr),y    ; write attr

        memb_off

        ; Advance screen pointer by 2 (next char+attr position)
        lda zp_scr_ptr
        clc
        adc #2
        sta zp_scr_ptr
        bcc ?nc
        inc zp_scr_ptr+1
?nc     inc zp_cursor_col
        lda zp_cursor_col
        cmp #SCR_COLS
        bcc ?done

        lda #0
        sta zp_cursor_col
        inc zp_cursor_row
        lda zp_cursor_row
        cmp #SCR_ROWS
        bcc ?recalc

        dec zp_cursor_row
        jsr vbxe_scroll_up
?recalc jsr calc_scr_ptr       ; recalculate for new row
?done   rts
 .endif
.endp

; ----------------------------------------------------------------------------
; vbxe_emit - Write X chars from print_buf at the cursor (attr zp_cur_attr),
; advancing and wrapping the cursor exactly like X calls of vbxe_putchar,
; but inside one MEMAC B session. X = 1..128. MEMAC B must be on.
; ----------------------------------------------------------------------------
.proc vbxe_emit
        stx ?cnt
        lda zp_cur_attr
        sta ?attr+1
        ldx #0
?run    lda #SCR_COLS
        sec
        sbc zp_cursor_col      ; cells left on this row (1..80)
        sta ?room
        ldy #0
?lp     lda print_buf,x
        sta (zp_scr_ptr),y
        iny
?attr   lda #0
        sta (zp_scr_ptr),y
        iny
        inx
        dec ?room
        beq ?eol
        cpx ?cnt
        bne ?lp
        ert >?lp <> >*         ; hot loop: keep it in one page
        ; fall into ?adv, then return

?adv    tya                    ; ptr += Y, col += Y/2 (Y <= 160)
        clc
        adc zp_scr_ptr
        sta zp_scr_ptr
        bcc ?n
        inc zp_scr_ptr+1
?n      tya
        lsr
        adc zp_cursor_col      ; C = 0 (Y even)
        sta zp_cursor_col
        rts

?eol    jsr ?adv               ; row filled: wrap like putchar
        lda #0
        sta zp_cursor_col
        inc zp_cursor_row
        lda zp_cursor_row
        cmp #SCR_ROWS
        bcc ?rc
        dec zp_cursor_row
        jsr vbxe_scroll_up
?rc     stx ?x
        jsr calc_scr_ptr
        ldx ?x
        cpx ?cnt
        bne ?run
        rts

?cnt    dta 0
?room   dta 0
?x      dta 0
.endp

; ----------------------------------------------------------------------------
; vbxe_fill_char - Write X copies of char A at the cursor (X = 1..80)
; Safe to call from above $4000 (this code is below $4000)
; ----------------------------------------------------------------------------
.proc vbxe_fill_char
 .if 1                          ; 2026-09-23 (vbxe: cells staged in print_buf, written by vbxe_emit
                                ; in one MEMAC session; was one putchar_fast call per cell)
        stx ?n
?f      dex
        sta print_buf,x
        bne ?f
        memb_on 0
        ldx ?n
        jsr vbxe_emit
        memb_off
        rts
?n      dta 0
 .else
        sta ?ch
        stx ?cnt
        memb_on 0
        ldx ?cnt
?lp     lda ?ch
        jsr ?putchar_fast
        dex
        bne ?lp
        memb_off
        rts
?ch     dta 0
?cnt    dta 0

; vbxe_putchar_fast - Write char (MEMAC B must already be on)
?putchar_fast
        ldy #0
        sta (zp_scr_ptr),y    ; write char
        iny
        lda zp_cur_attr
        sta (zp_scr_ptr),y    ; write attr
        lda zp_scr_ptr
        clc
        adc #2
        sta zp_scr_ptr
        bcc ?nc
        inc zp_scr_ptr+1
?nc     inc zp_cursor_col
        lda zp_cursor_col
        cmp #SCR_COLS
        bcc ?done
        lda #0
        sta zp_cursor_col
        inc zp_cursor_row
        lda zp_cursor_row
        cmp #SCR_ROWS
        bcc ?recalc
        dec zp_cursor_row
        jsr vbxe_scroll_up
?recalc jsr calc_scr_ptr
?done   rts
 .endif
.endp

; ----------------------------------------------------------------------------
; vbxe_put_word - Write zp_word_len chars from word_buf at the cursor, and a
; trailing space when C = 1, in one MEMAC B session (same result as the
; putchar calls it replaces). Caller guarantees 1 <= len and col+len < 80.
; word_buf lives above $7FFF (data.asm): readable with the window open.
; MUST be below $4000.
; ----------------------------------------------------------------------------
.proc vbxe_put_word
 .if 1                          ; 2026-09-23 (6502-loops-tables-smc: attribute as an SMC immediate;
                                ; C = 1 also writes the trailing space in the same MEMAC session).
                                ; Pairs with render_space / render_flush_word (renderer.asm): flip together
 .if 1                          ; 2026-09-23 (6502-loops-tables-smc: word length as a cpx # operand)
        lda zp_word_len
        sta ?len+1             ; loop end as an immediate (2 cycles, not 3)
        adc #0                 ; n = len + C
        sta ?n
        lda zp_cur_attr
        sta ?attr+1
        memb_on 0
        ldy #0
        ldx #0
?lp     lda word_buf,x
        sta (zp_scr_ptr),y
        iny
?attr   lda #0
        sta (zp_scr_ptr),y
        iny
        inx
?len    cpx #0
        bne ?lp
 .else
        lda zp_word_len
        adc #0                 ; n = len + C
        sta ?n
        lda zp_cur_attr
        sta ?attr+1
        memb_on 0
        ldy #0
        ldx #0
?lp     lda word_buf,x
        sta (zp_scr_ptr),y
        iny
?attr   lda #0
        sta (zp_scr_ptr),y
        iny
        inx
        cpx zp_word_len
        bne ?lp
 .endif
        ert >?lp <> >*         ; hot loop: keep it in one page
        cpx ?n
        beq ?nosp
        lda #CH_SPACE
        sta (zp_scr_ptr),y
        iny
        lda ?attr+1
        sta (zp_scr_ptr),y
?nosp   memb_off
        lda ?n                 ; ptr += 2n, col += n
        asl                    ; n <= 80: C = 0
        adc zp_scr_ptr
        sta zp_scr_ptr
        bcc ?nc
        inc zp_scr_ptr+1
?nc     lda zp_cursor_col
        clc
        adc ?n
        sta zp_cursor_col
        cmp #SCR_COLS
        bcc ?done
        lda #0                 ; the space took column 79: wrap
        sta zp_cursor_col      ; (row <= 27 here, no scroll)
        inc zp_cursor_row
        jmp calc_scr_ptr
?done   rts
?n      dta 0
 .else
        ldx zp_word_len
        beq ?done
        memb_on 0
        ldy #0
        ldx #0
?lp     lda word_buf,x
        sta (zp_scr_ptr),y     ; char
        iny
        lda zp_cur_attr
        sta (zp_scr_ptr),y     ; attr
        iny
        inx
        cpx zp_word_len
        bne ?lp
        memb_off
        ; Advance screen pointer by 2*len and cursor by len
        lda zp_word_len
        asl                    ; len <= 79 -> no carry out
        adc zp_scr_ptr
        sta zp_scr_ptr
        bcc ?nc
        inc zp_scr_ptr+1
?nc     lda zp_cursor_col
        clc
        adc zp_word_len
        sta zp_cursor_col
?done   rts
 .endif
.endp

; ----------------------------------------------------------------------------
; vbxe_print - Write ASCIIZ string (A=lo, X=hi of pointer)
; Copies up to 128 chars at a time to print_buf (the string may sit inside
; the MEMAC B window), then writes them in one MEMAC session.
; ----------------------------------------------------------------------------
 .if 1                          ; 2026-09-23 (6502-cycles-layout: the copy loop and its exit in one page)
        page_fit vbxe_print.pl_s-vbxe_print, vbxe_print.pl_e-vbxe_print.pl_s
 .endif
.proc vbxe_print
 .if 1                          ; 2026-09-23 (vbxe: one MEMAC session per 128 chars instead of one
                                ; per char; print -47 %)
        sta zp_tmp_ptr
        stx zp_tmp_ptr+1
        sta ?src+1
        stx ?src+2
?chunk  ldx #0
pl_s
?src    lda $FFFF,x
        beq ?last
        sta print_buf,x
        inx
        bpl ?src
        jsr ?out               ; 128 chars: write them, next chunk
        lda ?src+1
        eor #$80               ; src += 128
        sta ?src+1
        bmi ?chunk
        inc ?src+2
        bne ?chunk             ; always
?last   txa
pl_e
        beq ?done
?out    memb_on 0
        jsr vbxe_emit
        memb_off
?done   rts
 .else
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
 .endif
.endp

; ----------------------------------------------------------------------------
; blit_run - Run the BCB list at VRAM A/X (bank 0) and wait for it
; blit_go  - Start it and return at once ("fire early, wait late"): only
;            when the CPU does not touch the blit's destination next.
; A START while the blitter runs is ignored, so a blit started by blit_go
; is waited for (blit_pending) before the next START.
; BUSY can read 0 for an instant between chained BCBs: two reads.
; ----------------------------------------------------------------------------
 .if 1                          ; 2026-09-23 (6502-cycles-layout: keep the BUSY poll loop in one page)
        page_fit blit_idle.wt-blit_run, blit_idle.wt_end-blit_idle.wt
 .endif
.proc blit_run
        ldy blit_pending
        beq ?go
        pha                    ; a blit_go blit may still run
        jsr blit_idle
        pla
?go     ldy #VBXE_BL_ADR0
        sta (zp_vbxe_base),y
        iny
        txa
        sta (zp_vbxe_base),y
        iny
        lda #0
        sta (zp_vbxe_base),y
        iny
        lda #1
        sta (zp_vbxe_base),y   ; Y = VBXE_BLITTER: start
.endp
        ; fall through: wait for it
.proc blit_idle
        ldy #VBXE_BLITTER
wt
?w      lda (zp_vbxe_base),y
        bne ?w
        lda (zp_vbxe_base),y
        bne ?w
wt_end
        ert >wt <> >(wt_end-1)
        sta blit_pending       ; A = 0: nothing running any more
        rts
.endp

.proc blit_go
        ldy blit_pending
        beq ?go
        pha
        jsr blit_idle
        pla
?go     jsr blit_kick
        inc blit_pending       ; 0 -> 1: running, not waited for
        rts
.endp

 .if 1                          ; 2026-09-23 (vbxe-blitter: fire early, wait late)
; blit_sync - Wait for a started blit, if any (before the CPU touches its cells)
.proc blit_sync
        ldy blit_pending
        bne blit_idle
        rts
.endp
 .endif

; blit_kick - BL_ADR = A/X (bank 0), START
.proc blit_kick
        ldy #VBXE_BL_ADR0
        sta (zp_vbxe_base),y
        iny
        txa
        sta (zp_vbxe_base),y
        iny
        lda #0
        sta (zp_vbxe_base),y
        iny
        lda #1
        sta (zp_vbxe_base),y   ; Y = VBXE_BLITTER: start
        rts
.endp

blit_pending dta 0

; ----------------------------------------------------------------------------
; vbxe_cls - Clear screen using blitter (constant fills: chars, attrs)
; ----------------------------------------------------------------------------
.proc vbxe_cls
 .if 1                          ; 2026-09-23 (vbxe-blitter: constant fills, AND 0 / XOR value, 1 cycle
                                ; a byte, no pattern reads; cls -45 %). Pairs with the BCB table (vbxe_init)
        blit VRAM_BCB+BCB_CLS_OFS
        lda #0
        sta zp_cursor_row
        sta zp_cursor_col
        rts
 .else
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
 .endif
.endp

; ----------------------------------------------------------------------------
; vbxe_scroll_up - Scroll screen up 1 row via chained blitter
; ----------------------------------------------------------------------------
.proc vbxe_scroll_up
 .if 1                          ; 2026-09-23 (vbxe-blitter: shared blit_run)
        blit VRAM_BCB+BCB_SCROLL_OFS
        rts
 .else
        blit_start (VRAM_BCB + BCB_SCROLL_OFS)
        blit_wait
        rts
 .endif
.endp

; ----------------------------------------------------------------------------
; ui_clear_content - Clear content rows (CONTENT_TOP..CONTENT_BOT), one blit
; ----------------------------------------------------------------------------
.proc ui_clear_content
 .if 1                          ; 2026-09-23 (vbxe-blitter: the 25 content rows are one blit list;
                                ; 52k CPU cycles -> ~750). Was in ui.asm
        blit VRAM_BCB+BCB_CONTENT_OFS
        rts
 .else
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
 .endif
.endp

; ----------------------------------------------------------------------------
; vbxe_clear_row - Clear one row (A=row number)
; vbxe_fill_row  - Fill row with spaces in color X (A=row)
; One blit list: characters (space) and attributes (XOR = colour), each a
; constant fill; only the two destinations and the colour are written.
; ----------------------------------------------------------------------------
.proc vbxe_clear_row
 .if 1                          ; 2026-09-23 (vbxe-blitter: a blit through vbxe_fill_row)
        ldx #COL_BLACK
 .else
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
 .endif
.endp
        ; fall through
.proc vbxe_fill_row
 .if 1                          ; 2026-09-23 (vbxe-blitter: one blit, only the 2 destinations and the
                                ; colour written into the BCB templates; fill_row -92 %)
        sta zp_tmp1
        memb_on 0
        stx MEMB_BCB+BCB_ROW_OFS+21+16   ; attribute BCB XOR = colour
        ldx zp_tmp1
        lda row_addr_lo,x      ; VRAM row address = MEMB address - $4000
        sta MEMB_BCB+BCB_ROW_OFS+6
        ora #1                 ; attributes: +1 (row addresses are even)
        sta MEMB_BCB+BCB_ROW_OFS+21+6
        lda row_addr_hi,x
        and #$3F
        sta MEMB_BCB+BCB_ROW_OFS+7
        sta MEMB_BCB+BCB_ROW_OFS+21+7
        memb_off
        blit VRAM_BCB+BCB_ROW_OFS
        rts
 .else
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
 .endif
.endp

 .if 1                          ; 2026-09-23 (vbxe-blitter: a line of one char is a constant fill)
; ----------------------------------------------------------------------------
; vbxe_hline - X copies of char A at the cursor in zp_cur_attr, by blitter
; (AND 0 / XOR: 1 blitter cycle a byte); the cursor moves X cells.
; Only dest, width and the two XOR values go into the BCB template.
; ----------------------------------------------------------------------------
.proc vbxe_hline
        stx ?n
        ldy blit_pending               ; the last line may still read the
        beq ?free                      ; template: wait only in that case
        pha
        jsr blit_idle
        pla
?free   tay                            ; memb_on loads A
        memb_on 0
        sty MEMB_HLINE_BCB+16          ; XOR = char
        lda zp_cur_attr
        sta MEMB_HLINE_BCB+21+16       ; XOR = attribute
        dex
        stx MEMB_HLINE_BCB+12          ; width - 1 (<= 79: high byte stays 0)
        stx MEMB_HLINE_BCB+21+12
        lda zp_scr_ptr                 ; VRAM dest = screen pointer - $4000
        sta MEMB_HLINE_BCB+6
        ora #1                         ; attributes: +1 (cells are even)
        sta MEMB_HLINE_BCB+21+6
        lda zp_scr_ptr+1
        and #$3F
        sta MEMB_HLINE_BCB+7
        sta MEMB_HLINE_BCB+21+7
        memb_off
        lda #<VRAM_HLINE_BCB           ; started, not waited for: callers that
        ldx #>VRAM_HLINE_BCB           ; write over these cells call blit_sync
        jsr blit_go
        lda ?n                         ; ptr += 2n, col += n
        asl                            ; n <= 80: C = 0
        adc zp_scr_ptr
        sta zp_scr_ptr
        bcc ?nc
        inc zp_scr_ptr+1
?nc     lda zp_cursor_col
        clc
        adc ?n
        sta zp_cursor_col
        rts
?n      dta 0
.endp
 .endif

; ----------------------------------------------------------------------------
; Original helpers, used only by .else (original) code paths: set this to 1
; together with such a path (mouse cursor, status_msg / set-attribute).
; ----------------------------------------------------------------------------
 .if 0
.proc vbxe_setattr
        sta zp_cur_attr
        rts
.endp
render_set_attr = vbxe_setattr

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
 .endif

; ----------------------------------------------------------------------------
; vbxe_cell_get - Read one text cell in one MEMAC B session
; MUST be below $4000! Called by code above $4000 (mouse module).
; Input: zp_tmp_ptr = row address (MEMAC B window), Y = col*2
; Output: A = char, X = attr
; ----------------------------------------------------------------------------
.proc vbxe_cell_get
        memb_on 0              ; (keeps Y)
        iny
        lda (zp_tmp_ptr),y     ; attr
        tax
        dey
        lda (zp_tmp_ptr),y     ; char
        pha
        memb_off
        pla
        rts
.endp

; ----------------------------------------------------------------------------
; vbxe_cell_put - Write one text cell (A = char, X = attr) in one session
; Input: zp_tmp_ptr = row address (MEMAC B window), Y = col*2
; ----------------------------------------------------------------------------
.proc vbxe_cell_put
        pha
        memb_on 0              ; (keeps Y)
        pla
        sta (zp_tmp_ptr),y
        iny
        txa
        sta (zp_tmp_ptr),y
        memb_off
        rts
.endp

; ----------------------------------------------------------------------------
; status_msg_sub - Show message on status bar (subroutine for status_msg macro)
; Input: Y=color, A=msg_lo, X=msg_hi
; ----------------------------------------------------------------------------
 .if 1                          ; 2026-09-23 (one status bar for everything: an inverse bar in the
                                ; message's colour, drawn by the blitter; keys right-aligned)
; ----------------------------------------------------------------------------
; status_msg_sub - THE status bar. Every status line goes through here.
; Row STATUS_ROW becomes an inverse bar in colour Y; message A/X is
; "left text [, 1, keys], 0" -- the keys are shown right-aligned. The
; cursor stays after the left text: sb_text / sb_char / sb_num append
; to it in the bar's colour.
; ----------------------------------------------------------------------------
.proc status_msg_sub
        sta ?f+1
        sta ?m+1
        stx ?f+2
        stx ?m+2
        sty sb_attr
        sty zp_cur_attr
        lda #STATUS_ROW
        ldx #0
        jsr vbxe_setpos
        lda #$A0               ; inverse space: the bar (blitter fill)
        ldx #SCR_COLS
        jsr vbxe_hline
        ldy #0                 ; find the end of the left text
?f      lda $FFFF,y
        cmp #2                 ; 0 = no keys, 1 = keys follow
        bcc ?sep
        iny
        bne ?f                 ; always (< 80)
?sep    sty ?n                 ; fire early, wait late: the text goes over
        tax                    ; the bar's cells (blit_sync uses Y)
        jsr blit_sync
        txa
        ldy ?n
        lsr                    ; A = 1: C = 1
        bcc ?left
        ldx #0                 ; keys -> print_buf, inverted
?rl     iny
?m      lda $FFFF,y
        beq ?rd
        ora #$80
        sta print_buf,x
        inx
        bne ?rl                ; always (< 80)
?rd     stx ?n
        lda #SCR_COLS-1        ; right-aligned, one bar cell before the edge;
        sbc ?n                 ; C = 1: lsr of A = 1 above, nothing since changed it
        tax
        lda #STATUS_ROW
        jsr vbxe_setpos
        ldx ?n
        jsr sb_emit
?left   lda #STATUS_ROW
        ldx #0
        jsr vbxe_setpos
        lda ?f+1
        ldx ?f+2
        jmp sb_text            ; the left text (sb_text stops at 0 or 1)
?n      dta 0
.endp

; sb_text - Append string A/X (ends at 0 or 1) to the status bar: one
; inverting copy straight into print_buf, then vbxe_emit
.proc sb_text
        sta ?s+1
        stx ?s+2
        ldx #0
?s      lda $FFFF,x
        cmp #2                 ; 0 or 1 ends it
        bcc ?e
        ora #$80
        sta print_buf,x
        inx
        bne ?s                 ; always (< 80)
?e      txa
        bne sb_emit            ; X = count >= 1
        rts
.endp

; sb_emit - print_buf[0..X-1] (X >= 1) at the cursor in the bar's colour
.proc sb_emit
        lda sb_attr
        sta zp_cur_attr
        memb_on 0
        jsr vbxe_emit
        memb_off
        lda #ATTR_NORMAL
        sta zp_cur_attr
        rts
.endp

; sb_char - Append char A to the status bar (X preserved)
.proc sb_char
        ora #$80
        ldy sb_attr
        sty zp_cur_attr
        jsr vbxe_putchar       ; keeps X
        lda #ATTR_NORMAL
        sta zp_cur_attr
        rts
.endp

; sb_num - Append A (0-255) in decimal, no leading zeros
.proc sb_num
        ldx #'0'-1             ; X = digit char
        cmp #100
        bcc ?tens
?h      inx
        sbc #100
        bcs ?h
        adc #100               ; C = 0: undo the last subtraction
        jsr ?digit
        ldx #'0'-1
        sec
        bcs ?t                 ; always: with hundreds, tens always print
?tens   cmp #10
        bcc ?one
?t      inx
        sbc #10
        bcs ?t
        adc #10                ; C = 0
        jsr ?digit
?one    ora #'0'
        jmp sb_char
?digit  pha                    ; print X, keep A
        txa
        jsr sb_char
        pla
        rts
.endp

sb_attr dta 0
 .else
.proc status_msg_sub
 .if 1                          ; 2026-09-23 (6502-idioms: attribute stored directly, jsr/rts -> jmp)
        sta sm_msg
        stx sm_msg+1
        sty zp_cur_attr
        tya
        tax
        lda #STATUS_ROW
        jsr vbxe_fill_row
        lda #STATUS_ROW
        ldx #0
        jsr vbxe_setpos
        lda sm_msg
        ldx sm_msg+1
        jsr vbxe_print
        lda #ATTR_NORMAL
        sta zp_cur_attr
        rts
sm_msg   dta a(0)
 .else
        sta sm_msg
        stx sm_msg+1
        sty sm_color
        lda #STATUS_ROW
        ldx sm_color
        jsr vbxe_fill_row
        lda #STATUS_ROW
        ldx #0
        jsr vbxe_setpos
        lda sm_color
        jsr vbxe_setattr
        lda sm_msg
        ldx sm_msg+1
        jsr vbxe_print
        lda #ATTR_NORMAL
        jmp vbxe_setattr
sm_color dta b(0)
sm_msg   dta a(0)
 .endif
.endp
 .endif

; ----------------------------------------------------------------------------
; wait_frames_sub - Wait X frames (subroutine for wait_frames macro)
; Input: X = number of frames to wait. Returns Z = 1 (X = 0): callers may
; follow `wait_frames` with a beq instead of a jmp.
; ----------------------------------------------------------------------------
.proc wait_frames_sub
?wfdly  lda RTCLOK+2
?wfdw   cmp RTCLOK+2
        beq ?wfdw
        dex
        bne ?wfdly
        rts
.endp

; ----------------------------------------------------------------------------
; tab_find_next - Find next link on screen after current cursor position
; Scans VRAM attrs for any link attr ($20-$5F) different from current link.
; Wraps around to top once if no link found below current position.
; MUST be below $4000 (uses MEMAC B directly)
; Input: zp_tab_link = current link ($FF = none), zp_mouse_x/y = position
; Output: C=0 found (zp_mouse_x/y set), C=1 no link found
; ----------------------------------------------------------------------------
        page_fit tab_find_next.scan_row-tab_find_next, tab_find_next.scan_end-tab_find_next.scan_row
.proc tab_find_next
 .if 1                          ; 2026-09-23 (6502-idioms: skip attr as an SMC operand, known C,
                                ; bne ?found instead of beq/jmp; 6502-cycles-layout: page_fit + ert keep
                                ; the scan loops in one page)
        ; Attr to skip (the current link's continuation); $FF matches none
        lda zp_tab_link
        cmp #$FF
        beq ?no_cur
        adc #ATTR_LINK_BASE    ; C = 0: A < $FF
?no_cur sta ?skip+1

        memb_on 0

        ; Start position: top-left if no selection, else next col
        ldx #CONTENT_TOP
        ldy #1                 ; first attr byte
        lda zp_tab_link
        cmp #$FF
        beq ?set_wrap          ; A = $FF: "not wrapped yet" = any non-zero
        ldx zp_mouse_y
        lda zp_mouse_x
        asl                    ; col <= 79: C = 0
        adc #3                 ; next column's attr offset
        tay
        cpy #SCR_STRIDE
        bcc ?set_wrap
        ldy #1                 ; wrap to next row
        inx
        cpx #CONTENT_BOT+1
        bcc ?set_wrap
        ldx #CONTENT_TOP       ; wrap to top
?set_wrap
        lda #1
        sta ?did_wrap          ; 1 = may still wrap once

scan_row
?scan_row
        lda row_addr_lo,x
        sta zp_scr_ptr
        lda row_addr_hi,x
        sta zp_scr_ptr+1

scan_col
?col    lda (zp_scr_ptr),y
        cmp #ATTR_LINK_BASE
        bcc ?next
        cmp #ATTR_LINK_BASE+MAX_LINKS
        bcs ?next
?skip   cmp #$FF               ; skip same link's text (operand patched)
        bne ?found

?next   iny
        iny
        cpy #SCR_STRIDE
        bcc ?col
        ert >?col <> >*         ; hot loop: keep it in one page

        ldy #1
        inx
        cpx #CONTENT_BOT+1
        bcc ?scan_row
scan_end
        ert >?scan_row <> >*    ; the row loop too

        ; Bottom reached -- wrap to top (once only)
        dec ?did_wrap
        bmi ?none
        ldx #CONTENT_TOP
        bpl ?scan_row          ; always

?none   memb_off
        sec
        rts

?found  ; X = row, Y = attr offset; col = (Y-1) / 2
        stx zp_mouse_y
        tya
        lsr                    ; (Y-1)/2 = Y/2 for odd Y
        sta zp_mouse_x
        memb_off
        clc
        rts

?did_wrap  dta 0
 .else
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

scan_row                       ; (label for page_fit)
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
scan_end                       ; (label for page_fit)

        ; Bottom reached - wrap to top (once only)
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
 .endif
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
