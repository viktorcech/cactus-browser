; ============================================================================
; Mouse Module - Atari ST mouse driver via joystick port
; Timer 2 IRQ for fast quadrature sampling (GOS-style lookup table)
; VBI for applying accumulated movement to text cursor
; Based on flashjazzcat's GOS mouse driver + PAD game + xlpaint
;
; MEMAC B safety: This module is above $4000 (in MEMAC B window).
; - The timer IRQ runs entirely from page 6 with its tables at $8300+
;   (outside the window), so it never touches MEMAC B
; - The VBI uses entry/exit stubs at page 6 to disable/restore MEMAC B
; - VRAM access uses vbxe_cell_get/vbxe_cell_put (below $4000)
; - NO memb_on/memb_off in this file!
; ============================================================================

MOUSE_PORT2 = 1               ; 0=port 1, 1=port 2

STRIG0     = $D010             ; used when MOUSE_PORT2=0
STRIG1     = $D011
SETVBV     = $E45C
XITVBV     = $E462

POKMSK     = $10               ; IRQ enable shadow
IRQEN      = $D20E
AUDF2      = $D202
AUDC2      = $D203
AUDCTL     = $D208
STIMER     = $D209
VTIMR2     = $0212             ; Timer 2 IRQ vector

; Zero-page variables ($B0-$B7)
zp_mouse_x    = $B0            ; text column 0-79
zp_mouse_y    = $B1            ; text row 0-23
zp_mouse_btn  = $B2            ; 0=none, 1=clicked
zp_mouse_old  = $B3            ; last port nibble (timer IRQ)
zp_mouse_dx   = $B4            ; accumulated X delta (signed, reset each VBI)
zp_mouse_dy   = $B5            ; accumulated Y delta (signed, reset each VBI)
zp_mouse_prev_x = $B6          ; previous cursor col
zp_mouse_prev_y = $B7          ; previous cursor row

; ----------------------------------------------------------------------------
; Page 6 stubs ($0600), copied from mouse_stubs by mouse_install_stubs:
;   Timer IRQ: the whole handler (OS saved A; it saves Y itself)
;   VBI entry: save shadow, disable MEMAC B, jmp mouse_vbi (OS saved A,X,Y)
;   VBI exit:  restore shadow + MEMAC B, jmp XITVBV
; Shadow save/restore keeps a VBI nested inside MEMAC B code safe.
; ----------------------------------------------------------------------------
STUB_BASE       = $0600
STUB_VBI_ENTRY  = STUB_BASE + mst_vbi_entry - mouse_stubs
STUB_VBI_EXIT   = STUB_BASE + mst_vbi_exit - mouse_stubs

; ----------------------------------------------------------------------------
; mouse_init
; ----------------------------------------------------------------------------
.proc mouse_init
        lda #40
        sta zp_mouse_x
        lda #12
        sta zp_mouse_y
        lda #$FF
        sta zp_mouse_prev_x    ; $FF = invalid, skip first restore
        sta zp_mouse_prev_y
        lda #0
        sta zp_mouse_btn
        sta zp_mouse_dx
        sta zp_mouse_dy
        sta zp_memb_shadow
        sta zp_vbi_saved

        ; Initial port nibble
        lda PORTA
    .if MOUSE_PORT2
        lsr
        lsr
        lsr
        lsr
    .else
        and #$0F
    .endif
        sta zp_mouse_old

        ; Install all stubs at page 6
        jsr mouse_install_stubs

        ; Install Timer 2 IRQ (the page 6 handler)
        sei
        lda #<STUB_BASE
        sta VTIMR2
        lda #>STUB_BASE
        sta VTIMR2+1

        ; Enable Timer 2 IRQ (bit 1)
        lda POKMSK
        ora #$02
        sta POKMSK
        sta IRQEN

        ; Set timer frequency (64kHz / 65 ≈ 985 Hz)
        lda #0
        sta AUDCTL
        sta AUDC2              ; no sound output
        lda #$40
        sta AUDF2
        sta STIMER
        cli

        ; Install deferred VBI via entry stub
        ldy #<STUB_VBI_ENTRY
        ldx #>STUB_VBI_ENTRY
        lda #7
        jmp SETVBV
.endp

; ----------------------------------------------------------------------------
; mouse_install_stubs - Copy the stubs to page 6 and patch the VBI jump
; ----------------------------------------------------------------------------
.proc mouse_install_stubs
        ldy #mst_end-mouse_stubs-1
?lp     lda mouse_stubs,y
        sta STUB_BASE,y
        dey
        bpl ?lp
        lda #<mouse_vbi
        sta STUB_BASE+mst_vbi_jmp-mouse_stubs+1
        lda #>mouse_vbi
        sta STUB_BASE+mst_vbi_jmp-mouse_stubs+2
        rts
.endp

