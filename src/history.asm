; ============================================================================
; History Module - URL history stack
; ============================================================================

HIST_MAX       = 16
HIST_ENTRY_SZ  = 130   ; 128 bytes URL + 2 bytes scroll pos

; ----------------------------------------------------------------------------
; history_init
; ----------------------------------------------------------------------------
.proc history_init
        lda #0
        sta zp_hist_ptr
        rts
.endp

; ----------------------------------------------------------------------------
; history_push - Save current URL to history stack
; ----------------------------------------------------------------------------
.proc history_push
        lda zp_hist_ptr
        cmp #HIST_MAX
        bcc ?room
        jsr history_shift
        dec zp_hist_ptr

?room   jsr calc_hist_addr

        ldy #128               ; scroll pos after the 128-byte URL
        lda zp_scroll_pos
        sta (zp_tmp_ptr),y
        iny
        lda zp_scroll_pos+1
        sta (zp_tmp_ptr),y
        ldy #127
?cp     lda url_buffer,y
        sta (zp_tmp_ptr),y
        dey
        bpl ?cp

        inc zp_hist_ptr
        rts
.endp

; ----------------------------------------------------------------------------
; history_pop - Restore URL from history
; Output: C=0 ok, C=1 empty
; ----------------------------------------------------------------------------
.proc history_pop
        lda zp_hist_ptr
        beq ?empty

        dec zp_hist_ptr
        jsr calc_hist_addr

        ldy #128
        lda (zp_tmp_ptr),y
        sta zp_scroll_pos
        iny
        lda (zp_tmp_ptr),y
        sta zp_scroll_pos+1
        ldy #127
?cp     lda (zp_tmp_ptr),y
        sta url_buffer,y
        dey
        bpl ?cp

        ; Recalc url_length
        ldy #0
?len    lda url_buffer,y
        beq ?gl
        iny
        bne ?len
?gl     sty url_length
        clc
        rts

?empty  sec
        rts
.endp

; ----------------------------------------------------------------------------
; calc_hist_addr - Set zp_tmp_ptr to history_data + zp_hist_ptr * 130
; Table lookup instead of the old repeated-add loop (x130 per entry)
; ----------------------------------------------------------------------------
.proc calc_hist_addr
        ldx zp_hist_ptr
        lda hist_addr_lo,x
        sta zp_tmp_ptr
        lda hist_addr_hi,x
        sta zp_tmp_ptr+1
        rts
.endp

hist_addr_lo
        :HIST_MAX dta <(history_data + # * HIST_ENTRY_SZ)
hist_addr_hi
        :HIST_MAX dta >(history_data + # * HIST_ENTRY_SZ)

; ----------------------------------------------------------------------------
; history_shift - Shift entries down (discard oldest)
; ----------------------------------------------------------------------------
.proc history_shift
        ldx #1
?lp     lda hist_addr_lo,x     ; source = entry X
        sta zp_tmp_ptr2
        lda hist_addr_hi,x
        sta zp_tmp_ptr2+1
        lda hist_addr_lo-1,x   ; dest = entry X-1
        sta zp_tmp_ptr
        lda hist_addr_hi-1,x
        sta zp_tmp_ptr+1
 .if 1                          ; 2026-09-23 (6502-idioms: count DOWN, dex/bne): Y = SZ-1..1 in the
                                ; loop, byte 0 after it; entries do not overlap, so order is free
        ldy #HIST_ENTRY_SZ-1
?cp     lda (zp_tmp_ptr2),y    ; 130 bytes (> 128: no dey/bpl)
        sta (zp_tmp_ptr),y
        dey
        bne ?cp
        lda (zp_tmp_ptr2),y    ; Y = 0
        sta (zp_tmp_ptr),y
 .else
        ldy #0
?cp     lda (zp_tmp_ptr2),y    ; 130 bytes (> 128: no dey/bpl)
        sta (zp_tmp_ptr),y
        iny
        cpy #HIST_ENTRY_SZ
        bne ?cp
 .endif
        inx
        cpx #HIST_MAX
        bne ?lp
        ldx #HIST_MAX-2        ; zp_hist_ptr as the old per-entry loop left
        stx zp_hist_ptr        ; it (history_push decrements it next)
        rts
.endp
