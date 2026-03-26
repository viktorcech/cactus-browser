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
        sta td_count
        sta zp_link_num
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

        lda rx_buffer,y
        inc chunk_idx

        ldx zp_parse_state
        beq ?normal
        cpx #PS_IN_TAG
        beq ?tag
        cpx #PS_IN_ENTITY
        beq ?entity
        cpx #PS_IN_ATTRNAME
        bne ?noan
        jmp parse_attrname
?noan   cpx #PS_IN_ATTRVAL
        bne ?noav
        jmp parse_attrval
?noav   cpx #PS_SKIP_TAG
        beq ?skip
        jmp parse_comment
?skip   jmp parse_skipmode

?normal jmp parse_normal
?tag    jmp parse_tag
?entity jmp parse_entity

parse_chunk_done
        rts

; --- Normal text ---
.proc parse_normal
        cmp #'<'
        beq ?start_tag
        cmp #'&'
        beq ?start_ent

        ; UTF-8 filtering: Atari has no UTF-8 font, skip all non-ASCII bytes
        ; 2-byte ($C0-$DF lead + 1 cont), 3-byte ($E0-$EF + 2), 4-byte ($F0+)
        ldx utf8_skip
        bne ?utf8_cont
        cmp #$C0               ; 2-byte UTF-8 lead (C0-DF)?
        bcc ?ascii
        cmp #$E0               ; 3-byte UTF-8 lead (E0-EF)?
        bcc ?utf2
        cmp #$F0               ; 4-byte UTF-8 lead (F0-F7)?
        bcc ?utf3
        jmp parse_loop_re      ; >= F0: skip
?utf2   lda #1
        sta utf8_skip
        jmp parse_loop_re      ; skip lead byte, skip 1 more
?utf3   lda #2
        sta utf8_skip
        jmp parse_loop_re      ; skip lead byte, skip 2 more
?utf8_cont
        dec utf8_skip
        jmp parse_loop_re      ; skip continuation byte

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
.proc html_flush
        jmp render_flush_word
.endp

.proc html_emit_char
        ldx zp_in_skip
        bne ?skip
        ldx zp_in_head
        bne ?head_chk
        ldx skip_to_heading
        bne ?skip
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
utf8_skip      dta 0          ; bytes to skip in multi-byte UTF-8 (no UTF-8 font on Atari)
td_count       dta 0          ; table cell counter per <tr> row (reset at open_tr)
zp_in_head     dta 0          ; 1 = inside <head>: skip all content except <title>

; Buffers
tag_name_buf   .ds TAG_BUF_SIZE
attr_name_buf  .ds ATTR_BUF_SIZE
attr_val_buf   .ds VAL_BUF_SIZE
entity_buf     .ds ENTITY_BUF_SZ
