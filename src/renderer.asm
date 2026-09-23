; ============================================================================
; Renderer Module - Word-wrap, attributes, link numbering
; ============================================================================

; render_setpos - vbxe_setpos(zp_render_row, zp_render_col) inline: cursor
; and screen pointer set, X = row, A = pointer high byte (as calc_scr_ptr)
render_setpos .macro
        ldx zp_render_row      ; = vbxe_setpos + calc_scr_ptr: X = row,
        stx zp_cursor_row      ; A = pointer high byte as they leave them
        lda zp_render_col
        sta zp_cursor_col
        asl                    ; col <= 79: C = 0
        adc row_addr_lo,x
        sta zp_scr_ptr
        lda row_addr_hi,x
        adc #0
        sta zp_scr_ptr+1
        .endm

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
        sta last_was_sp
        sta title_len
        sta title_buf          ; null-terminate empty title
        sta zp_scroll_pos
        sta zp_scroll_pos+1
        sta page_abort
        sta skip_to_heading

        lda #ATTR_NORMAL
        sta zp_cur_attr
        lda #$FF
        sta pending_link
        sta zp_tab_link
        jmp update_emit_skip   ; skip_to_heading changed above
.endp

; ----------------------------------------------------------------------------
; render_char - Process char for word-wrapped output
; Input: A = character
; last_was_sp is only read while zp_word_len = 0: a non-space char always
; leaves the word non-empty, so it no longer needs clearing here.
; ----------------------------------------------------------------------------
.proc render_char
        ldx in_title
        bne ?title
        cmp #CH_SPACE
        beq render_space
        ldx zp_word_len        ; non-space: add to word buffer
        cpx #WORD_BUF_SZ-1
        bcs ?skip
        sta word_buf,x
        inc zp_word_len
?skip   rts

?title  ldx title_len
        cpx #78
        bcs ?skip
        sta title_buf,x
        inc title_len
        rts
.endp

; ----------------------------------------------------------------------------
; render_space - A space in word-wrapped text: flush the pending word and
; output one space (duplicate spaces collapse). The word and its space go
; out in one vbxe_put_word call.
; ----------------------------------------------------------------------------
.proc render_space
        lda zp_word_len
        bne ?word
        lda last_was_sp        ; no word: a lone space, unless one just went
        bne ?done
        inc last_was_sp        ; 0 -> 1
        lda #CH_SPACE
        jmp render_out_char

?word   clc                    ; does the word fit?
        adc zp_render_col
        cmp #SCR_COLS
        bcc ?fits
        jsr render_do_nl
        jsr render_indent_out
 .if 1                          ; 2026-09-23 (6502-cycles-layout: inline vbxe_setpos + calc_scr_ptr per
                                ; word: no jsr/jmp/rts, no reloads, -21 cycles a word)
?fits   lda skip_hf
        bne ?skip
        render_setpos
 .else
?fits   lda skip_hf
        bne ?skip
        lda zp_render_row
        ldx zp_render_col
        jsr vbxe_setpos
 .endif
        sec                    ; word + trailing space
        jsr vbxe_put_word
        lda zp_render_col      ; col += len + 1
        sec
        adc zp_word_len
        sta zp_render_col
        ldx #0
        stx zp_word_len
        inx
        stx last_was_sp        ; = 1
        cmp #SCR_COLS
        bcc ?done
        jsr render_do_nl       ; the space took the last column
        jmp render_indent_out
?skip   lda #0
        sta zp_word_len
        lda #1
        sta last_was_sp
?done   rts
.endp

; ----------------------------------------------------------------------------
; render_flush_word - Output buffered word with word-wrap
; ----------------------------------------------------------------------------
.proc render_flush_word
        lda zp_word_len
        bne ?go
        rts                    ; no word: done (no page-crossing branch)
?go

        clc                    ; does the word fit?
        adc zp_render_col
        cmp #SCR_COLS
        bcc ?fits
        jsr render_do_nl
        jsr render_indent_out

 .if 1                          ; 2026-09-23 (6502-cycles-layout: vbxe_setpos inline, -21 a word)
