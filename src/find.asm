; ============================================================================
; Find in page
; Ctrl+F opens "Find: " prompt. Scans visible content rows for the typed
; string (case-insensitive, ASCII). Highlights all matches in yellow.
; Any key closes find mode and restores original attributes.
; ============================================================================

FIND_MAX_LEN    = 16
FIND_MAX_MATCH  = 16
FIND_HILITE     = COL_YELLOW

; Find state in page 5 (free RAM)
find_buf         = $0500          ; 16 B search string
find_match_row   = $0510          ; 16 B row per match
find_match_col   = $0520          ; 16 B col (0..79) per match
find_len         = $0530          ; search string length
find_count       = $0531          ; number of VIEWPORT matches (highlighted)
find_total       = $0532          ; total matches in full page buffer (counted only)
find_mpos        = $0533          ; full-scan: partial match position
find_intag       = $0534          ; full-scan: inside HTML tag flag
find_fold        = $0540          ; 16 B search string, case-folded

; Saved attributes — packed linearly as matches are processed.
; For match i we save find_len bytes, running total <= FIND_MAX_MATCH*FIND_MAX_LEN = 256.
find_saved       = $0700          ; 256 B in page 7

; ----------------------------------------------------------------------------
; find_start - Entry point (called from Ctrl+F dispatch)
; ----------------------------------------------------------------------------
.proc find_start
 .if 1                          ; 2026-09-23 (one status bar for everything)
        status_msg COL_GREEN, m_prompt
        lda #COL_GREEN         ; typed text: inverse, in the bar
        sta zp_cur_attr
        lda #$80
        sta kgl_inv
 .else
        ; "Find: " prompt on status bar
        lda #STATUS_ROW
        ldx #COL_GREEN
        jsr vbxe_fill_row
        lda #STATUS_ROW
        ldx #0
        jsr vbxe_setpos
        lda #COL_GREEN
        sta zp_cur_attr
        lda #<m_prompt
        ldx #>m_prompt
        jsr vbxe_print
 .endif

        ; Read into find_buf
        lda #<find_buf
        sta zp_tmp_ptr
        lda #>find_buf
        sta zp_tmp_ptr+1
        ldx #FIND_MAX_LEN-1
        jsr kbd_get_line
        bcs ?bail                   ; ESC
        sty find_len
        tya
        beq ?bail                   ; empty

        jsr find_scan
        lda find_count
        bne ?have
        status_msg COL_RED, m_nomatch
        jsr kbd_get
        jmp ui_status_end

?have   jsr find_highlight
        jsr find_scan_full          ; count total matches in whole page
 .if 1                          ; 2026-09-23 (one status bar for everything)
        status_msg COL_GREEN, m_found
        lda find_count
        jsr sb_num
        lda #<m_visible
        ldx #>m_visible
        jsr sb_text
        lda find_total
        jsr sb_num
        lda #<m_total
        ldx #>m_total
        jsr sb_text
 .else
        status_msg COL_YELLOW, m_found
        lda find_count
        jsr find_print_num
        lda #<m_visible
        ldx #>m_visible
        jsr vbxe_print
        lda find_total
        jsr find_print_num
        lda #<m_total
        ldx #>m_total
        jsr vbxe_print
 .endif
        jsr kbd_get
        jsr find_restore
        jmp ui_status_end

?bail   jmp ui_status_end
.endp

