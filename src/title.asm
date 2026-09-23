; ============================================================================
; Title Screen - Welcome / about screen with GMON gradient banner
; ============================================================================

.proc show_welcome
 .if 1                          ; 2026-09-23 (modern card layout drawn from a table; 6502-loops-tables-smc:
                                ; tables beat code, count down)
        jsr vbxe_cls
        jsr title_gfx_init
        lda zp_vbxe_base+1     ; "$D640" / "$D740": the register page digit
        and #$0F
        ora #'0'
        sta tw_vbxe_pg
        lda #<(welcome_list-1)
        ldx #>(welcome_list-1)
        jsr ui_draw
        lda #1                 ; build stamp, right end of the header
        ldx #51
        jsr vbxe_setpos
        lda #ATTR_DECOR
        sta zp_cur_attr
        lda #<msg_welcome
        ldx #>msg_welcome
        jsr vbxe_print
        lda #5                 ; proxy switch
        ldx #70
        jsr vbxe_setpos
        lda use_proxy
        beq ?poff
        ldy #COL_GREEN
        lda #<tw_on
        ldx #>tw_on
        bne ?pset              ; always (hi byte <> 0)
?poff   ldy #ATTR_DECOR
        lda #<tw_off
        ldx #>tw_off
?pset   sty zp_cur_attr
        jsr vbxe_print
        lda #11                ; video standard
        ldx #50
        jsr vbxe_setpos
        lda #ATTR_NORMAL
        sta zp_cur_attr
        lda #<tw_pal
        ldx #>tw_pal
        ldy is_pal
        bne ?vset
        lda #<tw_ntsc
        ldx #>tw_ntsc
?vset   jsr vbxe_print
        ; first 6 bookmarks on rows 16..21 (count down: slot 5..0)
        ldx #5
?bk     stx ?i
        txa
        clc
        adc #16
        sta ?row
        ldx #2
        jsr vbxe_setpos
        lda #ATTR_H1
        sta zp_cur_attr
        lda ?i                 ; C = 0: vbxe_setpos ends in calc_scr_ptr's
        adc #'1'               ; adc #0 on a screen page < $FF
        jsr vbxe_putchar
        lda ?row
        ldx #6
        jsr vbxe_setpos
        ldx ?i
        lda bk_slot_lo,x
        sta ?slot+1
        lda bk_slot_hi,x
        sta ?slot+2