?fits   lda skip_hf            ; skip check once for the entire word
        bne ?clr
        render_setpos
 .else
?fits   lda skip_hf            ; skip check once for the entire word
        bne ?clr
        lda zp_render_row
        ldx zp_render_col
        jsr vbxe_setpos
 .endif
        clc                    ; word only, no trailing space
        jsr vbxe_put_word
        lda zp_render_col      ; bulk update render_col
        clc
        adc zp_word_len
        sta zp_render_col

?clr    lda #0
        sta zp_word_len
        sta last_was_sp
        rts
.endp

; ----------------------------------------------------------------------------
; render_out_char - Put char on screen at render position
; Input: A = char
; ----------------------------------------------------------------------------
.proc render_out_char
 .if 1                          ; 2026-09-23 (6502-cycles-layout: vbxe_setpos inline; 6502-idioms:
                                ; the char waits in Y, not on the stack)
        ldx skip_hf
        bne ?skip_ret
        tay
        render_setpos
        tya
        jsr vbxe_putchar
 .else
        ldx skip_hf
        bne ?skip_ret
        pha
        lda zp_render_row
        ldx zp_render_col
        jsr vbxe_setpos
        pla
        jsr vbxe_putchar
 .endif

        inc zp_render_col
        lda zp_render_col
        cmp #SCR_COLS
        bcc ?skip_ret
        jsr render_do_nl
        jmp render_indent_out
?skip_ret
        rts
.endp

; ----------------------------------------------------------------------------
; render_newline
; ----------------------------------------------------------------------------
.proc render_newline
        jsr render_flush_word
        jmp render_do_nl
.endp

; ----------------------------------------------------------------------------
; render_do_nl - Internal: advance to next line
; When content area is full, pause for user input (pagination)
; ----------------------------------------------------------------------------
.proc render_do_nl
        lda skip_hf
        bne ?ok
        sta zp_render_col      ; A = 0
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
        lda #0
        sta zp_link_num        ; reset links for new screen
        lda #$FF
        sta zp_tab_link        ; clear TAB selection on scroll
?ok     rts

?abort  ; User pressed Q - set abort flag; the parser loop ends at once
        ; because the chunk now "ends" at the current byte
        lda #1
        sta page_abort
        dec zp_render_row
        lda chunk_idx
        sta zp_rx_len
        rts
.endp

; ----------------------------------------------------------------------------
; render_page_pause - Show "--More--" prompt, wait for key
; Output: C=0 continue, C=1 abort
; ----------------------------------------------------------------------------
.proc render_page_pause
 .if 1                          ; 2026-09-23 (one status bar for everything)
        status_msg COL_BLUE, m_more
 .else
        status_msg COL_YELLOW, m_more
 .endif
        ; Clear any residual mouse click from previous scroll/rendering
        lda #0
        sta zp_mouse_btn

?wait   ; Non-blocking loop: check keyboard and mouse
        ; Wait one frame (vsync)
        lda RTCLOK+2
?vs     cmp RTCLOK+2
        beq ?vs

        ; Update mouse cursor
        jsr mouse_show_cursor

        ; Check mouse button click
        lda zp_mouse_btn
        jeq ?no_click
        ; Wait for physical button release
?brel   lda STRIG1
        beq ?brel
        ; Clear btn after release
        lda #0
        sta zp_mouse_btn
        ; Check if cursor is on a link
        jsr mouse_check_link
        jcs ?click_ignore      ; not on link — do nothing

        ; Link found — check if it's an image link
        sta rpp_link_num
        jsr calc_link_addr     ; zp_tmp_ptr = link URL
        ldy #0
        lda (zp_tmp_ptr),y
        cmp #'I'
        jne ?normal_click
        iny
        lda (zp_tmp_ptr),y
        cmp #':'
        jne ?normal_click

        ; Image link: fetch image and return to --More--
        jsr mouse_hide_cursor
        ; DON'T call http_save_base here — base_url was set
        ; in http_navigate and must stay intact for subsequent images
        lda rpp_link_num
        jsr calc_link_addr
        ldy #2                 ; skip "I:"
        jsr copy_img_src
        ; Check if download is still active (N1: open)
        lda dl_active
        beq ?img_now
        ; Download active — defer image fetch until after fn_close
        lda #1
        sta img_deferred
 .if 1                          ; 2026-09-23 (one status bar for everything)
        status_msg COL_BLUE, m_img_queued
 .else
        status_msg COL_CYAN, m_img_queued
 .endif
        wait_frames 75         ; ~1.5s
 .if 1                          ; 2026-09-23 (one status bar for everything)
        status_msg COL_BLUE, m_more
 .else
        status_msg COL_YELLOW, m_more
 .endif
        lda #0
        sta zp_mouse_btn
        jmp ?wait