; ----------------------------------------------------------------------------
; find_scan - Scan content rows for find_buf. Populates match arrays.
; Case-insensitive for ASCII letters (ORA #$20).
; ----------------------------------------------------------------------------
        page_fit find_scan.col_loop-find_scan, find_scan.col_end-find_scan.col_loop
.proc find_scan
        lda #0
        sta find_count
        ; Case-folded copy of the search string (compared as is below)
        ldx find_len
?fold   lda find_buf-1,x
        ora #$20
        sta find_fold-1,x
        dex
        bne ?fold
        ; Last start offset: col + len <= 80  ->  Y <= 2 * (80 - len)
        lda #SCR_COLS
        sec
        sbc find_len
        asl
        adc #2                 ; C = 0 (len >= 1): loop while Y < 2*(80-len)+2
        sta ?lim+1

        memb_on 0

        ldx #CONTENT_TOP
?rowlp  stx zp_tmp2            ; row
        lda row_addr_lo,x
        sta zp_scr_ptr
        lda row_addr_hi,x
        sta zp_scr_ptr+1

        ldy #0                 ; Y = char-byte offset within row (0,2,4,...)
col_loop
?collp  sty zp_tmp1            ; start offset
        ldx #0                 ; index into find_fold
cmp_loop
?cmplp  lda (zp_scr_ptr),y
        and #$7F               ; ignore inverse video bit
        ora #$20               ; case-fold
        cmp find_fold,x
        bne ?miss
        iny
        iny
        inx
        cpx find_len
        bne ?cmplp
cmp_end
        ert >?cmplp <> >*         ; hot loop: keep it in one page

        ldx find_count         ; hit
        lda zp_tmp2
        sta find_match_row,x
        lda zp_tmp1
        lsr
        sta find_match_col,x
        inx
        stx find_count
        cpx #FIND_MAX_MATCH
        beq ?done
?miss   ldy zp_tmp1
        iny
        iny
?lim    cpy #0                 ; (operand patched)
        bcc ?collp
col_end
        ert >?collp <> >*      ; the column scan stays in one page

        ldx zp_tmp2
        inx
        cpx #CONTENT_BOT+1
        bcc ?rowlp

?done   memb_off
        rts
.endp

; ----------------------------------------------------------------------------
; find_highlight - Save original attrs and write highlight to all matches
; ----------------------------------------------------------------------------
.proc find_highlight
        memb_on 0
        lda #0
        sta ?sidx
        sta ?mi
?mlp    ldx ?mi
        cpx find_count
        bcs ?done
        ldy find_match_row,x
        lda row_addr_lo,y
        sta zp_scr_ptr
        lda row_addr_hi,y
        sta zp_scr_ptr+1
        lda find_match_col,x
        sec
        rol                    ; Y = col*2+1 = attr offset of the first char
        tay
        lda find_len
        sta ?n
        ldx ?sidx
?clp    lda (zp_scr_ptr),y     ; save the original attr
        sta find_saved,x
        inx
        lda #FIND_HILITE
        sta (zp_scr_ptr),y
        iny
        iny
        dec ?n
        bne ?clp
        stx ?sidx
        inc ?mi
        bne ?mlp               ; always
?done   memb_off
        rts

?mi     dta 0
?sidx   dta 0
?n      dta 0
.endp

; ----------------------------------------------------------------------------
; find_restore - Write saved attrs back (mirrors find_highlight layout)
; ----------------------------------------------------------------------------
 .if 1                          ; 2026-09-23 (6502-cycles-layout: the match loop in one page)
        page_fit 0, find_restore.pend-find_restore
 .endif
.proc find_restore
        memb_on 0
        lda #0
        sta ?sidx
        sta ?mi
?mlp    ldx ?mi
        cpx find_count
        bcs ?done
        ldy find_match_row,x
        lda row_addr_lo,y
        sta zp_scr_ptr
        lda row_addr_hi,y
        sta zp_scr_ptr+1
        lda find_match_col,x
        sec
        rol                    ; Y = attr offset of the first char
        tay
        lda find_len
        sta ?n
        ldx ?sidx
?clp    lda find_saved,x
        sta (zp_scr_ptr),y
        inx
        iny
        iny
        dec ?n
        bne ?clp
        stx ?sidx
        inc ?mi
        bne ?mlp               ; always
?done   memb_off
        rts
pend

?mi     dta 0
?sidx   dta 0
?n      dta 0
.endp

; ----------------------------------------------------------------------------
; find_print_num - Print A as 1-2 digit decimal at cursor
; ----------------------------------------------------------------------------
.proc find_print_num
        ldx #0
?t      cmp #10
        bcc ?o
        sbc #10
        inx
        bne ?t                 ; always
?o      pha
        txa
        beq ?no_t
        ora #'0'
        jsr vbxe_putchar
?no_t   pla
        ora #'0'
        jmp vbxe_putchar
.endp

; ----------------------------------------------------------------------------
; find_scan_full - Walk the entire VRAM page buffer, count matches of find_buf
; while skipping content inside HTML tags (<...>). Case-insensitive (ASCII).
; Saves and restores the parser's read pointer so rendering can resume.
; ----------------------------------------------------------------------------
 .if 1                          ; 2026-09-23 (6502-cycles-layout: the whole byte loop with its
                                ; ?lt/?gt/?reset_m arms in one page)
        page_fit find_scan_full.slp_s-find_scan_full, find_scan_full.slp_e-find_scan_full.slp_s
 .endif
.proc find_scan_full
        ; Save parser read state
        lda pb_rd_bank
        sta ?sv_bank
        lda zp_pb_rd_ptr
        sta ?sv_lo
        lda zp_pb_rd_ptr+1
        sta ?sv_hi
        lda pb_read
        sta ?sv_rd0
        lda pb_read+1
        sta ?sv_rd1
        lda pb_read+2
        sta ?sv_rd2
        lda zp_rx_len
        sta ?sv_rxlen

        ; Rewind to start of page buffer
        jsr vbxe_pb_init_read

        lda #0
        sta find_total
        sta zp_tmp3            ; inside-tag flag in bit 7 during the scan
        sta find_mpos

?cloop  ; remaining = pb_total - pb_read (24-bit), chunk = min(255, remaining)
        lda pb_total
        sec
        sbc pb_read
        tay
        lda pb_total+1
        sbc pb_read+1
        tax
        lda pb_total+2
        sbc pb_read+2
        bne ?has_upper         ; remaining >= 65536
        txa
        bne ?has_upper         ; remaining >= 256
        tya
        beq ?done              ; remaining = 0
        bne ?do_read           ; always
?has_upper
        lda #255
?do_read
        jsr vbxe_pb_read_chunk ; reads A bytes, zp_rx_len = A
        clc                    ; pb_read += zp_rx_len
        lda pb_read
        adc zp_rx_len
        sta pb_read
        bcc ?npr
        inc pb_read+1
        bne ?npr
        inc pb_read+2
?npr
        ldx find_mpos          ; X = partial match position
        ldy #0
slp_s
?slp    cpy zp_rx_len
        bcs ?chunk_end
        lda rx_buffer,y
        iny
        cmp #'<'
        beq ?lt
        cmp #'>'
        beq ?gt
        bit zp_tmp3            ; inside a tag: skip (N = bit 7 of the flag)
        bmi ?slp
        ert >?slp <> >*         ; hot loop: keep it in one page
        and #$7F
        ora #$20
        cmp find_fold,x
        bne ?reset_m
        inx
        cpx find_len
        bne ?slp
        inc find_total         ; complete match
?reset_m
        ldx #0
        beq ?slp               ; always
?lt     lda #$80
        sta zp_tmp3
        ldx #0
        beq ?slp               ; always
?gt     lda #0
        sta zp_tmp3
        beq ?slp               ; always
slp_e
?chunk_end
        stx find_mpos
        jmp ?cloop

?done   lda zp_tmp3            ; find_intag = 0/1 as before
        asl
        lda #0
        rol
        sta find_intag
        ; The scan reused rx_buffer: reload the chunk the parser is on (find
        ; can run from --More-- in the middle of a page), then its state
        lda http_render.pb_rd_save_bank
        sta pb_rd_bank
        lda http_render.pb_rd_save_lo
        sta zp_pb_rd_ptr
        lda http_render.pb_rd_save_hi
        sta zp_pb_rd_ptr+1
        lda http_render.pb_chunk_size
        jsr vbxe_pb_read_chunk
        ; Restore parser state
        lda ?sv_bank
        sta pb_rd_bank
        lda ?sv_lo
        sta zp_pb_rd_ptr
        lda ?sv_hi
        sta zp_pb_rd_ptr+1
        lda ?sv_rd0
        sta pb_read
        lda ?sv_rd1
        sta pb_read+1
        lda ?sv_rd2
        sta pb_read+2
        lda ?sv_rxlen
        sta zp_rx_len
        jmp parse_sentinel

?sv_bank  dta 0
?sv_lo    dta 0
?sv_hi    dta 0
?sv_rd0   dta 0
?sv_rd1   dta 0
?sv_rd2   dta 0
?sv_rxlen dta 0
.endp

 .if 1                          ; 2026-09-23 (one status bar for everything)
m_prompt  dta c' Find: ',1,c'Return  Search   Esc  Cancel',0
m_nomatch dta c' No matches',1,c'any key',0
m_found   dta c' Matches: ',1,c'any key',0
 .else
m_prompt  dta c'Find: ',0
m_nomatch dta c' No matches (press a key)',0
m_found   dta c' Matches: ',0
 .endif
m_visible dta c' visible, ',0
m_total   dta c' total',0
