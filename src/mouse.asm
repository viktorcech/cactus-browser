; ============================================================================
; Mouse Module - Atari ST mouse driver via joystick port
; Timer 1 IRQ for fast quadrature sampling (GOS-style lookup table)
; VBI for applying accumulated movement to text cursor
; Based on flashjazzcat's GOS mouse driver + PAD game + xlpaint
;
; MEMAC B safety: This module is above $4000 (in MEMAC B window).
; - Interrupt handlers use entry/exit stubs at page 6 ($0600)
; - VRAM access uses vbxe_read_vram/vbxe_write_vram (below $4000)
; - NO memb_on/memb_off in this file!
; ============================================================================

MOUSE_PORT2 = 1               ; 0=port 1, 1=port 2

STRIG0     = $D010
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
zp_mouse_dx   = $B4            ; accumulated X delta (signed, reset each VBI)
zp_mouse_dy   = $B5            ; accumulated Y delta (signed, reset each VBI)
zp_mouse_prev_x = $B6          ; previous cursor col
zp_mouse_prev_y = $B7          ; previous cursor row

; ----------------------------------------------------------------------------
; Page 6 stub layout ($0600):
; Timer IRQ: OS only saves A, so entry must save Y (TYA PHA) before LDY #$5D.
; VBI (NMI): OS saves A,X,Y — XITVBV restores them, no extra save needed.
; Each interrupt saves zp_memb_shadow, clears it, disables MEMAC B register,
; then restores shadow+register on exit. No MEMAC B register reads.
;   $0600: Timer IRQ entry (17 bytes) - save Y, save shadow, disable MEMAC B
;   $0611: Timer IRQ exit (12 bytes) - restore shadow+MEMAC B, restore Y+A, RTI
;   $061D: VBI entry (15 bytes) - save shadow, disable MEMAC B
;   $062C: VBI exit (13 bytes) - restore shadow+MEMAC B, JMP XITVBV
; Total: 57 bytes
; ----------------------------------------------------------------------------
STUB_BASE       = $0600
STUB_TIRQ_EXIT  = STUB_BASE + 17
STUB_VBI_ENTRY  = STUB_BASE + 29
STUB_VBI_EXIT   = STUB_BASE + 44

; ----------------------------------------------------------------------------
; mouse_init
; ----------------------------------------------------------------------------
.proc mouse_init
        lda #40
        sta zp_mouse_x
        sta zp_mouse_prev_x
        lda #12
        sta zp_mouse_y
        sta zp_mouse_prev_y
        lda #0
        sta zp_mouse_btn
        sta zp_mouse_dx
        sta zp_mouse_dy
        sta zp_memb_shadow
        sta zp_tirq_saved
        sta zp_vbi_saved

        ; Read initial port state and prepare old_x/old_y (pre-shifted <<2)
        lda PORTA
    .if MOUSE_PORT2
        lsr
        lsr
        lsr
        lsr
    .endif
        and #$03
        asl
        asl
        sta mouse_old_x

        lda PORTA
    .if MOUSE_PORT2
        lsr
        lsr
        lsr
        lsr
    .endif
        lsr
        lsr
        and #$03
        asl
        asl
        sta mouse_old_y

        ; Install all stubs at page 6
        jsr mouse_install_stubs

        ; Install Timer 1 IRQ via entry stub
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
        jsr SETVBV
        rts
.endp

; ----------------------------------------------------------------------------
; mouse_install_stubs - Copy all 4 stubs to page 6 and patch JMP targets
; Timer IRQ: OS only saves A → entry must TYA PHA to save Y before LDY #$5D.
; VBI (NMI): OS saves A,X,Y → XITVBV restores, no extra save needed.
; Shadow save/restore prevents race condition when VBI nests inside Timer IRQ.
; ----------------------------------------------------------------------------
.proc mouse_install_stubs
        ; Copy entire template to page 6
        ldy #0