?img_now
        ; Save ALL parser+renderer state before image fetch
        ; (img_fetch_single may clobber ZP vars via status_msg, SIO, etc.)
        lda chunk_idx
        sta rpp_saved_cidx
        lda zp_rx_len
        sta rpp_saved_rxlen
        ldx #14
?sv     lda zp_cur_attr,x      ; save $84-$92 (15 bytes)
        sta rpp_state_buf,x
        dex
        bpl ?sv                ; (rpp_state_buf+0 = zp_cur_attr)
        lda in_quotes
        sta rpp_saved_quotes
        lda is_closing
        sta rpp_saved_closing

        jsr img_fetch_single

        ; Restore parser+renderer state
        ldx #14
?rs     lda rpp_state_buf,x    ; restore $84-$92
        sta zp_cur_attr,x
        dex
        bpl ?rs
        lda rpp_saved_quotes
        sta in_quotes
        lda rpp_saved_closing
        sta is_closing

        ; rx_buffer destroyed by img_fetch — rewind VRAM and re-read chunk
        ; Restore VRAM read pointer to start of current chunk
        lda http_render.pb_rd_save_bank
        sta pb_rd_bank
        lda http_render.pb_rd_save_lo
        sta zp_pb_rd_ptr
        lda http_render.pb_rd_save_hi
        sta zp_pb_rd_ptr+1
        ; Re-read same chunk from VRAM into rx_buffer (the image fetch
        ; used it), put the sentinel back and resume where the parser was
        lda rpp_saved_rxlen
        jsr vbxe_pb_read_chunk
        jsr parse_sentinel
        lda rpp_saved_cidx
        sta chunk_idx
 .if 1                          ; 2026-09-23 (one status bar for everything)
        status_msg COL_BLUE, m_more
 .else
        status_msg COL_YELLOW, m_more
 .endif
        lda rpp_state_buf      ; attribute (status_msg reset it)
        sta zp_cur_attr
        lda #0
        sta zp_mouse_btn
        jmp ?wait

?normal_click
        ; Normal link — store pending and ABORT rendering (C=1)
        lda rpp_link_num
        sta pending_link
        jsr mouse_hide_cursor
        sec
        rts

?click_ignore
        ; Not a link — check if click is on status bar (--More--)
        lda zp_mouse_y
        cmp #STATUS_ROW
        bne ?click_nop         ; click on page content = do nothing
        ; Click on --More-- bar = advance page
        jsr mouse_hide_cursor
        jmp ?advance
?click_nop
        jmp ?wait

?no_click
        ; Check keyboard (non-blocking via CH)
        lda CH
        cmp #KEY_NONE
        jeq ?wait              ; no input, loop
        ; Key available — kbd_get returns immediately via CIO
        jsr kbd_get
        cmp #CH_SPACE
        beq ?key_next
        cmp #ATASCII_TAB
        beq ?key_tab
        cmp #ATASCII_RET
        beq ?key_return
        cmp #'h'
        beq ?key_heading
        cmp #'H'
        beq ?key_heading
        cmp #'q'
        beq ?key_quit
        cmp #'Q'
        beq ?key_quit
        cmp #$06                ; Ctrl+F
        beq ?key_find
        cmp #'f'
        beq ?key_find
        cmp #'F'
        jne ?wait

?key_find
        jsr find_start
        jmp ?wait

