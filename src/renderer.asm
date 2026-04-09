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

?fits   ; Skip check once for entire word
        lda skip_to_heading
        ora skip_to_frag
        bne ?clr
        ; Position VBXE cursor once (putchar auto-advances)
        lda zp_render_row
        ldx zp_render_col
        jsr vbxe_setpos
        ; Output chars — putchar preserves X (word fits, no wrap)
        ldx #0
?lp     cpx zp_word_len
        beq ?upd
        lda word_buf,x
        jsr vbxe_putchar
        inx
        bne ?lp
?upd    ; Bulk update render_col
        lda zp_render_col
        clc
        adc zp_word_len
        sta zp_render_col

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
        ldx skip_to_heading
        bne ?skip_ret
        ldx skip_to_frag
        bne ?skip_ret
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
?ok
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
        lda skip_to_heading
        bne ?ok_ret
        lda skip_to_frag
        bne ?ok_ret
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
        lda #0
        sta zp_link_num        ; reset links for new screen
        lda #$FF
        sta zp_tab_link        ; clear TAB selection on scroll
?ok
?ok_ret rts

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
        bne ?has_click
        jmp ?no_click
?has_click
        ; Wait for physical button release
?brel   lda STRIG1
        beq ?brel
        ; Clear btn after release
        lda #0
        sta zp_mouse_btn
        ; Check if cursor is on a link
        jsr mouse_check_link
        bcc ?is_link
        jmp ?click_ignore      ; not on link — do nothing
?is_link

        ; Link found — check if it's an image link
        sta rpp_link_num
        jsr calc_link_addr     ; zp_tmp_ptr = link URL
        ldy #0
        lda (zp_tmp_ptr),y
        cmp #'I'
        beq ?chk_colon
        jmp ?normal_click
?chk_colon
        iny
        lda (zp_tmp_ptr),y
        cmp #':'
        beq ?is_img
        jmp ?normal_click
?is_img

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
        status_msg COL_CYAN, m_img_queued
        wait_frames 75         ; ~1.5s
        status_msg COL_YELLOW, m_more
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
        ldx #0
?sv     lda zp_cur_attr,x      ; save $84-$92 (15 bytes)
        sta rpp_state_buf,x
        inx
        cpx #15
        bne ?sv
        lda zp_cur_attr
        sta rpp_saved_attr
        lda in_quotes
        sta rpp_saved_quotes
        lda is_closing
        sta rpp_saved_closing

        jsr img_fetch_single

        ; Restore parser+renderer state
        ldx #0
?rs     lda rpp_state_buf,x    ; restore $84-$92
        sta zp_cur_attr,x
        inx
        cpx #15
        bne ?rs
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
        ; Re-read same chunk from VRAM into rx_buffer
        lda rpp_saved_rxlen
        jsr vbxe_pb_read_chunk
        ; Restore chunk position — parser continues exactly where it left off
        lda rpp_saved_cidx
        sta chunk_idx
        ; Restore attr (status_msg clobbered it)
        lda rpp_saved_attr
        sta zp_cur_attr
        ; zp_rx_len restored by pb_read_chunk
        ; Return to --More-- loop — page render continues from VRAM
        status_msg COL_YELLOW, m_more
        ; Re-restore attr after status_msg clobbered it again
        lda rpp_saved_attr
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
        bne ?has_key
        jmp ?wait              ; no input, loop
?has_key
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
        status_msg COL_YELLOW, m_skipping
        jmp ?advance

?key_quit
        jsr mouse_hide_cursor
        lda #$FF               ; $FF = no pending link
        sta pending_link
        sec
        rts

m_more    dta c' -- Next page: Spc  Skip: H  Quit: Q --',0
m_img_queued dta c' IMG queued after download',0
m_skipping dta c' Skipping to heading...',0
m_loading dta c' Loading...',0
; --- Parser state save area for img_fetch during --More-- ---
; img_fetch_single clobbers ZP, rx_buffer, and status_msg overwrites attr.
; After image view, VRAM is rewound and chunk re-read, parser resumes exactly.
rpp_link_num    dta 0              ; link number of clicked IMG link
rpp_saved_cidx  dta 0              ; saved chunk_idx (parser position in rx_buffer)
rpp_saved_rxlen dta 0              ; saved zp_rx_len (chunk size for re-read)
rpp_saved_attr  dta 0              ; saved zp_cur_attr (status_msg clobbers it)
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

; render_set_attr = vbxe_setattr (identical: sta zp_cur_attr / rts)
render_set_attr = vbxe_setattr

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
last_was_sp dta 0              ; suppress duplicate spaces in word wrap
title_len   dta 0              ; chars collected in title_buf so far
page_abort  dta 0              ; 1 = user pressed Q, stop rendering
pending_link dta $FF           ; $FF = none, 0-63 = link number to follow after render
skip_to_heading dta 0          ; 1 = H key pressed, suppress output until next <hN>

WORD_BUF_SZ = 80
word_buf    .ds WORD_BUF_SZ
title_buf   .ds 80
