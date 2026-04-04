; ============================================================================
; Cactus - Web Browser for Atari XE/XL
; Requires: VBXE + FujiNet
; Assembler: MADS
; Build: mads browser.asm -o:browser.xex
; ============================================================================

        opt h+                 ; Atari XEX header
        opt o+                 ; Optimize branches

        icl 'vbxe_const.asm'

; ============================================================================
; Main program
; ============================================================================
        org $3000

; ============================================================================
; Entry point
; ============================================================================
.proc main
        lda #0
        sta SDMCTL
        sei

        ; PAL/NTSC detection (PAL=$01, NTSC=$0F)
        lda PAL
        cmp #$01
        beq ?pal
        lda #0               ; NTSC
?pal    sta is_pal

        jsr vbxe_detect
        bcc no_vbxe

        jsr vbxe_init
        cli

        jsr kbd_init
        jsr mouse_init
        jsr history_init
        jsr html_reset
        jsr render_reset
        jsr show_welcome
        jsr ui_main_loop
        ; ui_main_loop never returns (Q goes to welcome screen)
        ; To exit browser, user presses Reset on Atari

no_vbxe cli
        lda #$22
        sta SDMCTL
        ; Show error message via E: device (CIO IOCB #0)
        ldx #0               ; IOCB #0 = E: (editor)
        lda #$09             ; PUT RECORD command
        sta ICCOM
        lda #<msg_no_vbxe
        sta ICBAL
        lda #>msg_no_vbxe
        sta ICBAH
        lda #18              ; string length
        sta ICBLL
        lda #0
        sta ICBLH
        jsr CIOV
        ; Wait for keypress then cold start
?wk     lda CH
        cmp #KEY_NONE
        beq ?wk
        jmp (COLDSV)
.endp

is_pal  dta b(1)             ; 1=PAL, 0=NTSC (default PAL)


; show_welcome is in title.asm

; ============================================================================
; Include all modules
; ============================================================================
        icl 'vbxe_detect.asm'
        icl 'vbxe_init.asm'
        icl 'vbxe_text.asm'
        icl 'vbxe_gfx.asm'
        icl 'fujinet.asm'
        icl 'http.asm'
        icl 'url.asm'
        icl 'html_parser.asm'
        icl 'html_tags.asm'
        icl 'html_entities.asm'
        icl 'renderer.asm'
        icl 'keyboard.asm'
        icl 'ui.asm'
        icl 'img_fetch.asm'
        icl 'history.asm'
        icl 'mouse.asm'
        icl 'title.asm'
        icl 'data.asm'

; ============================================================================
; Run address
; ============================================================================
        run main