?lp     lda ?stubs,y
        sta STUB_BASE,y
        iny
        cpy #?stubs_end-?stubs
        bne ?lp

        ; Patch Timer IRQ entry: JMP target at offset 15,16
        lda #<mouse_timer_irq
        sta STUB_BASE+15
        lda #>mouse_timer_irq
        sta STUB_BASE+16

        ; Patch VBI entry: JMP target at offset 42,43
        lda #<mouse_vbi
        sta STUB_BASE+42
        lda #>mouse_vbi
        sta STUB_BASE+43
        rts

        ; === Stub templates (57 bytes total) ===

        ; Timer IRQ entry (offset 0, 17 bytes)
        ; OS only saved A → we must save Y too!
        ; Save Y, save shadow, clear shadow+MEMAC B, JMP handler
?stubs
        tya                    ; 98       save original Y
        pha                    ; 48       (on stack, below OS-saved A)
        lda zp_memb_shadow     ; A5 AD   read shadow
        sta zp_tirq_saved      ; 85 AE   save to timer copy
        lda #0                 ; A9 00
        sta zp_memb_shadow     ; 85 AD   clear shadow
        ldy #VBXE_MEMAC_B     ; A0 5D
        sta (zp_vbxe_base),y  ; 91 80   disable MEMAC B
        jmp $0000              ; 4C xx xx (patched)

        ; Timer IRQ exit (offset 17, 12 bytes)
        ; Restore shadow+MEMAC B, then pop Y and A, RTI
        ; NOTE: Y=$5D here (handler restores it from its own push)
        lda zp_tirq_saved      ; A5 AE   saved shadow
        sta zp_memb_shadow     ; 85 AD   restore shadow
        beq *+4                ; F0 02   skip STA if shadow was 0
        sta (zp_vbxe_base),y  ; 91 80   restore MEMAC B (Y=$5D)
        pla                    ; 68       pop original Y
        tay                    ; A8       restore Y
        pla                    ; 68       pop original A (from OS)
        rti                    ; 40

        ; VBI entry (offset 29, 15 bytes)
        ; OS saves A,X,Y → no extra reg saves needed
        ; Save shadow, clear shadow+MEMAC B, JMP handler
        lda zp_memb_shadow     ; A5 AD
        sta zp_vbi_saved       ; 85 AF
        lda #0                 ; A9 00
        sta zp_memb_shadow     ; 85 AD
        ldy #VBXE_MEMAC_B     ; A0 5D
        sta (zp_vbxe_base),y  ; 91 80
        jmp $0000              ; 4C xx xx (patched)

        ; VBI exit (offset 44, 13 bytes)
        ; Restore shadow+MEMAC B, JMP XITVBV (restores A,X,Y)
        lda zp_vbi_saved       ; A5 AF
        sta zp_memb_shadow     ; 85 AD
        beq *+6                ; F0 04   skip if was 0
        ldy #VBXE_MEMAC_B     ; A0 5D
        sta (zp_vbxe_base),y  ; 91 80
        jmp XITVBV             ; 4C 62 E4
?stubs_end
.endp

; ----------------------------------------------------------------------------
; mouse_timer_irq - Timer 1 ISR: sample PORTA, decode quadrature
; Uses GOS-style 16-entry lookup table (old<<2 | new) for robustness
; CRITICAL: Must save/restore X, Y. A saved by OS. Exit via stub.
; ----------------------------------------------------------------------------
.proc mouse_timer_irq
        ; NOTE: A already saved by OS IRQ handler before jumping to VTIMR1
        ; NOTE: MEMAC B disabled by entry stub at page 6
        txa
        pha
        tya
        pha

        ; Read port once
        lda PORTA
    .if MOUSE_PORT2
        lsr
        lsr
        lsr
        lsr
    .endif
        tax                    ; X = full nibble (bits 0-3)

        ; --- X axis ---
        and #$03               ; A = new X bits (0-3)
        ora mouse_old_x        ; combine with old<<2 = 4-bit index
        tay
        lda mouse_movtab,y     ; get delta: 0, 1, or $FF(-1)
        beq ?xd
        bmi ?xl
        inc zp_mouse_dx        ; +1 = move right
        jmp ?xd