?slot   lda $FFFF              ; (patched: slot's first byte)
        beq ?empty
        lda #ATTR_LINK
        sta zp_cur_attr
        lda ?slot+1
        ldx ?slot+2            ; slots live at $08xx-$0Axx: X <> 0
        bne ?bprt              ; always
?empty  lda #ATTR_DECOR
        sta zp_cur_attr
        lda #<tw_empty
        ldx #>tw_empty
?bprt   jsr vbxe_print
        ldx ?i
        dex
        bpl ?bk
        lda #ATTR_NORMAL
        sta zp_cur_attr
        rts
?i      dta 0
?row    dta 0
 .else
        jsr vbxe_cls
        jsr title_gfx_init
        lda #1
        ldx #34
        jsr vbxe_setpos
        lda #ATTR_H1
        sta zp_cur_attr
        lda #<tw_title
        ldx #>tw_title
        jsr vbxe_print
        lda #3
        ldx #msg_welcome_col
        jsr vbxe_setpos
        lda #ATTR_NORMAL
        sta zp_cur_attr
        lda #<msg_welcome
        ldx #>msg_welcome
        jsr vbxe_print
        lda #5
        ldx #23
        jsr vbxe_setpos
        lda #ATTR_NORMAL
        sta zp_cur_attr
        lda #<tw_subtitle
        ldx #>tw_subtitle
        jsr vbxe_print
        lda #7
        ldx #0
        jsr vbxe_setpos
        lda #ATTR_H2
        sta zp_cur_attr
        lda #$A0               ; inverse space = solid block
        ldx #SCR_COLS
        jsr vbxe_fill_char
        lda #9
        ldx #17
        jsr vbxe_setpos
        lda #ATTR_DECOR
        sta zp_cur_attr
        lda #<tw_req
        ldx #>tw_req
        jsr vbxe_print
        lda #14
        ldx #20
        jsr vbxe_setpos
        lda #ATTR_H2
        sta zp_cur_attr
        lda #<tw_press_i
        ldx #>tw_press_i
        jsr vbxe_print
        lda #18
        ldx #0
        jsr vbxe_setpos
        lda #ATTR_DECOR
        sta zp_cur_attr
        lda #$A0               ; inverse space = solid block
        ldx #SCR_COLS
        jsr vbxe_fill_char
        lda #20                ; proxy status
        ldx #25
        jsr vbxe_setpos
        lda use_proxy
        beq ?poff
        lda #COL_GREEN
        sta zp_cur_attr
        lda #<tw_pon
        ldx #>tw_pon
        bne ?pshow             ; always (hi byte != 0)
?poff   lda #ATTR_DECOR
        sta zp_cur_attr
        lda #<tw_poff
        ldx #>tw_poff
?pshow  jsr vbxe_print
        lda #22
        ldx #27
        jsr vbxe_setpos
        lda #ATTR_LINK
        sta zp_cur_attr
        lda #<tw_press_u
        ldx #>tw_press_u
        jsr vbxe_print
        lda #24
        ldx #18
        jsr vbxe_setpos
        lda #ATTR_DECOR
        sta zp_cur_attr
        lda #<msg_author
        ldx #>msg_author
        jsr vbxe_print
        lda #ATTR_NORMAL
        sta zp_cur_attr
        rts
 .endif
.endp

; Title screen strings
tw_title    dta c'C A C T U S',0
tw_subtitle dta c'The Internet on your Atari XL/XE!',0
tw_req      dta c'Requires: VBXE + FujiNet + ST Mouse (port 2)',0
tw_ctrl_hdr dta c'Controls:',0
tw_ctrl1    dta c'U - Enter URL              B - Back',0
tw_ctrl2    dta c'H - Skip to heading        Q - Quit page',0
tw_ctrl3    dta c'Space/Return - Next page   Click - follow link',0
tw_ctrl4    dta c'P - Toggle proxy (fast)    IMG links: click to view',0
tw_search   dta c'Tip: press U, type words (e.g. ATARI 800XL) to search',0
tw_press_u  dta c'Press U to start browsing.',0
tw_press_i  dta c'Press I for controls / help',0
tw_pon      dta c'Proxy: ON  (P to toggle)',0
tw_poff     dta c'Proxy: OFF (P to toggle)',0

 .if 1                          ; 2026-09-23 (welcome screen as data: 6502-loops-tables-smc, tables beat code)
; ----------------------------------------------------------------------------
; ui_draw - Draw a screen description (A/X = list - 1):
;   UL_BOX,  row, col, w, h, attr         frame of ATASCII line characters
;   UL_TEXT, row, col, attr, c'...', 0    string
;   UL_FILL, row, col, n, attr, char      n copies of char
;   UL_END
; The list pointer is the SMC operand of ?ld (no zero page pointer).
; ----------------------------------------------------------------------------
UL_END  = 0
UL_BOX  = 1
UL_TEXT = 2
UL_FILL = 3

.proc ui_draw
        sta ?ld+1
        stx ?ld+2
?next   jsr ?get
        bne ?op
        rts                    ; UL_END
?op     cmp #UL_TEXT
        beq ?text
        bcs ?fill
        jsr ?get               ; UL_BOX
        sta ui_box.row
        jsr ?get
        sta ui_box.col
        jsr ?get
        sta ui_box.w
        jsr ?get
        sta ui_box.h
        jsr ?get
        sta zp_cur_attr
        jsr ui_box
        jmp ?next
?text   jsr ?pos
        jsr ?get
        sta zp_cur_attr
        lda ?ld+1              ; the string starts at the next byte
        clc
        adc #1
        sta ?sc+1
        lda ?ld+2
        adc #0
        sta ?sc+2
        ldy #0                 ; its length (< 80): abs,y scan
?sc     lda $FFFF,y
        beq ?se
        iny
        bne ?sc
?se     tya                    ; list pointer -> its NUL: += length + 1
        sec
        adc ?ld+1
        sta ?ld+1
        bcc ?tp
        inc ?ld+2
?tp     jsr blit_sync          ; text may sit on a line just filled
        lda ?sc+1
        ldx ?sc+2
        jsr vbxe_print
        jmp ?next
?fill   jsr ?pos
        jsr ?get
        sta ?n
        jsr ?get
        sta zp_cur_attr
        jsr ?get
        ldx ?n
        jsr vbxe_hline
        jmp ?next

?pos    jsr ?get               ; row, col -> cursor
        pha
        jsr ?get
        tax
        pla
        jmp vbxe_setpos

?get    inc ?ld+1              ; next list byte in A, N/Z from it
        bne ?ld
        inc ?ld+2
?ld     lda $FFFF
        rts
?n      dta 0
.endp

; ui_box - Frame at row/col, w x h (w, h >= 3), attr in zp_cur_attr
.proc ui_box
        lda row
        sta ?r
        ldx col
        jsr vbxe_setpos
        ldx w
        dex
        dex
        stx ?in
        lda #$11               ; top left
        jsr vbxe_putchar
        lda #$12
        ldx ?in
        jsr vbxe_hline
        lda #$05               ; top right
        jsr vbxe_putchar
        lda col                ; right column = col + w - 1:
        clc                    ; col + w <= 80 leaves C = 0, and that
        adc w                  ; clear carry is the -1 of the sbc
        sbc #0
        sta ?rc
        ldx h
        dex
        dex
        stx ?cnt
?side   inc ?r
        lda ?r
        ldx col
        jsr vbxe_setpos
        lda #$7C
        jsr vbxe_putchar
        lda ?r
        ldx ?rc
        jsr vbxe_setpos
        lda #$7C
        jsr vbxe_putchar
        dec ?cnt
        bne ?side
        inc ?r
        lda ?r
        ldx col
        jsr vbxe_setpos
        lda #$1A               ; bottom left
        jsr vbxe_putchar
        lda #$12
        ldx ?in
        jsr vbxe_hline
        lda #$03               ; bottom right
        jmp vbxe_putchar
row     dta 0
col     dta 0
w       dta 0
h       dta 0
?r      dta 0
?rc     dta 0
?in     dta 0
?cnt    dta 0
.endp

welcome_list
        dta UL_BOX, 0, 0, 80, 3, ATTR_DECOR
        dta UL_TEXT, 1, 2, ATTR_H1, c'CACTUS',0
        dta UL_TEXT, 1, 10, ATTR_NORMAL, c'web browser for Atari XL/XE',0

        dta UL_BOX, 4, 0, 40, 6, ATTR_DECOR
        dta UL_TEXT, 4, 2, ATTR_H2, c' Start ',0
        dta UL_TEXT, 5, 2, ATTR_H1, c'U',0
        dta UL_TEXT, 5, 11, ATTR_NORMAL, c'Open a URL or search the web',0
        dta UL_TEXT, 6, 2, ATTR_H1, c'Ctrl+B',0
        dta UL_TEXT, 6, 11, ATTR_NORMAL, c'Bookmarks (10 slots)',0
        dta UL_TEXT, 7, 2, ATTR_H1, c'I',0
        dta UL_TEXT, 7, 11, ATTR_NORMAL, c'All keys and help',0
        dta UL_TEXT, 8, 2, ATTR_DECOR, c'Words without a dot search the web',0

        dta UL_BOX, 4, 40, 40, 6, ATTR_DECOR
        dta UL_TEXT, 4, 42, ATTR_H2, c' Settings ',0
        dta UL_TEXT, 5, 42, ATTR_H1, c'P',0
        dta UL_TEXT, 5, 45, ATTR_NORMAL, c'Proxy',0
        dta UL_TEXT, 6, 45, ATTR_DECOR, c'Lighter, faster pages',0
        dta UL_TEXT, 7, 45, ATTR_DECOR, c'via turiecfoto.sk/cactus',0
        dta UL_TEXT, 8, 42, ATTR_DECOR, c'Saved on disk D1: sector 715',0

        dta UL_BOX, 10, 0, 80, 5, ATTR_DECOR
        dta UL_TEXT, 10, 2, ATTR_H2, c' System ',0
        dta UL_TEXT, 11, 2, ATTR_H1, c'VBXE',0
        dta UL_TEXT, 11, 10, ATTR_NORMAL, c'FX core at $D'
tw_vbxe_pg
        dta c'640',0
        dta UL_TEXT, 11, 42, ATTR_H1, c'Video',0
        dta UL_TEXT, 12, 2, ATTR_H1, c'Mouse',0
  .if MOUSE_PORT2
        dta UL_TEXT, 12, 10, ATTR_NORMAL, c'ST mouse, joystick port 2',0
  .else
        dta UL_TEXT, 12, 10, ATTR_NORMAL, c'ST mouse, joystick port 1',0
  .endif
        dta UL_TEXT, 12, 42, ATTR_H1, c'Network',0
        dta UL_TEXT, 12, 50, ATTR_NORMAL, c'FujiNet N:',0
        dta UL_TEXT, 13, 2, ATTR_H1, c'Disk',0
        dta UL_TEXT, 13, 10, ATTR_NORMAL, c'D1: bookmarks in sectors 716-720, settings in 715',0

        dta UL_BOX, 15, 0, 80, 8, ATTR_DECOR
        dta UL_TEXT, 15, 2, ATTR_H2, c' Bookmarks ',0
        dta UL_TEXT, 15, 60, ATTR_DECOR, c' Ctrl+B: all 10 ',0

        dta UL_TEXT, 23, 17, ATTR_DECOR, c'w1k 2026  github.com/viktorcech/cactus-browser',0
        dta UL_FILL, 25, 0, 80, ATTR_LINK, $A0
        dta UL_TEXT, 25, 1, ATTR_LINK, c' U  Open URL    Ctrl+B  Bookmarks    P  Proxy on/off    I  Help '*,0
        dta UL_END

tw_on    dta c'[  ON ]',0
tw_off   dta c'[ OFF ]',0
tw_pal   dta c'PAL',0
tw_ntsc  dta c'NTSC',0
tw_empty dta c'(empty)',0
 .endif

; ============================================================================
; show_info - Full-screen help/controls popup (triggered by 'I' in main loop)
; ============================================================================
.proc show_info
        jsr vbxe_cls
        lda #1
        ldx #35
        jsr vbxe_setpos
        lda #ATTR_H1
        sta zp_cur_attr
        lda #<in_hdr
        ldx #>in_hdr
        jsr vbxe_print
        lda #3
        ldx #4
        jsr vbxe_setpos
        lda #ATTR_H2
        sta zp_cur_attr
        lda #<in_main_hdr
        ldx #>in_main_hdr
        jsr vbxe_print
        ldx #IN_MAIN_N-1       ; main controls, rows 4..15 (bottom up)
?ml1    stx ?i
        txa
        clc
        adc #4
        ldy in_main_lo,x
        sty ?pl+1
        ldy in_main_hi,x
        sty ?ph+1
        ldx #6
        jsr vbxe_setpos
        lda #ATTR_NORMAL
        sta zp_cur_attr
?pl     lda #0                 ; (patched: text)
?ph     ldx #0
        jsr vbxe_print
        ldx ?i
        dex
        bpl ?ml1
        lda #16
        ldx #6
        jsr vbxe_setpos
        lda #ATTR_DECOR
        sta zp_cur_attr
        lda #<tw_search
        ldx #>tw_search
        jsr vbxe_print
        lda #18
        ldx #4
        jsr vbxe_setpos
        lda #ATTR_H2
        sta zp_cur_attr
        lda #<in_bk_hdr
        ldx #>in_bk_hdr
        jsr vbxe_print
        ldx #IN_BK_N-1         ; bookmark controls, rows 19..25
?bl1    stx ?i
        txa
        clc
        adc #19
        ldy in_bk_lo,x
        sty ?bl+1
        ldy in_bk_hi,x
        sty ?bh+1
        ldx #6
        jsr vbxe_setpos
        lda #ATTR_NORMAL
        sta zp_cur_attr
?bl     lda #0                 ; (patched: text)
?bh     ldx #0
        jsr vbxe_print
        ldx ?i
        dex
        bpl ?bl1
        lda #26
        ldx #25
        jsr vbxe_setpos
        lda #ATTR_LINK
        sta zp_cur_attr
        lda #<in_foot
        ldx #>in_foot
        jsr vbxe_print
        lda #ATTR_NORMAL
        sta zp_cur_attr

        ; Wait for any key (MAG-style CH poll)
?wait   lda RTCLOK+2
?wvs    cmp RTCLOK+2
        beq ?wvs
        lda CH
        cmp #$FF
        beq ?wait
        lda #$FF
        sta CH
        rts
?i      dta 0
.endp

IN_MAIN_N = 12
in_main_hdr dta c'Browser',0
in_main_lo  dta <in_m1,<in_m2,<in_m3,<in_m4,<in_m5,<in_m6,<in_m7,<in_m8,<in_m9,<in_m10,<in_m11,<in_m12
in_main_hi  dta >in_m1,>in_m2,>in_m3,>in_m4,>in_m5,>in_m6,>in_m7,>in_m8,>in_m9,>in_m10,>in_m11,>in_m12
in_m1   dta c'U             Enter URL, or search words (no dot)',0
in_m2   dta c'B             Back (history)',0
in_m3   dta c'Q             Quit to welcome screen',0
in_m4   dta c'P             Toggle proxy (fast rendering)',0
 .if 1                          ; 2026-09-23 (H jumps to the page content)
in_m5   dta c'H             Jump to the content (next heading)',0
 .else
in_m5   dta c'H             Skip to next heading on page',0
 .endif
in_m6   dta c'Ctrl+B        Open bookmarks window',0
in_m7   dta c'F (Ctrl+F)   Find text on page',0
in_m8   dta c'I             This help screen',0
in_m9   dta c'TAB           Highlight next link',0
in_m10  dta c'RETURN        Follow highlighted link / next page',0
in_m11  dta c'SPACE         Next page (during --More--)',0
in_m12  dta c'Click         Follow link under mouse cursor',0

IN_BK_N = 7
in_bk_hdr dta c'Bookmarks window',0
in_bk_lo  dta <in_b1,<in_b2,<in_b3,<in_b4,<in_b5,<in_b6,<in_b7
in_bk_hi  dta >in_b1,>in_b2,>in_b3,>in_b4,>in_b5,>in_b6,>in_b7
in_b1   dta c'Joy / - =     Move cursor',0
in_b2   dta c'RETURN        Open URL / edit empty slot',0
in_b3   dta c'1-9, 0        Open slot directly',0
in_b4   dta c'E             Edit selected slot',0
in_b5   dta c'A             Add current page URL',0
in_b6   dta c'D             Delete selected slot',0
in_b7   dta c'ESC           Close window',0

in_hdr  dta c'Controls',0
in_foot dta c'Press any key to close',0
