; ============================================================================
; Bookmarks Module
; Storage: D1: sectors 719-720 (raw SIO, no DOS dependency)
; 4 slots × 64 bytes, URL NUL-terminated.
; Buffer at $0500 (page 5) — does not consume data.asm buffer space.
;
; UI pattern follows mag/menu.asm: CH register polling, clear CH after read.
; ============================================================================

BK_SLOTS       = 10
BK_SLOT_SZ     = 64
BK_SECT_FIRST  = 716                ; 5 sectors (716..720), 2 slots per sector
BK_NUM_SECT    = 5

STICK0         = $0278              ; port 1 joystick shadow (MAG-style nav)

bookmarks_buf  = $0800              ; 640 bytes of free RAM (pages 8..10)

; Per-slot address lookup (10 slots, 64 B each at bookmarks_buf)
bk_slot_lo
        :BK_SLOTS dta <(bookmarks_buf + # * BK_SLOT_SZ)
bk_slot_hi
        :BK_SLOTS dta >(bookmarks_buf + # * BK_SLOT_SZ)

; ----------------------------------------------------------------------------
; bk_slot_addr - Set zp_tmp_ptr to slot X address (X preserved)
; ----------------------------------------------------------------------------
.proc bk_slot_addr
        lda bk_slot_lo,x
        sta zp_tmp_ptr
        lda bk_slot_hi,x
        sta zp_tmp_ptr+1
        rts
.endp

; ----------------------------------------------------------------------------
; bk_sio_sector - Read or write one D1: sector
; Input: A=0 read, A!=0 write; bk_sect_lo/hi = sector; zp_tmp_ptr = buffer
; Output: C=0 ok, C=1 error
; ----------------------------------------------------------------------------
.proc bk_sio_sector
        tax                         ; X = 0 read, else write
        lda #$31
        sta DDEVIC
        lda #1
        sta DUNIT
        txa
        beq ?rd
        lda #'P'
        sta DCOMND
        lda #$80
        bne ?dirset
?rd     lda #'R'
        sta DCOMND
        lda #$40
?dirset sta DSTATS
        lda zp_tmp_ptr
        sta DBUFLO
        lda zp_tmp_ptr+1
        sta DBUFHI
        lda #15
        sta DTIMLO
        lda #128
        sta DBYTLO
        lda #0
        sta DBYTHI
        lda bk_sect_lo
        sta DAUX1
        lda bk_sect_hi
        sta DAUX2
        jmp sio_ok
.endp

bk_sect_lo  dta 0
bk_sect_hi  dta 0
bk_sel      dta 0

; ----------------------------------------------------------------------------
; bk_load - Read both sectors into bookmarks_buf, sanitize invalid slots.
; Called once at startup from main.
; ----------------------------------------------------------------------------
.proc bk_load
        lda #0                      ; A=0 = read
        jsr bk_rw_all
        bcc bk_sanitize
        ldx #BK_SLOTS-1
        lda #0
?zl     ldy bk_slot_lo,x            ; slot byte 0 = 0 (empty)
        sty ?st+1
        ldy bk_slot_hi,x
        sty ?st+2
?st     sta $FFFF
        dex
        bpl ?zl
        rts
.endp

; bk_rw_all - Read (A=0) or write (A!=0) all BK_NUM_SECT sectors.
; Sector i = BK_SECT_FIRST + i, buffer at bookmarks_buf + i*128.
.proc bk_rw_all
        sta bk_rw_req
        ldx #BK_NUM_SECT-1     ; sector order does not matter: count down
?lp     stx ?i
        ; Sector = BK_SECT_FIRST + X
        txa
        clc
        adc #<BK_SECT_FIRST
        sta bk_sect_lo
        lda #0
        adc #>BK_SECT_FIRST
        sta bk_sect_hi
        ; Buffer = bookmarks_buf + X*128 (table)
        lda bk_sect_off_lo,x
        clc
        adc #<bookmarks_buf
        sta zp_tmp_ptr
        lda bk_sect_off_hi,x
        adc #>bookmarks_buf
        sta zp_tmp_ptr+1
        lda bk_rw_req
        jsr bk_sio_sector
        bcs ?err               ; C = 1: error
        ldx ?i
        dex
        bpl ?lp
?err    rts                    ; C = 0 after the last good sector
?i      dta 0
.endp

; X*128 offsets for BK_NUM_SECT=5 sectors
bk_sect_off_lo dta $00, $80, $00, $80, $00
bk_sect_off_hi dta $00, $00, $01, $01, $02
bk_rw_req      dta 0

; ----------------------------------------------------------------------------
; bk_sanitize - For each slot, verify byte 0 to first NUL are printable ASCII.
; If not (or no NUL within 63 bytes), zero byte 0 to mark empty.
; Protects against garbage in uninitialized ATR sectors.
; ----------------------------------------------------------------------------
.proc bk_sanitize
        ldx #BK_SLOTS-1
?slot   stx ?i
        jsr bk_slot_addr
        ldy #0
?scan   lda (zp_tmp_ptr),y
        beq ?ok                     ; NUL terminator = slot is valid
        cmp #$20
        bcc ?bad
        cmp #$7F
        bcs ?bad
        iny
        cpy #BK_SLOT_SZ-1
        bne ?scan
?bad    lda #0
        tay
        sta (zp_tmp_ptr),y
?ok     ldx ?i
        dex
        bpl ?slot
        rts
?i      dta 0
.endp

; ----------------------------------------------------------------------------
; bk_save - Persist bookmarks_buf back to both sectors
; ----------------------------------------------------------------------------
.proc bk_save
        lda #1                      ; A!=0 = write
        jmp bk_rw_all
.endp

; ============================================================================
; Bookmark window UI (MAG-style: CH register polling, not CIO)
; ============================================================================

.proc bk_screen
        jsr mouse_hide_cursor
        jsr ui_init
        jsr bk_draw_header
        jsr bk_draw_hint

        lda #0
        sta bk_sel
        jsr bk_draw_list

?wait   lda RTCLOK+2                ; sync to VBI (MAG pattern)
?wvs    cmp RTCLOK+2
        beq ?wvs

        ; Joystick port 1 — MAG uses stick0 for up/down
        lda STICK0
        cmp #14                     ; up
        beq ?stk_up
        cmp #13                     ; down
        beq ?stk_dn

        ; Keyboard via CH
        lda CH
        cmp #$FF
        beq ?wait
        ldx #$FF               ; consume the key, A keeps it
        stx CH

        cmp #$0C                    ; RETURN = confirm (open filled / edit empty)
        jeq ?confirm
        cmp #$1C                    ; ESC = close window
        jeq ?close
        cmp #$0E                    ; '-' alt up
        beq ?ku
        cmp #$8E                    ; CTRL+'-' alt up
        beq ?ku
        cmp #$0F                    ; '=' alt down
        beq ?kdn
        cmp #$8F                    ; CTRL+'='
        beq ?kdn
        cmp #$3A                    ; D = delete
        jeq ?del
        cmp #$2A                    ; E = edit selected slot (even filled)
        jeq ?edit
        cmp #$3F                    ; A = add current page URL to empty slot
        jeq ?add
        ; Digit keys 1-9,0 jump straight to slot 1-10 and confirm
        ldx #BK_SLOTS-1
?kdig   cmp bk_digit_codes,x
        beq ?dighit
        dex
        bpl ?kdig
        jmp ?wait                   ; unrecognised key
?dighit lda bk_sel
        sta bk_old_sel
        stx bk_sel
        jsr bk_draw_two
        jmp ?confirm

?stk_up jsr bk_stick_release
?ku     lda bk_sel
        jeq ?wait
        sta bk_old_sel              ; redraw only the two affected rows
        dec bk_sel
        jsr bk_draw_two
        jmp ?wait

?stk_dn jsr bk_stick_release
?kdn    lda bk_sel
        cmp #BK_SLOTS-1
        jcs ?wait
        sta bk_old_sel
        inc bk_sel
        jsr bk_draw_two
        jmp ?wait

?confirm
        ldx bk_sel
        jsr bk_slot_addr
        ldy #0
        lda (zp_tmp_ptr),y
        jeq ?edit                   ; empty -> edit mode
?opcp   lda (zp_tmp_ptr),y
        sta url_buffer,y
        beq ?opd
        iny
        cpy #URL_BUF_SIZE-1
        bne ?opcp
        lda #0
        sta url_buffer,y
?opd    sty url_length

        ; Detect if URL (has '.') or search query (no '.') — mirror ui_url_input
        ldy #0
?ckd    lda url_buffer,y
        beq ?nodot                  ; end of string, no dot = search phrase
        cmp #'.'
        beq ?gonav                  ; dot found = treat as URL
        iny
        bne ?ckd
?nodot  jsr url_build_search        ; rewrite url_buffer as search URL
?gonav  lda #$FF
        sta zp_mouse_prev_x
        jsr history_push
        jmp http_navigate

?del    ldx bk_sel
        jsr bk_slot_addr
        ldy #0
        lda (zp_tmp_ptr),y
        jeq ?wait
        tya                         ; A = 0
        sta (zp_tmp_ptr),y
        jsr bk_save
        ldx bk_sel
        jsr bk_draw_row
        jmp ?wait

?edit   ; Edit selected slot (RETURN on empty slot, or E on any slot)
        ldx bk_sel
        jsr bk_edit
        jsr bk_draw_list
        jsr bk_draw_hint
        jmp ?wait

?add    ; Save current page URL into the first empty slot
        lda cur_page_url
        jeq ?wait                   ; no page loaded yet
        ldx #0
?afind  jsr bk_slot_addr            ; preserves X
        ldy #0
        lda (zp_tmp_ptr),y
        beq ?aslot
        inx
        cpx #BK_SLOTS
        bne ?afind
        jmp ?wait                   ; all slots full
?aslot  lda bk_sel
        sta bk_old_sel
        stx bk_sel                  ; select the new entry (visual feedback)
        ldy #0
?acp    lda cur_page_url,y
        sta (zp_tmp_ptr),y
        beq ?acpd
        iny
        cpy #BK_SLOT_SZ-1
        bne ?acp
        lda #0
        sta (zp_tmp_ptr),y
?acpd   jsr bk_save
        jsr bk_draw_two
        jmp ?wait

?close  ; ESC: restore welcome screen (window cleared the page content,
        ; so returning without a redraw left the list on screen — the
        ; window looked impossible to close)
        lda #$FF
        sta zp_mouse_prev_x
        jmp show_welcome
.endp

; CH scan codes for keys 1,2,3,4,5,6,7,8,9,0 -> slots 0-9
bk_digit_codes dta $1F,$1E,$1A,$18,$1D,$1B,$33,$35,$30,$32
bk_old_sel     dta 0

; ----------------------------------------------------------------------------
; bk_stick_release - Wait for joystick to return to center (MAG's debounce)
; ----------------------------------------------------------------------------
.proc bk_stick_release
?r      lda STICK0
        cmp #15
        bne ?r
        rts
.endp

; ----------------------------------------------------------------------------
; bk_edit - Inline edit of slot X using CIO kbd_get_line.
; On RETURN: save URL to slot and persist. On ESC: slot unchanged.
; ----------------------------------------------------------------------------
.proc bk_edit
        stx ?slot

        ; Clear row, position cursor, yellow attr
        txa
        clc
        adc #CONTENT_TOP+1
        sta ?row
        jsr vbxe_clear_row
        lda ?row
        ldx #4
        jsr vbxe_setpos
        lda #COL_YELLOW
        sta zp_cur_attr

        ; "N. " prefix
        lda ?slot
        clc
        adc #'1'
        jsr vbxe_putchar
        lda #'.'
        jsr vbxe_putchar
        lda #' '
        jsr vbxe_putchar

        ; Edit into url_save_buf (256 B, free outside image fetch)
        lda #<url_save_buf
        sta zp_tmp_ptr
        lda #>url_save_buf
        sta zp_tmp_ptr+1
        ldx #BK_SLOT_SZ-2
        jsr kbd_get_line
        bcs ?cancel
        tya
        beq ?cancel

        ; Copy url_save_buf (NUL-terminated) -> slot[?slot]
        ldx ?slot
        jsr bk_slot_addr
        ldy #0
?cp     lda url_save_buf,y
        sta (zp_tmp_ptr),y
        beq ?cpd
        iny
        cpy #BK_SLOT_SZ-1
        bne ?cp
        lda #0
        sta (zp_tmp_ptr),y
?cpd    jmp bk_save
?cancel rts
?slot   dta 0
?row    dta 0
.endp

; ----------------------------------------------------------------------------
; Drawing helpers
; ----------------------------------------------------------------------------

.proc bk_draw_header
        lda #TITLE_ROW
        jsr vbxe_clear_row
        lda #TITLE_ROW
        ldx #35
        jsr vbxe_setpos
        lda #ATTR_HEADING
        sta zp_cur_attr
        lda #<m_hdr
        ldx #>m_hdr
        jsr vbxe_print
        lda #ATTR_NORMAL
        sta zp_cur_attr
        rts
m_hdr   dta c'Bookmarks',0
.endp

.proc bk_draw_hint
 .if 1                          ; 2026-09-23 (one status bar for everything)
        ldy #COL_BLUE
        lda #<m_hint
        ldx #>m_hint
        jmp status_msg_sub
m_hint  dta c' Bookmarks',1,c'-= Move  Ret Open  E Edit  A Add  D Del  1-0 Slot  Esc Close',0
 .else
        lda #STATUS_ROW
        ldx #COL_GRAY
        jsr vbxe_fill_row
        lda #STATUS_ROW
        ldx #0
        jsr vbxe_setpos
        lda #COL_GRAY
        sta zp_cur_attr
        lda #<m_hint
        ldx #>m_hint
        jsr vbxe_print
        lda #ATTR_NORMAL
        sta zp_cur_attr
        rts
m_hint  dta c' -=/Joy:move  RET:open  E:edit  A:add page  D:del  1-0:slot  ESC:close',0
 .endif
.endp

; ----------------------------------------------------------------------------
; bk_draw_list - Redraw all slot rows (initial draw, after edit/delete)
; ----------------------------------------------------------------------------
.proc bk_draw_list
        ldx #BK_SLOTS-1
?lp     stx ?x
        jsr bk_draw_row
        ldx ?x
        dex
        bpl ?lp
        rts
?x      dta 0
.endp

; ----------------------------------------------------------------------------
; bk_draw_two - Redraw only the rows for bk_old_sel and bk_sel.
; Selection moves repaint 2 rows instead of all 10 (5x less VRAM work
; per keypress — snappier cursor in the list).
; ----------------------------------------------------------------------------
.proc bk_draw_two
        ldx bk_old_sel
        jsr bk_draw_row
        ldx bk_sel
        jmp bk_draw_row
.endp

; ----------------------------------------------------------------------------
; bk_draw_row - Draw one slot row. Input: X = slot index (0..BK_SLOTS-1)
; ----------------------------------------------------------------------------
.proc bk_draw_row
        stx ?i
        txa
        clc
        adc #CONTENT_TOP+1
        sta ?row
        jsr vbxe_clear_row
        lda ?row
        ldx #4
        jsr vbxe_setpos

        ; Selected row: yellow + ">" cursor, else normal + " "
        lda bk_sel
        cmp ?i
        bne ?nor
        lda #COL_YELLOW
        sta zp_cur_attr
        lda #'>'
        bne ?cwr                    ; always
?nor    lda #ATTR_NORMAL
        sta zp_cur_attr
        lda #' '
?cwr    jsr vbxe_putchar
        lda #' '
        jsr vbxe_putchar

        ; Slot number label: " 1.".." 9." for slots 0-8, "10." for slot 9
        ldx ?i
        inx                         ; 1..10
        txa
        cmp #10
        bne ?sng
        ; "10"
        lda #'1'
        jsr vbxe_putchar
        lda #'0'
        jmp ?lbl_dot
?sng    ; " N"
        pha
        lda #' '
        jsr vbxe_putchar
        pla
        clc
        adc #'0'
?lbl_dot jsr vbxe_putchar
        lda #'.'
        jsr vbxe_putchar
        lda #' '
        jsr vbxe_putchar

        ldx ?i
        jsr bk_slot_addr
        ldy #0
        lda (zp_tmp_ptr),y
        bne ?url
        lda #<m_emp
        ldx #>m_emp
        bne ?prt                    ; always (hi byte != 0)
?url    lda zp_tmp_ptr
        ldx zp_tmp_ptr+1
?prt    jsr vbxe_print
        lda #ATTR_NORMAL
        sta zp_cur_attr
        rts
?i      dta 0
?row    dta 0
m_emp   dta c'(empty)',0
.endp

 .if 1                          ; 2026-09-23 (settings saved on disk: D1: sector 715)
; ----------------------------------------------------------------------------
; set_load / set_save - Settings sector: 'C','S', version, use_proxy, 0...
; A missing or foreign sector (no "CS") keeps the defaults.
; ----------------------------------------------------------------------------
SET_SECT     = 715
settings_buf = $0A80                ; 128 B after bookmarks_buf (ends $0A7F)

.proc set_load
        jsr set_io
        lda #0                      ; read
        jsr bk_sio_sector
        bcs ?done
        lda settings_buf
        cmp #'C'
        bne ?done
        lda settings_buf+1
        cmp #'S'
        bne ?done
        lda settings_buf+3
        and #1
        sta use_proxy
?done   rts
.endp

.proc set_save
        ldx #127
        lda #0
?clr    sta settings_buf,x
        dex
        bpl ?clr
        lda #'C'
        sta settings_buf
        lda #'S'
        sta settings_buf+1
        lda #1                      ; format version
        sta settings_buf+2
        lda use_proxy
        sta settings_buf+3
        jsr set_io
        lda #1                      ; write
        jmp bk_sio_sector
.endp

; set_io - zp_tmp_ptr = settings_buf, sector = SET_SECT
.proc set_io
        lda #<settings_buf
        sta zp_tmp_ptr
        lda #>settings_buf
        sta zp_tmp_ptr+1
        lda #<SET_SECT
        sta bk_sect_lo
        lda #>SET_SECT
        sta bk_sect_hi
        rts
.endp
 .endif
