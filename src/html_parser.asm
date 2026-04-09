; ============================================================================
; HTML Parser Module - Streamovy byte-by-byte parser
; Tag handlers in html_tags.asm, entity decode in html_entities.asm
; ============================================================================

; Parser states
PS_NORMAL      = 0
PS_IN_TAG      = 1
PS_IN_ENTITY   = 2
PS_IN_ATTRNAME = 3
PS_IN_ATTRVAL  = 4
PS_SKIP_TAG    = 5
PS_IN_COMMENT  = 6

; Tag IDs
TAG_UNKNOWN    = 0
TAG_H1         = 1
TAG_H2         = 2
TAG_H3         = 3
TAG_P          = 4
TAG_BR         = 5
TAG_A          = 6
TAG_UL         = 7
TAG_OL         = 8
TAG_LI         = 9
TAG_B          = 10
TAG_STRONG     = 11
TAG_I          = 12
TAG_EM         = 13
TAG_TITLE      = 14
TAG_SCRIPT     = 15
TAG_STYLE      = 16
TAG_IMG        = 17
TAG_INPUT      = 18
TAG_FORM       = 19
TAG_DIV        = 20
TAG_SPAN       = 21
TAG_PRE        = 22
TAG_HR         = 23
TAG_NOSCRIPT   = 24
TAG_TABLE      = 25
TAG_TR         = 26
TAG_TD         = 27
TAG_TH         = 28
TAG_BLOCKQUOTE = 29
TAG_DT         = 30
TAG_DD         = 31
TAG_CODE       = 32
TAG_HEAD       = 33
TAG_BODY       = 34
TAG_H4         = 35
TAG_H5         = 36
TAG_H6         = 37
TAG_U          = 38
TAG_SUP        = 39
TAG_SUB        = 40
TAG_NAV        = 41
TAG_ARTICLE    = 42
TAG_SECTION    = 43
TAG_ASIDE      = 44
TAG_HEADER     = 45
TAG_FOOTER     = 46
TAG_MAIN       = 47

TAG_BUF_SIZE   = 16
ATTR_BUF_SIZE  = 16
VAL_BUF_SIZE   = 256
ENTITY_BUF_SZ  = 8

.proc html_reset
        lda #PS_NORMAL
        sta zp_parse_state
        lda #0
        sta zp_tag_idx
        sta zp_attr_idx
        sta zp_val_idx
        sta zp_entity_idx
        sta zp_in_skip
        sta is_closing
        sta in_title
        sta in_pre
        sta img_src_len
        sta utf8_skip
        sta utf8_lead
        sta td_count
        sta zp_link_num
        sta ansi_state
        sta ansi_bold
        lda #1
        sta zp_in_head         ; start in head-skip mode
        rts
.endp