; === Stub templates: position independent (relative branches only) ===
; Timer 2 IRQ, sampled at ~985 Hz: decode both quadrature axes with one
; table read. Reads only zero page, PORTA and the $8300+ tables, so it runs
; safely with the MEMAC B window open.
mouse_stubs
        tya
        pha
        lda PORTA
    .if MOUSE_PORT2
        and #$F0               ; new nibble << 4
    .else
        asl
        asl
        asl
        asl
    .endif
        ora zp_mouse_old
        tay                    ; new<<4 | old
        lda mouse_tab,y
        bne mst_move
mst_back   lda mouse_nib,y        ; old = new
        sta zp_mouse_old
        pla
        tay
        pla                    ; A saved by the OS IRQ handler
        rti
mst_move   lsr                    ; bit0: X+1
        bcc mst_m1
        inc zp_mouse_dx
mst_m1     lsr                    ; bit1: X-1
        bcc mst_m2
        dec zp_mouse_dx
mst_m2     lsr                    ; bit2: Y+1
        bcc mst_m3
        inc zp_mouse_dy
mst_m3     lsr                    ; bit3: Y-1
        bcc mst_back
        dec zp_mouse_dy
        bcs mst_back              ; always (C = 1)

        ; VBI entry: OS saved A,X,Y
mst_vbi_entry
        cld
        lda zp_memb_shadow
        sta zp_vbi_saved
        lda #0
        sta zp_memb_shadow
        ldy #VBXE_MEMAC_B
        sta (zp_vbxe_base),y
mst_vbi_jmp
        jmp $0000              ; patched: mouse_vbi

        ; VBI exit: restore shadow + MEMAC B, JMP XITVBV (restores A,X,Y)
mst_vbi_exit
        lda zp_vbi_saved
        sta zp_memb_shadow
        beq mst_x                 ; was off: register already 0
        ldy #VBXE_MEMAC_B
        sta (zp_vbxe_base),y
mst_x      jmp XITVBV
mst_end
        ert mst_end-mouse_stubs>256

; ----------------------------------------------------------------------------
; mouse_vbi - Deferred VBI: apply accumulated deltas to cursor position
; Exit via stub at page 6 (restores MEMAC B, JMP XITVBV)
;
; Speed handling (per axis, per frame):
; - Slow movement (|delta| < MOUSE_ACCEL): half speed, but the leftover
;   count is carried over to the next frame instead of being truncated.
;   The old code dropped it — a delta of 1 became 0, so slow precise
;   movements didn't move the cursor at all until you sped up.
; - Fast movement (|delta| >= MOUSE_ACCEL): full delta, no division —
;   2x faster sweeps (simple acceleration).
; ----------------------------------------------------------------------------
MOUSE_ACCEL = 6                ; counts/frame where acceleration kicks in

.proc mouse_vbi
        ; --- Apply X delta (signed) ---
        lda zp_mouse_dx
        beq ?do_y
        bpl ?x_pos

        ; Negative X = move left
        eor #$FF
        clc
        adc #1                 ; A = abs(dx)
        ldx #0
        stx zp_mouse_dx        ; consume (leftover may be put back below)
        cmp #MOUSE_ACCEL
        bcs ?xn_go             ; fast: use full delta
        lsr                    ; slow: half, C = leftover count
        bcc ?xn_go
        ldx #$FF
        stx zp_mouse_dx        ; carry leftover (-1) to next frame
?xn_go  eor #$FF                ; x - n = x + ~n + 1, clamped at the left edge
        sec
        adc zp_mouse_x
        bcs ?xl
        lda #0
?xl     sta zp_mouse_x
        bpl ?do_y              ; always (x <= 79)

?x_pos  ldx #0
        stx zp_mouse_dx        ; consume (leftover may be put back below)
        cmp #MOUSE_ACCEL
        bcs ?xp_go             ; fast: use full delta
        lsr                    ; slow: half, C = leftover count
        bcc ?xp_go
        ldx #1
        stx zp_mouse_dx        ; carry leftover (+1) to next frame
?xp_go  clc                    ; x + n, clamped at the right edge
        adc zp_mouse_x         ; (<= 79 + 5 / 2: no overflow)
        cmp #SCR_COLS
        bcc ?xr
        lda #SCR_COLS-1
?xr     sta zp_mouse_x

        ; --- Apply Y delta (signed) ---
?do_y   lda zp_mouse_dy
        beq ?btn
        bpl ?y_pos

        eor #$FF
        clc
        adc #1                 ; A = abs(dy)
        ldx #0
        stx zp_mouse_dy
        cmp #MOUSE_ACCEL
        bcs ?yn_go
        lsr
        bcc ?yn_go
        ldx #$FF
        stx zp_mouse_dy        ; carry leftover (-1)
?yn_go  eor #$FF                ; y - n, clamped at the top edge
        sec
        adc zp_mouse_y
        bcs ?yu
        lda #0
?yu     sta zp_mouse_y
        bpl ?btn               ; always (y <= 28)

