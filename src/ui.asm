; ============================================================================
; UI Module - URL bar, status bar, navigation
; ============================================================================

; ----------------------------------------------------------------------------
; ui_init - Initialize UI layout
; ----------------------------------------------------------------------------
.proc ui_init
        ; Restore normal 30-row text XDL (title screen uses GMON gradient XDL)
        jsr vbxe_restore_xdl
        jsr vbxe_cls

        ; URL bar (row 0, green)
        lda #URL_ROW
        ldx #COL_GREEN
        jsr vbxe_fill_row
        lda #URL_ROW
        ldx #0
        jsr vbxe_setpos
        lda #COL_GREEN
        sta zp_cur_attr
        lda #<m_urlp
        ldx #>m_urlp
        jsr vbxe_print

        lda #ATTR_NORMAL
        sta zp_cur_attr
        rts

m_urlp  dta c'URL: ',0
.endp

; ----------------------------------------------------------------------------
; ui_main_loop - Main keyboard event loop
; ----------------------------------------------------------------------------
.proc ui_main_loop
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
        ; Wait for physical button release (STRIG1: 0=pressed, 1=released)
?brel   lda STRIG1
        beq ?brel
        ; Check if cursor is on a link (uses mouse_saved_attr, no hide needed)
        jsr mouse_check_link
        bcs ?no_click
        ; A = link number — follow it
        sta zp_cur_link
        lda #KEY_NONE
        sta CH
        jsr mouse_hide_cursor
        jsr ui_follow_link
        jsr ?chk_pending
        jmp ?loop

?no_click
        ; Check keyboard (non-blocking via CH)
        lda CH
        cmp #KEY_NONE
        beq ?loop              ; no key, loop

        ; Key available — kbd_get returns immediately
        jsr kbd_get

        cmp #ATASCII_TAB
        beq ?tab
        cmp #ATASCII_RET
        beq ?ret_key
        cmp #$02                ; Ctrl+B = bookmarks window
        jeq ?bkmark
        cmp #$06                ; Ctrl+F = find in page
        jeq ?find
        ora #$20                ; letters: case-fold once ('Q' -> 'q')
        cmp #'q'
        beq ?quit
        cmp #'u'
        jeq ?url
        cmp #'b'
        jeq ?back
        cmp #'p'
        jeq ?proxy
        cmp #'f'                ; 'f' alt for find
        jeq ?find
        cmp #'i'                ; I = info / help screen
        jeq ?info
        jmp ?loop

?tab    jsr tab_next_link
        jmp ?loop

?ret_key
        lda zp_tab_link
        cmp #$FF
        jeq ?loop              ; no TAB selection
        sta zp_cur_link
        lda #KEY_NONE
        sta CH
        jsr mouse_hide_cursor
        jsr ui_follow_link
        jsr ?chk_pending
        jmp ?loop

        ; Q = return to welcome screen
?quit   jsr mouse_hide_cursor
        jsr fn_close
        lda img_active
        beq ?qi1
        jsr vbxe_img_hide
?qi1    jsr html_reset
        jsr render_reset
        jsr show_welcome
        jmp ?redraw

?url    jsr mouse_hide_cursor
        jsr ui_init
        jsr ui_url_input
        bcs ?url_done
        jsr history_push
        jsr http_navigate
        jsr ?chk_pending
?url_done
        jmp ?redraw

?back   jsr mouse_hide_cursor
        jsr ui_init
        jsr history_pop
        bcs ?redraw
        jsr http_navigate
        jsr ?chk_pending
?redraw lda #$FF               ; screen redrawn: the cursor has no saved cell
        sta zp_mouse_prev_x
        jmp ?loop

?proxy  ; Toggle proxy mode and refresh welcome screen
 .if 1                          ; 2026-09-23 (settings saved on disk)
        lda use_proxy
        eor #1
        sta use_proxy
        jsr set_save           ; D1: sector 715
        jsr show_welcome
 .else
        lda use_proxy
        eor #1
        sta use_proxy
        jsr show_welcome
 .endif
        jmp ?loop