; ============================================================================
; html_process_chunk - main parser loop
; Split into small sub-procs to avoid branch-out-of-range
; ============================================================================
chunk_idx  dta 0              ; current position in rx_buffer (0..zp_rx_len-1)
in_quotes  dta 0              ; inside quoted attr value: holds quote char (" or ')

.proc html_process_chunk
        lda #0
        sta chunk_idx
.endp
        ; fall through to parse_loop_re

parse_loop_re
        lda page_abort
        bne parse_chunk_done   ; user pressed Q - stop processing
        ldy chunk_idx
        cpy zp_rx_len
        beq parse_chunk_done
        inc chunk_idx
        ; Fast path: PS_NORMAL (state 0) is most common (~65% of bytes)
        ldx zp_parse_state
        bne ?dispatch
        lda rx_buffer,y
        jmp parse_normal
?dispatch
        ; Table dispatch for states 1-6
        lda state_tbl_hi,x
        sta zp_tmp_ptr+1
        lda state_tbl_lo,x
        sta zp_tmp_ptr
        lda rx_buffer,y
        jmp (zp_tmp_ptr)

parse_chunk_done
        rts

state_tbl_lo
        dta <parse_normal      ; 0 PS_NORMAL
        dta <parse_tag         ; 1 PS_IN_TAG
        dta <parse_entity      ; 2 PS_IN_ENTITY
        dta <parse_attrname    ; 3 PS_IN_ATTRNAME
        dta <parse_attrval     ; 4 PS_IN_ATTRVAL
        dta <parse_skipmode    ; 5 PS_SKIP_TAG
        dta <parse_comment     ; 6 PS_IN_COMMENT
state_tbl_hi
        dta >parse_normal
        dta >parse_tag
        dta >parse_entity
        dta >parse_attrname
        dta >parse_attrval
        dta >parse_skipmode
        dta >parse_comment

; --- Normal text ---
.proc parse_normal
        cmp #'<'
        beq ?start_tag
        cmp #'&'
        beq ?start_ent

        ; UTF-8 transliteration: convert accented chars to ASCII equivalents
        ; 2-byte ($C0-$DF lead + 1 cont), 3-byte ($E0-$EF + 2), 4-byte ($F0+)
        ldx utf8_skip
        bne ?utf8_cont
        cmp #$C0               ; 2-byte UTF-8 lead (C0-DF)?
        bcc ?ascii
        cmp #$E0               ; 3-byte UTF-8 lead (E0-EF)?
        bcc ?utf2
        cmp #$F0               ; 4-byte UTF-8 lead (F0-F7)?
        bcc ?utf3
        ; >= F0: 4-byte lead, skip 3 continuation bytes
        lda #3
        sta utf8_skip
        lda #0
        sta utf8_lead
        jmp parse_loop_re
?utf2   ; 2-byte UTF-8 lead - save for transliteration lookup
        sta utf8_lead
        lda #1
        sta utf8_skip
        jmp parse_loop_re
?utf3   lda #2
        sta utf8_skip
        lda #0
        sta utf8_lead           ; no transliteration for 3-byte sequences
        jmp parse_loop_re
?utf8_cont
        dec utf8_skip
        bne ?utf8_jlp           ; more continuation bytes to skip
        ; Last continuation byte — try transliteration
        ldx utf8_lead
        beq ?utf8_jlp           ; no lead saved (3/4-byte), skip
        jsr utf8_xlat           ; A=cont byte, X=lead → A=ascii or 0
        beq ?utf8_jlp           ; 0 = no mapping, skip
        jmp ?ascii              ; emit transliterated char
?utf8_jlp
        jmp parse_loop_re

?ascii  ldx zp_in_skip
        bne ?skip
        jsr html_emit_char
?skip   jmp parse_loop_re

?start_tag
        lda #PS_IN_TAG
        sta zp_parse_state
        lda #0
        sta zp_tag_idx
        sta zp_attr_idx
        sta zp_val_idx
        sta is_closing
        sta img_src_len
        jmp parse_loop_re

?start_ent
        lda #PS_IN_ENTITY
        sta zp_parse_state
        lda #0
        sta zp_entity_idx
        jmp parse_loop_re
.endp

; --- Inside tag name ---
.proc parse_tag
        ldx zp_tag_idx
        bne ?nf
        cmp #'/'
        bne ?nf
        lda #1
        sta is_closing
        jmp parse_loop_re

?nf     cmp #'>'
        beq ?end
        cmp #CH_SPACE
        beq ?2attr
        cmp #10
        beq ?2attr
        cmp #13
        beq ?2attr

        jsr to_lower
        ldx zp_tag_idx
        cpx #TAG_BUF_SIZE-1
        bcs ?jlp
        sta tag_name_buf,x
        inc zp_tag_idx
        ; Detect comment start: "!--" (3 chars collected)
        lda zp_tag_idx
        cmp #3
        bne ?jlp
        lda tag_name_buf
        cmp #'!'
        bne ?jlp
        lda tag_name_buf+1
        cmp #'-'
        bne ?jlp
        lda tag_name_buf+2
        cmp #'-'
        bne ?jlp
        ; HTML comment detected - switch to comment mode
        lda #PS_IN_COMMENT
        sta zp_parse_state
        lda #0
        sta comment_dashes
?jlp    jmp parse_loop_re

?2attr  ldx zp_tag_idx
        lda #0
        sta tag_name_buf,x
        lda #PS_IN_ATTRNAME
        sta zp_parse_state
        lda #0
        sta zp_attr_idx
        jmp parse_loop_re

?end    ldx zp_tag_idx
        lda #0
        sta tag_name_buf,x
        jsr process_tag
        lda #PS_NORMAL
        sta zp_parse_state
        jmp parse_loop_re
.endp

; --- Attribute name ---
.proc parse_attrname
        cmp #'>'
        beq ?end_tag
        cmp #'='
        beq ?2val
        cmp #CH_SPACE
        beq ?jlp
        cmp #10
        beq ?jlp
        cmp #13
        beq ?jlp

        jsr to_lower
        ldx zp_attr_idx
        cpx #ATTR_BUF_SIZE-1
        bcs ?jlp
        sta attr_name_buf,x
        inc zp_attr_idx
?jlp    jmp parse_loop_re

?2val   ldx zp_attr_idx
        lda #0
        sta attr_name_buf,x
        lda #PS_IN_ATTRVAL
        sta zp_parse_state
        lda #0
        sta zp_val_idx
        sta in_quotes
        jmp parse_loop_re

?end_tag
        ldx zp_attr_idx
        lda #0
        sta attr_name_buf,x
        jsr process_tag
        lda #PS_NORMAL
        sta zp_parse_state
        jmp parse_loop_re
.endp

; --- Attribute value ---
.proc parse_attrval
        ldx in_quotes
        bne ?inq

        cmp #'"'
        beq ?stq
        cmp #$27
        beq ?stq
        cmp #'>'
        beq ?evtag
        cmp #CH_SPACE
        beq ?endv

        ldx zp_val_idx
        cpx #VAL_BUF_SIZE-1
        bcs ?jlp
        sta attr_val_buf,x
        inc zp_val_idx
?jlp    jmp parse_loop_re

?stq    sta in_quotes
        jmp parse_loop_re

?inq    cmp in_quotes
        beq ?endv
        ldx zp_val_idx
        cpx #VAL_BUF_SIZE-1
        bcs ?jlp
        sta attr_val_buf,x
        inc zp_val_idx
        jmp parse_loop_re

?endv   ldx zp_val_idx
        lda #0
        sta attr_val_buf,x
        jsr process_attr
        lda #PS_IN_ATTRNAME
        sta zp_parse_state
        lda #0
        sta zp_attr_idx
        sta in_quotes
        jmp parse_loop_re

?evtag  ldx zp_val_idx
        lda #0
        sta attr_val_buf,x
        jsr process_attr
        jsr process_tag
        lda #PS_NORMAL
        sta zp_parse_state
        jmp parse_loop_re
.endp

; --- Skip mode (script/style) - fast scan for '<' ---
.proc parse_skipmode
        ; A already has current byte from parse_loop_re
        cmp #'<'
        beq ?found
        ; Fast scan: skip remaining bytes until '<' (tight loop)
        ldy chunk_idx
?scan   cpy zp_rx_len
        beq ?done              ; end of chunk, exit
        lda rx_buffer,y
        iny
        cmp #'<'
        bne ?scan              ; ~10 cycles per byte vs ~40 in main loop
        sty chunk_idx
?found  lda #PS_IN_TAG
        sta zp_parse_state
        lda #0
        sta zp_tag_idx
        sta is_closing
?done   jmp parse_loop_re
.endp

; --- HTML comment mode (<!-- ... -->) ---
.proc parse_comment
        cmp #'-'
        bne ?not_dash
        inc comment_dashes
        jmp parse_loop_re
?not_dash
        cmp #'>'
        bne ?reset
        ; Check if we had -- before >
        lda comment_dashes
        cmp #2
        bcs ?end_comment
?reset  lda #0
        sta comment_dashes
        jmp parse_loop_re
?end_comment
        lda #PS_NORMAL
        sta zp_parse_state
        jmp parse_loop_re
.endp

comment_dashes dta 0          ; consecutive '-' count before '>' (need 2+ for -->)

; --- Entity ---
.proc parse_entity
        cmp #';'
        beq ?end_ent
        cmp #CH_SPACE
        beq ?abort
        cmp #'<'
        beq ?abort_tag

        ldx zp_entity_idx
        cpx #ENTITY_BUF_SZ-1
        bcs ?jlp
        sta entity_buf,x
        inc zp_entity_idx
?jlp    jmp parse_loop_re

?end_ent
        ldx zp_entity_idx
        lda #0
        sta entity_buf,x
        jsr decode_entity
        jsr html_emit_char
        lda #PS_NORMAL
        sta zp_parse_state
        jmp parse_loop_re

?abort  lda #'&'
        jsr html_emit_char
        jsr emit_entity_buf
        lda #PS_NORMAL
        sta zp_parse_state
        jmp parse_loop_re

?abort_tag
        lda #'&'
        jsr html_emit_char
        jsr emit_entity_buf
        lda #PS_IN_TAG
        sta zp_parse_state
        lda #0
        sta zp_tag_idx
        sta is_closing
        jmp parse_loop_re
.endp

; ============================================================================
; html_flush / html_emit_char
; ============================================================================
html_flush = render_flush_word

.proc html_emit_char
        ldx zp_in_skip
        bne ?skip
        ldx zp_in_head
        bne ?head_chk
        ldx skip_to_heading
        bne ?skip
        ldx skip_to_frag
        bne ?skip

        ; ANSI escape sequence handling
        ; Detects ESC[$1B] and routes to CSI parser for SGR color codes
        ; Works in both normal text and <pre> blocks
        ldx ansi_state
        bne ?ansi_cont         ; already inside ESC sequence
        cmp #$1B               ; ESC character? start new sequence
        beq ?ansi_start

?emit   ldx in_pre
        bne ?pre_ch
        cmp #13
        beq ?ws
        cmp #10
        beq ?ws
        cmp #9
        beq ?ws
        jmp render_char
?ws     lda #CH_SPACE
        jmp render_char
?skip   rts
?pre_ch cmp #10
        beq ?pre_nl
        cmp #13
        beq ?skip              ; CR in pre → skip
        jmp render_out_char    ; direct output, preserve spaces
?pre_nl jmp render_do_nl
?head_chk
        ; In <head> - only emit if inside <title>
        ldx in_title
        bne ?emit
        rts

?ansi_start
        lda #1
        sta ansi_state
        rts                    ; consume ESC, don't emit

?ansi_cont
        jmp ansi_process       ; handle ANSI continuation byte
.endp

; ============================================================================
; to_lower - Convert A to lowercase if uppercase
; ============================================================================
.proc to_lower
        cmp #'A'
        bcc ?ok
        cmp #'Z'+1
        bcs ?ok
        ora #$20
?ok     rts
.endp

; --- Parser state variables ---
is_closing     dta 0          ; 1 = closing tag (</...>), set when '/' seen at tag start
in_title       dta 0          ; 1 = inside <title>: chars go to title_buf via render_char
in_pre         dta 0          ; 1 = inside <pre>: bypass word wrap, only LF=newline, CR skipped
utf8_skip      dta 0          ; bytes remaining in multi-byte UTF-8 sequence
utf8_lead      dta 0          ; saved lead byte for 2-byte UTF-8 transliteration
td_count       dta 0          ; table cell counter per <tr> row (reset at open_tr)
zp_in_head     dta 0          ; 1 = inside <head>: skip all content except <title>

; Fragment anchor support
FRAG_BUF_SZ    = 32
skip_to_frag   dta 0          ; 1 = suppress output until matching id/name found
frag_buf       .ds FRAG_BUF_SZ ; fragment text (from URL #anchor)

; ============================================================================
; UTF-8 to ASCII Transliteration
; Input: A = continuation byte ($80-$BF), X = lead byte (C3/C4/C5)
; Output: A = ASCII char, or 0 = no mapping (Z flag set)
; ============================================================================
.proc utf8_xlat
        and #$3F               ; index 0-63
        tay
        cpx #$C3
        beq ?c3
        cpx #$C4
        beq ?c4
        cpx #$C5
        beq ?c5
        lda #0                 ; unknown lead byte
        rts
?c3     lda utf8_c3,y
        rts
?c4     lda utf8_c4,y
        rts
?c5     lda utf8_c5,y
        rts
.endp

; C3: U+00C0-U+00FF (Latin-1 Supplement: À-ÿ)
utf8_c3
        dta c'AAAAAAAC'        ; $80-$87: À Á Â Ã Ä Å Æ Ç
        dta c'EEEEIIII'        ; $88-$8F: È É Ê Ë Ì Í Î Ï
        dta c'DNOOOO'          ; $90-$95: Ð Ñ Ò Ó Ô Õ
        dta c'O'               ; $96: Ö
        dta b(0)               ; $97: × (skip)
        dta c'OUUUUYTS'        ; $98-$9F: Ø Ù Ú Û Ü Ý Þ ß→s
        dta c'aaaaaaac'        ; $A0-$A7: à á â ã ä å æ ç
        dta c'eeeeiiiidn'      ; $A8-$B1: è-ë ì-ï ð ñ
        dta c'ooooo'           ; $B2-$B6: ò ó ô õ ö
        dta b(0)               ; $B7: ÷ (skip)
        dta c'ouuuuyty'        ; $B8-$BF: ø ù ú û ü ý þ ÿ

; C4: U+0100-U+013F (Latin Extended-A, part 1)
utf8_c4
        dta c'AaAaAaCcCcCcCcDd' ; $80-$8F: Ā-ď
        dta c'DdEeEeEeEeEeGgGg' ; $90-$9F: Đ-ğ
        dta c'GgGgHhHhIiIiIiIi' ; $A0-$AF: Ġ-į
        dta c'IiIiJjKkkLlLlLlL'  ; $B0-$BF: İ-Ŀ

; C5: U+0140-U+017F (Latin Extended-A, part 2)
utf8_c5
        dta c'lLlNnNnNnnNnOoOo' ; $80-$8F: ŀ-ŏ
        dta c'OoOoRrRrRrSsSsSs' ; $90-$9F: Ő-ş
        dta c'SsTtTtTtUuUuUuUu' ; $A0-$AF: Š-ů
        dta c'UuUuWwYyYZzZzZzs' ; $B0-$BF: Ű-ſ

; ============================================================================
; ANSI SGR Escape Sequence Handler
; Supports: ESC[0m (reset), ESC[1m (bold/bright), ESC[22m (normal),
;           ESC[30-37m (FG), ESC[90-97m (bright FG), ESC[param;...m
; ============================================================================

; --- ANSI state ---
ansi_state  dta 0              ; 0=normal, 1=got ESC, 2=in CSI params
ansi_param  dta 0              ; current parameter value being accumulated
ansi_bold   dta 0              ; 1=bold (bright) mode active

; ---------------------------------------------------------------------------
; ansi_process - Handle one byte of ANSI escape sequence
; Called from html_emit_char when ansi_state > 0
; ANSI CSI format: ESC [ param1 ; param2 ; ... command_char
; We only handle 'm' (SGR = Set Graphics Rendition)
; Input: A = current byte
; ---------------------------------------------------------------------------
.proc ansi_process
        ldx ansi_state
        cpx #1
        beq ?expect_bracket    ; state 1: ESC received, expect '['
        ; state 2: inside CSI, collecting parameter digits

        ; Digit 0-9: accumulate into current parameter
        cmp #'0'
        bcc ?cmd
        cmp #'9'+1
        bcs ?cmd
        ; param = param * 10 + (char - '0')
        ; Multiply by 10 using shifts: x*10 = x*8 + x*2
        sec
        sbc #'0'
        pha
        lda ansi_param
        asl                    ; *2
        sta ?tmp
        asl                    ; *4
        asl                    ; *8
        clc
        adc ?tmp               ; + *2 = *10
        sta ansi_param
        pla
        clc
        adc ansi_param         ; + new digit
        sta ansi_param
        rts

?cmd    ; Non-digit: check for separator or command
        cmp #';'
        beq ?separator         ; ';' separates params (e.g. ESC[1;31m)
        cmp #'m'
        beq ?sgr_end           ; 'm' = SGR command, apply and finish
        ; Unknown command letter (H, J, K, etc.) - not supported, abort
        lda #0
        sta ansi_state
        rts

?expect_bracket
        cmp #'['               ; CSI introducer
        bne ?abort
        lda #2                 ; enter parameter collection state
        sta ansi_state
        lda #0
        sta ansi_param         ; reset first parameter
        rts

?abort  lda #0                 ; not CSI, abort sequence
        sta ansi_state
        rts

?separator
        jsr ansi_apply_sgr     ; apply current param
        lda #0
        sta ansi_param         ; reset for next param
        rts

?sgr_end
        jsr ansi_apply_sgr     ; apply last param
        lda #0
        sta ansi_state         ; sequence complete
        rts

?tmp    dta 0
.endp

; ---------------------------------------------------------------------------
; ansi_apply_sgr - Apply single SGR (Set Graphics Rendition) parameter
; Maps ANSI color codes to VBXE palette indices $10-$1F (CGA colors)
; Palette layout: $10-$17 = standard 8 colors, $18-$1F = bright 8 colors
; Supported codes:
;   0       = reset to normal white text
;   1       = bold (selects bright color variant)
;   22      = normal intensity (deselects bold)
;   30-37   = standard foreground: blk,red,grn,yel,blu,mag,cyn,wht
;   90-97   = bright foreground (same order)
; Input: ansi_param = SGR code, ansi_bold = bold flag
; ---------------------------------------------------------------------------
.proc ansi_apply_sgr
        lda ansi_param
        beq ?reset             ; 0 = reset all attributes
        cmp #1
        beq ?bold              ; 1 = bold/bright
        cmp #22
        beq ?unbold            ; 22 = normal intensity
        ; Standard foreground 30-37
        cmp #30
        bcc ?done
        cmp #38
        bcc ?fg_std
        ; 40-47: background colors (not supported - single attr byte)
        ; Bright foreground 90-97
        cmp #90
        bcc ?done
        cmp #98
        bcc ?fg_bright
?done   rts

?reset  lda #0
        sta ansi_bold
        lda #ATTR_NORMAL
        jmp render_set_attr

?bold   lda #1
        sta ansi_bold
        rts

?unbold lda #0
        sta ansi_bold
        rts

?fg_std sec
        sbc #30                ; ANSI code 30-37 → index 0-7
        clc
        adc #ATTR_ANSI_BASE    ; → palette $10-$17
        ldx ansi_bold
        beq ?set
        clc
        adc #8                 ; bold → bright variant $18-$1F
?set    jmp render_set_attr

?fg_bright
        sec
        sbc #90                ; ANSI code 90-97 → index 0-7
        clc
        adc #ATTR_ANSI_BASE+8  ; → bright palette $18-$1F
        jmp render_set_attr
.endp

; Buffers
tag_name_buf   .ds TAG_BUF_SIZE
attr_name_buf  .ds ATTR_BUF_SIZE
attr_val_buf   .ds VAL_BUF_SIZE
entity_buf     .ds ENTITY_BUF_SZ