?key_tab
        jsr tab_next_link
        jmp ?wait

?key_return
        lda zp_tab_link
        cmp #$FF
        beq ?key_next          ; no TAB selection → advance page
        sta pending_link
        jsr mouse_hide_cursor
        sec
        rts

?key_next
        ; Keyboard: hide cursor first, then advance
        jsr mouse_hide_cursor

?advance
        ; Restore status bar to loading
        status_msg COL_YELLOW, m_loading
        clc
        rts

?key_heading
        ; Skip to next heading - set flag, advance without pause
        jsr mouse_hide_cursor
        lda #1
        sta skip_to_heading
        jsr update_emit_skip
        status_msg COL_YELLOW, m_skipping
        jmp ?advance

?key_quit
        jsr mouse_hide_cursor
        lda #$FF               ; $FF = no pending link
        sta pending_link
        sec
        rts

 .if 1                          ; 2026-09-23 (one status bar for everything)
m_more    dta c' More below',1,c'Space  Next page   H  Jump to content   Q  Quit',0
m_img_queued dta c' Image queued: it opens after the download',0
m_skipping dta c' Jumping to the content (next heading)...',0
m_loading dta c' Loading...',0
 .else
m_more    dta c' -- Next page: Spc  Skip: H  Quit: Q --',0
m_img_queued dta c' IMG queued after download',0
m_skipping dta c' Skipping to heading...',0
m_loading dta c' Loading...',0
 .endif
; --- Parser state save area for img_fetch during --More-- ---
; img_fetch_single clobbers ZP, rx_buffer, and status_msg overwrites attr.
; After image view, VRAM is rewound and chunk re-read, parser resumes exactly.
rpp_link_num    dta 0              ; link number of clicked IMG link
rpp_saved_cidx  dta 0              ; saved chunk_idx (parser position in rx_buffer)
rpp_saved_rxlen dta 0              ; saved zp_rx_len (chunk size for re-read)
rpp_saved_quotes dta 0             ; saved in_quotes (parser mid-attribute state)
rpp_saved_closing dta 0            ; saved is_closing (parser mid-tag state)
rpp_state_buf   .ds 15             ; bulk save: ZP $84-$92 (cur_attr..entity_idx)
.endp

; ----------------------------------------------------------------------------
; render_indent_out - Output indentation spaces
; ----------------------------------------------------------------------------
.proc render_indent_out
        ldx zp_indent
        beq ?done
        lda zp_render_row
        ldx zp_render_col
        jsr vbxe_setpos
        lda #CH_SPACE
        ldx zp_indent
        jsr vbxe_fill_char     ; batch MEMAC (routine below $4000)
        lda zp_render_col
        clc
        adc zp_indent
        sta zp_render_col
?done   rts
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
        jmp render_out_char
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
        jmp render_out_char

?num    inc zp_list_item
        lda zp_list_item
        jsr render_number
        lda #'.'
        jsr render_out_char
        lda #CH_SPACE
        jmp render_out_char
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
        lda zp_render_row
        ldx zp_render_col
        jsr vbxe_setpos
        lda #'-'
        ldx #SCR_COLS-1
        jsr vbxe_fill_char     ; batch MEMAC (routine below $4000)
        lda #SCR_COLS-1
        sta zp_render_col
        ; Last dash via render_out_char (triggers wrap + pagination)
        lda #'-'
        jsr render_out_char
        lda #ATTR_NORMAL
        sta zp_cur_attr
        rts
.endp

; render_tbl_line = render_hr_line (identical code)
render_tbl_line = render_hr_line

; --- Renderer state ---
title_len   dta 0              ; chars collected in title_buf so far
page_abort  dta 0              ; 1 = user pressed Q, stop rendering
pending_link dta $FF           ; $FF = none, 0-63 = link number to follow after render
skip_to_heading dta 0          ; 1 = H key pressed, suppress output until next <hN>

; word_buf moved to data.asm: it must live above $7FFF so vbxe_put_word
; (below $4000) can read it while the MEMAC B window is enabled
WORD_BUF_SZ = 80
title_buf   .ds 80