?xl     dec zp_mouse_dx        ; -1 = move left
?xd
        ; Update old_x = new_bits << 2
        txa
        and #$03
        asl
        asl
        sta mouse_old_x

        ; --- Y axis ---
        txa
        lsr
        lsr
        and #$03               ; A = new Y bits (0-3)
        ora mouse_old_y
        tay
        lda mouse_movtab,y
        beq ?yd
        bmi ?yu
        inc zp_mouse_dy        ; +1 = move down
        jmp ?yd
?yu     dec zp_mouse_dy        ; -1 = move up
?yd
        ; Update old_y = new_bits << 2
        txa
        lsr
        lsr
        and #$03
        asl
        asl
        sta mouse_old_y

        pla
        tay
        pla
        tax
        ; Exit via stub at page 6 (restores MEMAC B + PLA + RTI)
        jmp STUB_TIRQ_EXIT

        ; GOS-style movement table (from flashjazzcat)
        ; Index = (old_2bits << 2) | new_2bits
        ; 0 = no movement, 1 = +1, $FF = -1
mouse_movtab
        dta 0,$FF,1,0, 1,0,0,$FF, $FF,0,0,1, 0,1,$FF,0
.endp

; ----------------------------------------------------------------------------
; mouse_vbi - Deferred VBI: apply accumulated deltas to cursor position
; Exit via stub at page 6 (restores MEMAC B, JMP XITVBV)
; ----------------------------------------------------------------------------
.proc mouse_vbi
        ; --- Apply X delta (signed) ---
        lda zp_mouse_dx
        beq ?do_y
        bpl ?x_pos

        ; Negative X = move left
        eor #$FF
        clc
        adc #1                 ; A = abs(dx)
        lsr                    ; divide by 2
        beq ?x_clr
        sta ?steps
?xl_lp  lda zp_mouse_x
        beq ?x_clr
        dec zp_mouse_x
        dec ?steps
        bne ?xl_lp
        jmp ?x_clr

?x_pos  lsr                    ; divide by 2
        beq ?x_clr
        sta ?steps
?xr_lp  lda zp_mouse_x
        cmp #SCR_COLS-1
        bcs ?x_clr
        inc zp_mouse_x
        dec ?steps
        bne ?xr_lp

?x_clr  lda #0
        sta zp_mouse_dx

        ; --- Apply Y delta (signed) ---
?do_y   lda zp_mouse_dy
        beq ?btn
        bpl ?y_pos

        eor #$FF
        clc
        adc #1
        lsr
        beq ?y_clr
        sta ?steps
?yu_lp  lda zp_mouse_y
        beq ?y_clr
        dec zp_mouse_y
        dec ?steps
        bne ?yu_lp
        jmp ?y_clr

?y_pos  lsr
        beq ?y_clr
        sta ?steps
?yd_lp  lda zp_mouse_y
        cmp #SCR_ROWS-1
        bcs ?y_clr
        inc zp_mouse_y
        dec ?steps
        bne ?yd_lp

?y_clr  lda #0
        sta zp_mouse_dy

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

?steps  dta 0
.endp

mouse_old_x     dta 0          ; old X bits, pre-shifted <<2
mouse_old_y     dta 0          ; old Y bits, pre-shifted <<2

; ----------------------------------------------------------------------------
; mouse_show_cursor - Update cursor on screen (call from main loop)
; ----------------------------------------------------------------------------
.proc mouse_show_cursor
        lda zp_mouse_prev_x
        cmp zp_mouse_x
        bne ?moved
        lda zp_mouse_prev_y
        cmp zp_mouse_y
        beq ?done
?moved
        lda zp_mouse_prev_y
        ldx zp_mouse_prev_x
        jsr mouse_restore_char

        lda zp_mouse_y
        ldx zp_mouse_x
        jsr mouse_invert_char

        lda zp_mouse_x
        sta zp_mouse_prev_x
        lda zp_mouse_y
        sta zp_mouse_prev_y