?y_pos  ldx #0
        stx zp_mouse_dy
        cmp #MOUSE_ACCEL
        bcs ?yp_go
        lsr
        bcc ?yp_go
        ldx #1
        stx zp_mouse_dy        ; carry leftover (+1)
?yp_go  clc                    ; y + n, clamped at the bottom edge
        adc zp_mouse_y
        cmp #SCR_ROWS
        bcc ?yd
        lda #SCR_ROWS-1
?yd     sta zp_mouse_y

        ; --- Button ---
?btn
    .if MOUSE_PORT2
        lda STRIG1
    .else
        lda STRIG0
    .endif
        bne ?no_btn
        lda #1
        sta zp_mouse_btn
?no_btn
        ; Exit via stub at page 6 (restores MEMAC B, JMP XITVBV)
        jmp STUB_VBI_EXIT
.endp


; ----------------------------------------------------------------------------
; mouse_show_cursor - Update cursor on screen (call from main loop)
; ----------------------------------------------------------------------------
 .if 1                          ; 2026-09-23 (6502-cycles-layout: the whole proc in one page, the taken
                                ; branches do not cross)
        page_fit 0, mouse_show_cursor.pend-mouse_show_cursor
 .endif
.proc mouse_show_cursor
        lda zp_mouse_prev_x
        cmp zp_mouse_x
        bne ?moved
        lda zp_mouse_prev_y
        cmp zp_mouse_y
        beq ?done
?moved
        lda #$FF
        sta zp_tab_link        ; mouse movement clears TAB selection
        ; Skip restore if prev_x=$FF (invalid — screen was redrawn)
        lda zp_mouse_prev_x
        cmp #$FF
        beq ?no_restore
        lda zp_mouse_prev_y
        ldx zp_mouse_prev_x
        jsr mouse_restore_char
?no_restore
        lda zp_mouse_y
        ldx zp_mouse_x
        jsr mouse_invert_char

        lda zp_mouse_x
        sta zp_mouse_prev_x
        lda zp_mouse_y
        sta zp_mouse_prev_y
?done   rts
pend
.endp

; ----------------------------------------------------------------------------
; mouse_hide_cursor - Remove cursor before screen updates
; ----------------------------------------------------------------------------
.proc mouse_hide_cursor
        lda zp_mouse_prev_x
        cmp #$FF
        beq ?done
        lda zp_mouse_prev_y
        ldx zp_mouse_prev_x
        jsr mouse_restore_char
        lda #$FF
        sta zp_mouse_prev_x    ; mark as restored, prevent double restore
?done   rts
.endp

; ----------------------------------------------------------------------------
; mouse_invert_char - Show cursor at A=row, X=col
; Uses vbxe_read_vram/vbxe_write_vram (below $4000) for VRAM access.
; ----------------------------------------------------------------------------
.proc mouse_invert_char
        jsr mouse_calc_vram    ; zp_tmp_ptr set, Y = col*2
        sty mouse_col_off
        jsr vbxe_cell_get      ; A = char, X = attr
        sta mouse_saved_char
        stx mouse_saved_attr
        ora #$80               ; inverted char, red attr
        ldx #COL_RED
        ldy mouse_col_off
        jmp vbxe_cell_put
.endp

; ----------------------------------------------------------------------------
; mouse_restore_char - Restore char+attr at A=row, X=col
; ----------------------------------------------------------------------------
.proc mouse_restore_char
        jsr mouse_calc_vram    ; Y = col*2
        lda mouse_saved_char
        ldx mouse_saved_attr
        jmp vbxe_cell_put
.endp

mouse_saved_char dta 0
mouse_saved_attr dta 0
mouse_col_off    dta 0

; ----------------------------------------------------------------------------
; mouse_calc_vram - MEMAC B address for text cell
; Input: A=row, X=col  Output: zp_tmp_ptr, Y=col*2
; ----------------------------------------------------------------------------
.proc mouse_calc_vram
        tay
        lda row_addr_lo,y      ; from vbxe_text.asm (below $4000)
        sta zp_tmp_ptr
        lda row_addr_hi,y
        sta zp_tmp_ptr+1
        txa
        asl
        tay
        rts
.endp

; ----------------------------------------------------------------------------
; mouse_check_link - Is cursor over a link? Find link number.
; Uses vbxe_read_vram for all VRAM access (safe from above $4000).
; Output: C=0 A=link#, C=1 not on link
; ----------------------------------------------------------------------------
.proc mouse_check_link
        ; Link number is encoded in the attr byte: $20+link_num
        ; mouse_saved_attr has the original attr from cursor position
        ; Output: C=0 A=link#, C=1 not on link
        lda mouse_saved_attr
        sec                    ; range test: C = 0 inside [$20, $5F]
        sbc #ATTR_LINK_BASE    ; A = link number
        cmp #MAX_LINKS         ; (attrs below $20 wrap to >= $E0)
        bcc ?yes
        lda mouse_saved_attr   ; not a link: A = attr as before (C = 1)
?yes    rts
.endp
