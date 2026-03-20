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

        ldy #0
?cp     lda url_buffer,y
        sta (zp_tmp_ptr),y
        iny
        cpy #128
        bne ?cp

        lda zp_scroll_pos
        sta (zp_tmp_ptr),y
        iny
        lda zp_scroll_pos+1
        sta (zp_tmp_ptr),y

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

        ldy #0
?cp     lda (zp_tmp_ptr),y
        sta url_buffer,y
        iny
        cpy #128
        bne ?cp

        lda (zp_tmp_ptr),y
        sta zp_scroll_pos
        iny
        lda (zp_tmp_ptr),y
        sta zp_scroll_pos+1

        ; Recalc url_length
        ldy #0
?len    lda url_buffer,y
        beq ?gl
        iny
        bne ?len
?gl     sty url_length
        lda #0
        sta url_length+1
        clc
        rts

?empty  sec
        rts
.endp

; ----------------------------------------------------------------------------
; calc_hist_addr - Set zp_tmp_ptr to history_data + zp_hist_ptr * 130
; ----------------------------------------------------------------------------
.proc calc_hist_addr
        lda #<history_data
        sta zp_tmp_ptr
        lda #>history_data
        sta zp_tmp_ptr+1

        ldx zp_hist_ptr
        beq ?done
?add    lda zp_tmp_ptr
        clc
        adc #HIST_ENTRY_SZ
        sta zp_tmp_ptr
        lda zp_tmp_ptr+1
        adc #0
        sta zp_tmp_ptr+1
        dex
        bne ?add
?done   rts
.endp

; ----------------------------------------------------------------------------
; history_shift - Shift entries down (discard oldest)
; ----------------------------------------------------------------------------
.proc history_shift
        ldx #0
?lp     inx
        cpx #HIST_MAX
        beq ?done

        stx zp_tmp1

        ; Source = entry X
        stx zp_hist_ptr
        jsr calc_hist_addr
        lda zp_tmp_ptr
        sta zp_tmp_ptr2
        lda zp_tmp_ptr+1
        sta zp_tmp_ptr2+1

        ; Dest = entry X-1
        ldx zp_tmp1
        dex
        stx zp_hist_ptr
        jsr calc_hist_addr

        ldy #0
?cp     lda (zp_tmp_ptr2),y
        sta (zp_tmp_ptr),y
        iny
        cpy #HIST_ENTRY_SZ
        bne ?cp

        ldx zp_tmp1
        jmp ?lp

?done   rts
.endp
