; ============================================================================
; Title Screen - Welcome / about screen with GMON gradient banner
; ============================================================================

.proc show_welcome
        jsr vbxe_cls
        jsr title_gfx_init

        ; === Title (row 1, centered) ===
        lda #1
        ldx #34
        jsr vbxe_setpos
        lda #ATTR_H1
        jsr vbxe_setattr
        lda #<tw_title
        ldx #>tw_title
        jsr vbxe_print

        ; === Version (row 3, centered) ===
        lda #3
        ldx #msg_welcome_col
        jsr vbxe_setpos
        lda #ATTR_NORMAL
        jsr vbxe_setattr
        lda #<msg_welcome
        ldx #>msg_welcome
        jsr vbxe_print

        ; === Subtitle (row 5, centered) ===
        lda #5
        ldx #23
        jsr vbxe_setpos
        lda #ATTR_NORMAL
        jsr vbxe_setattr
        lda #<tw_subtitle
        ldx #>tw_subtitle
        jsr vbxe_print

        ; === Separator (row 7) ===
        lda #7
        ldx #0
        jsr vbxe_setpos
        lda #ATTR_H2
        jsr vbxe_setattr
        ldx #SCR_COLS
?fl1    stx zp_tmp2
        lda #$A0               ; inverse space = solid block
        jsr vbxe_putchar
        ldx zp_tmp2
        dex
        bne ?fl1

        ; === Requirements (row 9, centered) ===
        lda #9
        ldx #17
        jsr vbxe_setpos
        lda #ATTR_DECOR
        jsr vbxe_setattr
        lda #<tw_req
        ldx #>tw_req
        jsr vbxe_print

        ; === Controls header (row 11) ===
        lda #11
        ldx #4
        jsr vbxe_setpos
        lda #ATTR_H2
        jsr vbxe_setattr
        lda #<tw_ctrl_hdr
        ldx #>tw_ctrl_hdr
        jsr vbxe_print

        ; === Control lines (rows 12-15) ===
        lda #12
        ldx #6
        jsr vbxe_setpos
        lda #ATTR_NORMAL
        jsr vbxe_setattr
        lda #<tw_ctrl1
        ldx #>tw_ctrl1
        jsr vbxe_print

        lda #13
        ldx #6
        jsr vbxe_setpos
        lda #<tw_ctrl2
        ldx #>tw_ctrl2
        jsr vbxe_print

        lda #14
        ldx #6
        jsr vbxe_setpos
        lda #<tw_ctrl3
        ldx #>tw_ctrl3
        jsr vbxe_print

        lda #15
        ldx #6
        jsr vbxe_setpos
        lda #<tw_ctrl4
        ldx #>tw_ctrl4
        jsr vbxe_print

        ; === Search hint (row 17) ===
        lda #17
        ldx #6
        jsr vbxe_setpos
        lda #ATTR_DECOR
        jsr vbxe_setattr
        lda #<tw_search
        ldx #>tw_search
        jsr vbxe_print

        ; === Separator (row 18) ===
        lda #18
        ldx #0
        jsr vbxe_setpos
        lda #ATTR_DECOR
        jsr vbxe_setattr
        ldx #SCR_COLS
?fl2    stx zp_tmp2
        lda #$A0               ; inverse space = solid block
        jsr vbxe_putchar
        ldx zp_tmp2
        dex
        bne ?fl2

        ; === Proxy status (row 20) ===
        lda #20
        ldx #25
        jsr vbxe_setpos
        lda use_proxy
        beq ?poff
        lda #COL_GREEN
        jsr vbxe_setattr
        lda #<tw_pon
        ldx #>tw_pon
        jmp ?pshow
?poff   lda #ATTR_DECOR
        jsr vbxe_setattr
        lda #<tw_poff
        ldx #>tw_poff
?pshow  jsr vbxe_print

        ; === Press U prompt (row 22, centered) ===
        lda #22
        ldx #27
        jsr vbxe_setpos
        lda #ATTR_LINK
        jsr vbxe_setattr
        lda #<tw_press_u
        ldx #>tw_press_u
        jsr vbxe_print

        ; === Author (row 24, centered) ===
        lda #24
        ldx #18
        jsr vbxe_setpos
        lda #ATTR_DECOR
        jsr vbxe_setattr
        lda #<msg_author
        ldx #>msg_author
        jsr vbxe_print

        lda #ATTR_NORMAL
        jmp vbxe_setattr
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
tw_search   dta c'Type any words to search (e.g. ATARI 800XL)',0
tw_press_u  dta c'Press U to start browsing.',0
tw_pon      dta c'Proxy: ON  (P to toggle)',0
tw_poff     dta c'Proxy: OFF (P to toggle)',0