?bkmark jsr bk_screen
        jmp ?loop

?info   jsr show_info
        jsr show_welcome        ; restore welcome screen after info closes
        jmp ?loop

?find   jsr find_start
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
        jmp ?chk_pending       ; follow a chain of pending links (tail call)
?no_pend rts
.endp

; ----------------------------------------------------------------------------
; ui_url_input - Prompt for URL
; Output: url_buffer set, C=0 ok, C=1 cancelled
; ----------------------------------------------------------------------------
.proc ui_url_input
 .if 1                          ; 2026-09-23 (one status bar for everything)
        status_msg COL_BLUE, m_urlhint
 .else
        ; Clear status bar during URL input (keys don't apply here)
        lda #STATUS_ROW
        ldx #COL_BLACK
        jsr vbxe_fill_row
 .endif

        lda #URL_ROW
        ldx #COL_GREEN
        jsr vbxe_fill_row

        lda #URL_ROW
        ldx #0
        jsr vbxe_setpos
        lda #COL_GREEN
        sta zp_cur_attr

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

        ; Lowercase entire URL (Atari keyboard is uppercase)
        ldy #0
?low    lda url_buffer,y
        beq ?lowd
 .if 1                          ; 2026-09-23 (6502-idioms: to lower: the common lowercase byte (> 'Z') leaves on the
                                ; first compare, 5 cycles instead of 9; same result for every byte)
        cmp #'Z'+1
        bcs ?lon
        cmp #'A'
        bcc ?lon
        ora #$20
 .else
        cmp #'A'
        bcc ?lon
        cmp #'Z'+1
        bcs ?lon
        ora #$20
 .endif
        sta url_buffer,y
?lon    iny
        bne ?low
?lowd
        ; Check if input is a URL (has '.') or search query (no '.')
        ldy #0
?chkdot lda url_buffer,y
        beq ?nosrch            ; end of string, no dot = search
        cmp #'.'
        beq ?isurl             ; has dot = URL
        iny
        bne ?chkdot
?nosrch ; No dot found - treat as search query
        jsr url_build_search
?isurl
        jsr ui_show_url
        clc
        rts

?cancel jsr ui_show_url
        sec
        rts

m_go    dta c'Go to: ',0
 .if 1                          ; 2026-09-23 (one status bar for everything)
m_urlhint dta c' Type a URL, or words to search the web',1,c'Return  Go   Esc  Cancel',0
 .endif
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
        jsr copy_img_src
        jsr img_fetch_single
        jmp ui_status_end      ; restore "-- End --" bar after image view

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

        jsr http_resolve_url   ; resolve relative URLs from links
        jsr history_push
        jmp http_navigate

?bad    lda #<m_badlnk
        ldx #>m_badlnk
        jmp ui_show_error

 .if 1                          ; 2026-09-23 (one status bar for everything)
m_badlnk dta c' Invalid link number',1,c'any key',0
 .else
m_badlnk dta c'Invalid link number',0
 .endif
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
        sta zp_cur_attr
        lda #<ui_init.m_urlp
        ldx #>ui_init.m_urlp
        jsr vbxe_print
        ; Check if URL starts with proxy prefix — if so, skip it
        ; proxy_prefix = "N:https://turiecfoto.sk/cactus/proxy.php?url=" (45 chars)
        ldy #0
?chk    lda proxy_prefix,y
        beq ?show_bare         ; end of prefix = full match, skip it
        cmp url_buffer,y
        bne ?show_full         ; mismatch = not proxied, show full URL
        iny
        bne ?chk
?show_full
        ; Search URL? Show "Search: query" instead. The host part is checked
        ; bare (typed before the prefix is added) and after "N:https://"
        ldy #0
?chks   lda search_host,y
        beq ?show_search           ; full match = search URL
        cmp url_buffer,y
        bne ?chks2
        iny
        bne ?chks
?chks2  ldy #0
?chks3  lda search_host,y
        beq ?show_search10
        cmp url_buffer+SEARCH_SCHEME,y
        bne ?not_search
        iny
        bne ?chks3
?show_search10
        tya
        adc #SEARCH_SCHEME-1       ; C = 1 (cmp equal): skip "N:https://" too
        tay
?show_search
        ; Y = length of search prefix
?do_search
        ; Print "Search: " then query (decode + back from url_buffer+Y)
        ; Save Y before vbxe_print (it clobbers Y)
 .if 1                          ; 2026-09-23 (6502-loops-tables-smc: index counting up to zero,
                                ; the patched operand carries the -(256-68) bias)
        tya                        ; query source = url_buffer + Y + 68 - 256 (SMC)
        clc
        adc #<(url_buffer+68-256)
        sta ?sq+1
        lda #>(url_buffer+68-256)
        adc #0
        sta ?sq+2
        lda #<m_search
        ldx #>m_search
        jsr vbxe_print
        ; Print query from url_buffer+Y, converting '+' back to spaces
        ldx #256-68                ; max display width 68
?sq     lda $FFFF,x                ; (patched: query start - 188)
        beq ?sqd
        cmp #'+'
        bne ?sqn
        lda #' '
?sqn    jsr vbxe_putchar           ; preserves X
        inx
        bne ?sq
?sqd    rts
 .else
        tya                        ; query source = url_buffer + Y (SMC)
        clc
        adc #<url_buffer
        sta ?sq+1
        lda #>url_buffer
        adc #0
        sta ?sq+2
        lda #<m_search
        ldx #>m_search
        jsr vbxe_print
        ; Print query from url_buffer+Y, converting '+' back to spaces
        ldx #0
?sq     lda $FFFF,x                ; (patched: query start)
        beq ?sqd
        cmp #'+'
        bne ?sqn
        lda #' '
?sqn    jsr vbxe_putchar           ; preserves X
        inx
        cpx #68                    ; max display width
        bne ?sq
?sqd    rts
 .endif

?not_search
        ; Skip "N:" prefix if present
        lda url_buffer
        cmp #'N'
        bne ?ns_full
        lda url_buffer+1
        cmp #':'
        bne ?ns_full
        lda #<(url_buffer+2)
        ldx #>(url_buffer+2)
        jmp vbxe_print
?ns_full
        lda #<url_buffer
        ldx #>url_buffer
        jmp vbxe_print
?show_bare
        ; Y = length of proxy prefix, print from url_buffer+Y
        ldx #>url_buffer
        tya
        clc
        adc #<url_buffer
        bcc ?sb
        inx
?sb     jmp vbxe_print

m_search dta c'Search: ',0
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
        sta zp_cur_attr
        lda #<title_buf
        ldx #>title_buf
        jsr vbxe_print
        lda #ATTR_NORMAL
        sta zp_cur_attr
        rts
.endp

; ----------------------------------------------------------------------------
; ui_show_error - Display error on status bar (A=lo, X=hi of msg)
; Waits for keypress, then restores status bar
; ----------------------------------------------------------------------------
.proc ui_show_error
 .if 1                          ; 2026-09-23 (one status bar for everything)
        ldy #COL_RED           ; red bar, message A/X ("..., 1, any key")
        jsr status_msg_sub
 .else
        sta ?msg
        stx ?msg+1

        lda #STATUS_ROW
        ldx #COL_RED
        jsr vbxe_fill_row
        lda #STATUS_ROW
        ldx #0
        jsr vbxe_setpos
        lda #ATTR_ERROR
        sta zp_cur_attr

        lda #<m_err
        ldx #>m_err
        jsr vbxe_print

        lda ?msg
        ldx ?msg+1
        jsr vbxe_print
        lda #ATTR_NORMAL
        sta zp_cur_attr
 .endif

        jsr kbd_get

        ; Clear status bar after error dismiss
        lda #STATUS_ROW
        ldx #COL_BLACK
        jmp vbxe_fill_row

m_err   dta c'ERROR: ',0
?msg    dta a(0)
.endp

; ----------------------------------------------------------------------------
; ui_status_loading
; ----------------------------------------------------------------------------
.proc ui_status_loading
        lda #$FF
        sta ui_status_progress.prog_last_kb
 .if 1                          ; 2026-09-23 (one status bar for everything)
        ldy #COL_YELLOW
        lda #<m_load
        ldx #>m_load
        jmp status_msg_sub
m_load  dta c' Loading...',1,c'Key  Stop',0
 .else
        ldy #COL_YELLOW
        lda #<m_load
        ldx #>m_load
        jmp status_msg_sub
m_load  dta c' Loading...',0
 .endif
.endp

; ----------------------------------------------------------------------------
; ui_status_progress - Show "Loading... NNkB" on status bar
; Input: http_bytes_lo/hi = total bytes downloaded (16-bit)
; ----------------------------------------------------------------------------
.proc ui_status_progress
        ; Convert bytes to KB (divide by 256 = just use high byte)
        ; Show update only when KB value changes (avoid flicker)
 .if 1                          ; 2026-09-23 (fix: real kB from the 24-bit pb_total)
        lda pb_total+1         ; kB = pb_total >> 10 (24-bit, <= 448):
        sta ?kl                ; the old high byte of http_bytes counted
        lda pb_total+2         ; 256-byte blocks and wrapped at 64 KB
        lsr
        ror ?kl
        lsr
        ror ?kl
        sta ?kh
        lda ?kl
        cmp prog_last_kb
        beq ?skip              ; same kB as last time, skip update
        sta prog_last_kb

 .if 1                          ; 2026-09-23 (one status bar for everything)
        lda #STATUS_ROW        ; the bar from ui_status_loading stays:
        ldx #PROG_COL          ; only the number is written (kB only grow)
        jsr vbxe_setpos
        jsr ?p16
 .else
        status_msg COL_YELLOW, m_prog

        lda #COL_YELLOW
        sta zp_cur_attr
        jsr ?p16
 .endif
 .else
        lda http_bytes_hi
        cmp prog_last_kb
        beq ?skip              ; same KB as last time, skip update
        sta prog_last_kb

        status_msg COL_YELLOW, m_prog

        ; Print KB number (0-255) — attr still yellow from fill_row
        lda #COL_YELLOW
        sta zp_cur_attr
        lda prog_last_kb
        jsr ?print_num
 .endif

 .if 1                          ; 2026-09-23 (one status bar for everything)
        lda #<m_kb
        ldx #>m_kb
        jsr sb_text
?skip   rts
 .else
        lda #<m_kb
        ldx #>m_kb
        jsr vbxe_print

        lda #ATTR_NORMAL
        sta zp_cur_attr
?skip   rts
 .endif

 .if 1                          ; 2026-09-23 (fix: 16-bit kB, ends in ?tens / ?t_lp like ?print_num)
?p16    ldx #'0'-1             ; hundreds digit of the 16-bit kB
?h16    inx
        lda ?kl
        sec
        sbc #100
        sta ?kl
        lda ?kh
        sbc #0
        sta ?kh
        bcs ?h16
        lda ?kl
        adc #100               ; C = 0: undo the last subtraction, A < 100
 .if 1                          ; 2026-09-23 (one status bar for everything)
        cpx #'0'
        beq ?no_h
        pha                    ; hundreds digit, then both lower digits
        txa
        jsr sb_char
        pla
        ldx #'0'-1
        sec
?t16    inx
        sbc #10
        bcs ?t16
        adc #10                ; C = 0
        pha
        txa
        jsr sb_char
        pla
        ora #'0'
        jmp sb_char
?no_h   jmp sb_num             ; < 100
 .else
        cpx #'0'
        beq ?no_h
        jsr ?digit             ; print X, keep A
        ldx #'0'-1
        sec
        bcs ?t_lp              ; always: with hundreds, tens always print
?no_h   ldx #'0'-1
        jmp ?tens
 .endif
 .endif
        ; Print 8-bit number in A as decimal (no leading zeros)
?print_num
        ldx #'0'-1             ; X = digit char (vbxe_putchar keeps X)
        cmp #100
        bcc ?tens
?h_lp   inx                    ; hundreds
        sbc #100
        bcs ?h_lp
        adc #100               ; C = 0: undo the last subtraction
        jsr ?digit
        ldx #'0'-1
        sec
        bcs ?t_lp              ; always: with hundreds, tens always print
?tens   cmp #10
        bcc ?one
?t_lp   inx
        sbc #10
        bcs ?t_lp
        adc #10
        jsr ?digit
?one    ora #'0'
        jmp vbxe_putchar
?digit  sta ?rest              ; print X, keep A
        txa
        jsr vbxe_putchar
        lda ?rest
        rts
?rest   dta 0

 .if 1                          ; 2026-09-23 (one status bar for everything)
m_prog  dta c' Loading... ',1,c'Key  Stop',0
m_kb    dta c' kB',0
PROG_COL = 12                  ; after " Loading... " (m_load + space)
 .else
m_prog  dta c' Loading... ',0
m_kb    dta c'kB',0
 .endif
prog_last_kb dta b($FF)
 .if 1
?kl     dta 0
?kh     dta 0
 .endif
.endp

; ----------------------------------------------------------------------------
; ui_status_done - Restore status bar after loading
; ----------------------------------------------------------------------------
.proc ui_status_done
        ; Clear status bar
        lda #STATUS_ROW
        ldx #COL_BLACK
        jsr vbxe_fill_row
        lda title_len
        jne ui_show_title
        rts
.endp

; ----------------------------------------------------------------------------
; ui_status_end - Show end-of-page indicator on status bar
; ----------------------------------------------------------------------------
.proc ui_status_end
 .if 1                          ; 2026-09-23 (one status bar for everything)
        status_msg COL_BLUE, m_end
 .else
        status_msg COL_YELLOW, m_end
 .endif
        lda title_len
        jne ui_show_title
        rts

 .if 1                          ; 2026-09-23 (one status bar for everything)
m_end   dta c' End of page',1,c'U  URL   B  Back   Q  Quit',0
 .else
m_end   dta c' -- End -- Q:Quit U:URL B:Back',0
 .endif
.endp

; ----------------------------------------------------------------------------
; ui_status_error
; ----------------------------------------------------------------------------
.proc ui_status_error
 .if 1                          ; 2026-09-23 (one status bar for everything)
        ldy #COL_RED
        lda #<m_stop
        ldx #>m_stop
        jmp status_msg_sub
m_stop  dta c' Stopped',0
.endp
 .else
        lda #STATUS_ROW
        ldx #COL_RED
        jmp vbxe_fill_row
.endp
 .endif

; ----------------------------------------------------------------------------
; tab_next_link - Cycle to next link via TAB key
; ----------------------------------------------------------------------------
.proc tab_next_link
        jsr mouse_hide_cursor
        jsr tab_find_next      ; scan VRAM for next link attr
        bcs ?none              ; no link found
        jsr mouse_show_cursor
        ; Extract link number from saved attr (set by mouse_invert_char)
        lda mouse_saved_attr
        sec
        sbc #ATTR_LINK_BASE
        sta zp_tab_link
?none   rts
.endp

; ----------------------------------------------------------------------------
; ui_settings - Settings screen
; P toggles proxy, ESC/Q exits