?done   rts
.endp

; ----------------------------------------------------------------------------
; mouse_hide_cursor - Remove cursor before screen updates
; ----------------------------------------------------------------------------
.proc mouse_hide_cursor
        lda zp_mouse_prev_y
        ldx zp_mouse_prev_x
        jsr mouse_restore_char
        rts
.endp

; ----------------------------------------------------------------------------
; mouse_invert_char - Show cursor at A=row, X=col
; Uses vbxe_read_vram/vbxe_write_vram (below $4000) for VRAM access.
; ----------------------------------------------------------------------------
.proc mouse_invert_char
        jsr mouse_calc_vram    ; zp_tmp_ptr set, Y = col*2
        sty mouse_col_off

        ; Read char
        ldy mouse_col_off
        jsr vbxe_read_vram
        sta mouse_saved_char

        ; Write inverted char
        lda mouse_saved_char
        ora #$80
        ldy mouse_col_off
        jsr vbxe_write_vram

        ; Read attr
        ldy mouse_col_off
        iny
        jsr vbxe_read_vram
        sta mouse_saved_attr

        ; Write red attr
        lda #COL_RED
        ldy mouse_col_off
        iny
        jsr vbxe_write_vram
        rts
.endp

; ----------------------------------------------------------------------------
; mouse_restore_char - Restore char+attr at A=row, X=col
; ----------------------------------------------------------------------------
.proc mouse_restore_char
        jsr mouse_calc_vram
        sty mouse_col_off

        ; Write saved char
        lda mouse_saved_char
        ldy mouse_col_off
        jsr vbxe_write_vram

        ; Write saved attr
        lda mouse_saved_attr
        ldy mouse_col_off
        iny
        jsr vbxe_write_vram
        rts
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
        txa
        asl
        sta ?col2
        lda row_addr_lo,y      ; from vbxe_text.asm (below $4000)
        sta zp_tmp_ptr
        lda row_addr_hi,y
        sta zp_tmp_ptr+1
        ldy ?col2
        rts

?col2   dta 0
.endp

; ----------------------------------------------------------------------------
; mouse_check_link - Is cursor over a link? Find link number.
; Uses vbxe_read_vram for all VRAM access (safe from above $4000).
; Output: C=0 A=link#, C=1 not on link
; ----------------------------------------------------------------------------
.proc mouse_check_link
        lda zp_mouse_y
        ldx zp_mouse_x
        jsr mouse_calc_vram
        iny                    ; attr byte
        sty mouse_col_off

        ; Read attr at cursor
        jsr vbxe_read_vram
        cmp #ATTR_LINK
        bne ?no

        ; Scan backward for '['
        ldy mouse_col_off
        dey                    ; back to char byte
?scan   cpy #0
        beq ?no
        dey
        dey
        sty mouse_col_off
        jsr vbxe_read_vram
        cmp #'['
        bne ?scan

        ; Found '[' - read first digit
        ldy mouse_col_off
        iny
        iny
        sty mouse_col_off
        jsr vbxe_read_vram
        cmp #'0'
        bcc ?no
        cmp #'9'+1
        bcs ?no
        sec
        sbc #'0'
        sta ?num

        ; Read next char - ']' or second digit
        ldy mouse_col_off
        iny
        iny
        sty mouse_col_off
        jsr vbxe_read_vram
        cmp #']'
        beq ?got
        cmp #'0'
        bcc ?no
        cmp #'9'+1
        bcs ?no
        sec
        sbc #'0'
        sta ?d2
        ; num = num*10 + d2
        lda ?num
        asl
        sta ?t
        asl
        asl
        clc
        adc ?t
        clc
        adc ?d2
        sta ?num

?got    lda ?num
        clc
        rts

?no     sec
        rts

?num    dta 0
?d2     dta 0
?t      dta 0
.endp
