; ============================================================================
; Cactus - Web Browser for Atari XE/XL
; Requires: VBXE + FujiNet
; Assembler: MADS
; Build: mads cactus.asm -o:cactus.xex
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
        cld                    ; decimal mode is not reset by the OS
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
        jsr memac_patch        ; MEMAC B stores -> the detected register page

        jsr vbxe_init
        cli

        jsr kbd_init
        jsr mouse_init
        jsr history_init
 .if 1                          ; 2026-09-23 (settings saved on disk)
        jsr bk_load
        jsr set_load           ; proxy on/off from D1: sector 715
 .else
        jsr bk_load
 .endif
        lda #0
        sta cur_page_url       ; no page loaded yet (buffer is uninitialized)
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
        stx ICBLH            ; X = 0
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
        icl 'find.asm'
        icl 'vbxe_gfx.asm'
        ; --- everything below this line is above $4000 (no MEMAC B code) ---
        icl 'bookmarks.asm'    ; no memb_on/off — VRAM via vbxe_* helpers
        icl 'fujinet.asm'
        icl 'http.asm'
        icl 'url.asm'
        icl 'vbxe_pal.asm'
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
