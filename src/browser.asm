; ============================================================================
; VBXE Web Browser for Atari XE/XL
; Requires: VBXE + FujiNet or 850 Interface Module
; Assembler: MADS
; Build: mads browser.asm -o:browser.xex
; ============================================================================

        opt h+                 ; Atari XEX header
        opt o+                 ; Optimize branches

        icl 'vbxe_const.asm'

; ============================================================================
; Main program
; 850 R: handler loads automatically during Atari boot via SIO
; ============================================================================
        org $3000

; ============================================================================
; Entry point
; ============================================================================
.proc main
        lda #0
        sta SDMCTL
        sei

        jsr vbxe_detect
        bcc no_vbxe

        jsr vbxe_init
        cli

        jsr kbd_init
        jsr history_init
        jsr html_reset
        jsr render_reset
        jsr ui_init
        jsr show_welcome
        jsr net_init
        jsr ui_init
        jsr show_welcome
        jsr ui_main_loop
        jsr shutdown
        jmp (COLDSV)

no_vbxe cli
        lda #$22
        sta SDMCTL
        ; Can't do much without VBXE, just cold start
        jmp (COLDSV)
.endp

; ----------------------------------------------------------------------------
; show_welcome
; ----------------------------------------------------------------------------
.proc show_welcome
        lda #TITLE_ROW
        ldx #0
        jsr vbxe_setpos
        lda #ATTR_HEADING
        jsr vbxe_setattr
        lda #<msg_welcome
        ldx #>msg_welcome
        jsr vbxe_print

        lda #3
        ldx #0
        jsr vbxe_setpos
        lda #ATTR_NORMAL
        jsr vbxe_setattr
        lda #<msg_welcome2
        ldx #>msg_welcome2
        jsr vbxe_print

        lda #5
        ldx #0
        jsr vbxe_setpos
        lda #ATTR_LINK
        jsr vbxe_setattr
        lda #<msg_press_u
        ldx #>msg_press_u
        jsr vbxe_print

        lda #ATTR_NORMAL
        jsr vbxe_setattr
        rts
.endp

; ----------------------------------------------------------------------------
; shutdown
; ----------------------------------------------------------------------------
.proc shutdown
        jsr net_shutdown
        ldy #VBXE_VCTL
        lda #0
        sta (zp_vbxe_base),y
        memb_off
        lda #$22
        sta SDMCTL
        rts
.endp

; ============================================================================
; Include all modules
; ============================================================================
        icl 'vbxe_detect.asm'
        icl 'vbxe_init.asm'
        icl 'vbxe_text.asm'
        icl 'fujinet.asm'
        icl 'modem850.asm'
        icl 'network.asm'
        icl 'http.asm'
        icl 'html_parser.asm'
        icl 'renderer.asm'
        icl 'keyboard.asm'
        icl 'ui.asm'
        icl 'history.asm'
        icl 'data.asm'

; ============================================================================
; Run address
; ============================================================================
        run main
