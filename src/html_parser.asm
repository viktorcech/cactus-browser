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
        lda #0                 ; PS_NORMAL = 0
        sta zp_parse_state
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
        jmp update_emit_skip
.endp

; The parse loop and the text path share one page: none of their hot taken
; branches pays the page-crossing cycle (checked by skill_scan --layout)
        .align $100
; ============================================================================
; html_process_chunk - main parser loop over rx_buffer[0..zp_rx_len-1]
; A '<' sentinel at rx_buffer[zp_rx_len] ends the text and skip scans
; without a length test per byte. A page abort (render_do_nl) cuts
; zp_rx_len to chunk_idx, so the loop needs no per-byte abort test.
; ============================================================================
.proc html_process_chunk
        jsr parse_sentinel
        ldy #0
.endp
        ; fall through with Y = 0

parse_loop_y                   ; Y = index of the next byte
        sty chunk_idx
parse_loop_re
        ldy chunk_idx
        cpy zp_rx_len
        beq parse_chunk_done
        lda rx_buffer,y
        iny
        sty chunk_idx
        ldx zp_parse_state
        beq parse_normal       ; most bytes: text
        tay                    ; keep the byte
        lda state_tbl_lo,x
        sta zp_tmp_ptr
        lda state_tbl_hi,x
        sta zp_tmp_ptr+1
        tya
        jmp (zp_tmp_ptr)

parse_chunk_done
        rts

; parse_sentinel - Put the '<' sentinel after the chunk (rx_buffer[zp_rx_len]);
; also after anything that reused rx_buffer mid-page (image, find)
.proc parse_sentinel
        ldy zp_rx_len
        lda #'<'
        sta rx_buffer,y
        rts
.endp

; Shared exit: reset parse state to PS_NORMAL and resume main loop
reset_parse_and_loop
        lda #0                 ; PS_NORMAL
        sta zp_parse_state
        jmp parse_loop_re

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
; A = byte, chunk_idx = index after it. Plain bytes (char_class 0) outside
; UTF-8 sequences go to the word buffer in a tight run (?run); the rest
; takes the full path below.
.proc parse_normal
        tax
        lda char_class,x
        beq ?plain             ; class 0: word run / skip (below)

        txa                    ; '<', '&', <= $20, >= $C0
        cmp #'<'
        beq ?start_tag
        cmp #'&'
        beq ?t_ent             ; rare cases: short branches to jmp stubs,
        ldx utf8_skip          ; so the common path never pays a taken
        bne ?t_cont            ; branch over a jmp (MADS jcc long form)
        cmp #$C0               ; UTF-8 lead byte?
        bcs ?t_lead

        ; byte <= $20: plain mode sends space / CR / LF / TAB straight to
        ; the word-space path (what html_emit_char + render_char would do)
        ldx emit_slow
        bne ?ascii
        cmp #CH_SPACE
        beq ?space
        cmp #13
        beq ?space
        cmp #10
        beq ?space
        cmp #9
        bne ?emit
?space  jsr render_space
        jmp parse_loop_re

?ascii  ldx emit_skip          ; combined flag: skips the jsr entirely
        bne ?jlp               ; during head/script/heading/fragment skip
?emit   jsr html_emit_char_ns
?jlp    jmp parse_loop_re

?start_tag
        lda #PS_IN_TAG
        sta zp_parse_state
        lda #0
        sta zp_tag_idx
        sta zp_attr_idx
        sta zp_val_idx
        sta is_closing
        sta img_src_len
        ; next byte straight into parse_tag (no dispatch)
        ldy chunk_idx
        cpy zp_rx_len
        beq ?jlp
        lda rx_buffer,y
        iny
        sty chunk_idx
        jmp parse_tag

?t_ent  jmp ?start_ent
?t_cont jmp ?utf8_cont
?t_lead jmp ?lead

        ; --- class 0: plain text byte ---
?plain  ora utf8_skip          ; A = utf8_skip
        bne ?cont_x            ; UTF-8 continuation byte
        ora emit_slow
        bne ?slow_x            ; skip / ANSI / pre / title mode
        ldy chunk_idx
        dey                    ; Y = this byte (class 0, so the run takes it)

        ; Word run: room = 79 - word_len (0 -> the byte is dropped)
        lda #WORD_BUF_SZ-1
        sec
        sbc zp_word_len
        beq ?full_y
        sty ?y0
        clc
        adc ?y0                ; limit = Y + room
        bcc ?lim_ok
        lda #0                 ; beyond 255: the sentinel ends the run first
?lim_ok sta ?lim+1
        lda zp_word_len        ; store base = word_buf + word_len - Y
        clc
        adc #<word_buf
        tax
        lda #>word_buf
        adc #0
        sta ?st+2
        txa
        sec
        sbc ?y0
        sta ?st+1
        bcs ?run
        dec ?st+2
?run    ldx rx_buffer,y
        lda char_class,x
        bne ?stop
        txa
?st     sta $FFFF,y            ; word_buf[word_len + Y - y0]
        iny
?lim    cpy #0
        bne ?run
        ert >?run <> >*         ; hot loop: keep it in one page
?stop   tya                    ; word_len += Y - y0
        sec
        sbc ?y0
        clc
        adc zp_word_len
        sta zp_word_len
        jmp parse_loop_y

?full_y iny                    ; word full: the byte is dropped (last_was_sp
        jmp parse_loop_y       ; only counts at word_len 0)

?slow_x txa
        ldx emit_skip
        jeq ?emit              ; ANSI / pre / title: full emit path
        ; skipped text: consume plain bytes without a jsr
        ldy chunk_idx
?skip   ldx rx_buffer,y
        lda char_class,x
        bne ?sk_end
        iny
        bne ?skip              ; always: the sentinel stops it
        ert >?skip <> >*         ; hot loop: keep it in one page
?sk_end jmp parse_loop_y

?cont_x txa
?utf8_cont
        dec utf8_skip
        bne ?jlp2               ; more continuation bytes to skip
        ; Last continuation byte -- try transliteration
        ldx utf8_lead
        beq ?jlp2               ; no lead saved (3/4-byte), skip
        jsr utf8_xlat           ; A=cont byte, X=lead -> A=ascii or 0
        jne ?ascii              ; 0 = no mapping, skip
?jlp2   jmp parse_loop_re

?lead   ; UTF-8 transliteration: 2-byte ($C0-$DF lead + 1 cont),
        ; 3-byte ($E0-$EF + 2), 4-byte ($F0+ + 3)
        cmp #$E0               ; 3-byte UTF-8 lead (E0-EF)?
        bcc ?utf2
        cmp #$F0               ; 4-byte UTF-8 lead (F0-F7)?
        bcc ?utf3
        lda #3                 ; >= F0: skip 3 continuation bytes
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

?start_ent
        lda #PS_IN_ENTITY
        sta zp_parse_state
        lda #0
        sta zp_entity_idx
        jmp parse_loop_re

?y0     dta 0
.endp

; --- Inside tag name ---
; Collects the name in a local loop until '>' or white space; '/' counts
; only as the first byte, "!--" as the first three switch to comment mode.
.proc parse_tag
        ldx zp_tag_idx
        bne ?chr
        cmp #'/'
        bne ?chr
        lda #1
        sta is_closing
        jmp parse_loop_re

?chr    ldy chunk_idx          ; X = tag_idx, Y = next index
?lp     cmp #'>'
        beq ?end
        cmp #CH_SPACE
        beq ?2attr
        cmp #10
        beq ?2attr
        cmp #13
        beq ?2attr
        cpx #TAG_BUF_SIZE-1
        bcs ?next              ; buffer full: drop
 .if 1                          ; 2026-09-23 (6502-idioms: to lower: the common lowercase byte (> 'Z') leaves on the
                                ; first compare, 5 cycles instead of 9; same result for every byte)
        cmp #'Z'+1             ; to lower
        bcs ?st
        cmp #'A'
        bcc ?st
        ora #$20
?st     sta tag_name_buf,x
 .else
        cmp #'A'               ; to lower
        bcc ?st
        cmp #'Z'+1
        bcs ?st
        ora #$20
?st     sta tag_name_buf,x
 .endif
        inx
        cpx #3
        beq ?chk3
?next   cpy zp_rx_len
        beq ?out
        lda rx_buffer,y
        iny
        bne ?lp                ; always (Y <= 255)
        ert >?lp <> >*         ; hot loop: keep it in one page

?out    stx zp_tag_idx         ; chunk exhausted mid-name
        sty chunk_idx
        jmp parse_loop_re

?chk3   lda tag_name_buf       ; "!--" = HTML comment
        cmp #'!'
        bne ?next
        lda tag_name_buf+1
        cmp #'-'
        bne ?next
        lda tag_name_buf+2
        cmp #'-'
        bne ?next
        stx zp_tag_idx
        sty chunk_idx
        lda #PS_IN_COMMENT
        sta zp_parse_state
        lda #0
        sta comment_dashes
        jmp parse_loop_re

?2attr  stx zp_tag_idx
        sty chunk_idx
        lda #0
        sta tag_name_buf,x
        sta zp_attr_idx
        lda #PS_IN_ATTRNAME
        sta zp_parse_state
        jmp parse_loop_re

?end    stx zp_tag_idx
        sty chunk_idx
        lda #0
        sta tag_name_buf,x
        jsr process_tag
        jmp reset_parse_and_loop
.endp

        .align $100            ; keep the attr-name loop in one page
; --- Attribute name --- (white space is skipped, the name continues)
.proc parse_attrname
        ldx zp_attr_idx
        ldy chunk_idx
?lp     cmp #'>'
        beq ?end_tag
        cmp #'='
        beq ?2val
        cmp #CH_SPACE
        beq ?next
        cmp #10
        beq ?next
        cmp #13
        beq ?next
        cpx #ATTR_BUF_SIZE-1
        bcs ?next
 .if 1                          ; 2026-09-23 (6502-idioms: to lower: the common lowercase byte (> 'Z') leaves on the
                                ; first compare, 5 cycles instead of 9; same result for every byte)
        cmp #'Z'+1             ; to lower
        bcs ?st
        cmp #'A'
        bcc ?st
        ora #$20
?st     sta attr_name_buf,x
 .else
        cmp #'A'               ; to lower
        bcc ?st
        cmp #'Z'+1
        bcs ?st
        ora #$20
?st     sta attr_name_buf,x
 .endif
        inx
?next   cpy zp_rx_len
        beq ?out
        lda rx_buffer,y
        iny
        bne ?lp                ; always
        ert >?lp <> >*         ; hot loop: keep it in one page

?out    stx zp_attr_idx
        sty chunk_idx
        jmp parse_loop_re

?2val   stx zp_attr_idx
        sty chunk_idx
        lda #0
        sta attr_name_buf,x
        sta zp_val_idx
        sta in_quotes
        lda #PS_IN_ATTRVAL
        sta zp_parse_state
        jmp parse_loop_re

?end_tag
        stx zp_attr_idx
        sty chunk_idx
        lda #0
        sta attr_name_buf,x
        jsr process_tag
        jmp reset_parse_and_loop
.endp

; --- Attribute value ---
.proc parse_attrval
        ldx in_quotes
        bne ?inq

        ; Unquoted: local loop until a quote, '>' or space
        ldx zp_val_idx
        ldy chunk_idx
?ulp    cmp #'"'
        beq ?stq
        cmp #$27
        beq ?stq
        cmp #'>'
        beq ?evtag_xy
        cmp #CH_SPACE
        beq ?endv_xy
        cpx #VAL_BUF_SIZE-1
        bcs ?unext
        sta attr_val_buf,x
        inx
?unext  cpy zp_rx_len
        beq ?uout
        lda rx_buffer,y
        iny
        bne ?ulp               ; always
        ert >?ulp <> >*         ; hot loop: keep it in one page
?uout   stx zp_val_idx
        sty chunk_idx
        jmp parse_loop_re

?stq    stx zp_val_idx
        sty chunk_idx
        sta in_quotes
        jmp parse_loop_re

?endv_xy
        stx zp_val_idx
        sty chunk_idx
        jmp ?endv
?evtag_xy
        stx zp_val_idx
        sty chunk_idx
        jmp ?evtag

?inq    cmp in_quotes
        beq ?endv
        ; Quoted value: copy in a tight loop until the closing quote
        ldx zp_val_idx
        ldy chunk_idx          ; >= 1: the current byte is stored first
        bne ?iq_store          ; always
?iq_lp  cpy zp_rx_len
        beq ?iq_end            ; chunk exhausted mid-value
        lda rx_buffer,y
        iny
        cmp in_quotes
        beq ?iq_quote          ; closing quote found
?iq_store
        cpx #VAL_BUF_SIZE-1
        bcs ?iq_lp             ; buffer full: keep scanning, don't store
        sta attr_val_buf,x
        inx
        bne ?iq_lp             ; always taken (X <= 255)
        ert >?iq_lp <> >*         ; hot loop: keep it in one page
?iq_quote
        sty chunk_idx
        stx zp_val_idx
        jmp ?endv
?iq_end sty chunk_idx
        stx zp_val_idx
        jmp parse_loop_re      ; index == len -> chunk done

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
        jmp reset_parse_and_loop
.endp

; --- Skip mode (script/style) - fast scan for '<' (sentinel ends it) ---
.proc parse_skipmode
        cmp #'<'
        beq ?found
        ldy chunk_idx
?scan   lda rx_buffer,y
        iny
        cmp #'<'
        bne ?scan
        ert >?scan <> >*         ; hot loop: keep it in one page
        dey
        cpy zp_rx_len
        beq ?end               ; the sentinel: chunk consumed
        iny
        sty chunk_idx
?found  lda #PS_IN_TAG
        sta zp_parse_state
        lda #0
        sta zp_tag_idx
        sta is_closing
        jmp parse_loop_re
?end    sty chunk_idx
        jmp parse_loop_re
.endp

; --- HTML comment mode (<!-- ... -->) ---
.proc parse_comment
        cmp #'-'
        bne ?not_dash
        inc comment_dashes
        jmp parse_loop_re
?not_dash
        cmp #'>'
        bne ?other
        ; Check if we had -- before >
        lda comment_dashes
        cmp #2
        bcs ?end_comment
?other  ; Ordinary comment byte: reset dash count, then fast-scan the
        ; rest of the chunk for '-'/'>' in a tight loop
        lda #0
        sta comment_dashes
        ldy chunk_idx
?scan   cpy zp_rx_len
        beq ?chunk_end
        lda rx_buffer,y
        iny
        cmp #'-'
        beq ?stop
        cmp #'>'
        bne ?scan
        ert >?scan <> >*         ; hot loop: keep it in one page
?stop   sty chunk_idx
        jmp parse_comment      ; re-handle found '-' or '>' above
?chunk_end
        sty chunk_idx
        jmp parse_loop_re      ; index == len -> chunk done
?end_comment
        jmp reset_parse_and_loop
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
        jmp reset_parse_and_loop

?abort  lda #'&'
        jsr html_emit_char
        jsr emit_entity_buf
        jmp reset_parse_and_loop

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
        ; Single precomputed skip test (see update_emit_skip)
        ldx emit_skip
        beq html_emit_char_ns
        rts
.endp

; html_emit_char_ns - html_emit_char when the caller already knows
; emit_skip = 0
.proc html_emit_char_ns
        ; ANSI escape sequence handling
        ; Detects ESC[$1B] and routes to CSI parser for SGR color codes
        ; Works in both normal text and <pre> blocks
        ldx ansi_state
        bne ?ansi_cont         ; already inside ESC sequence
        cmp #$1B               ; ESC character? start new sequence
        beq ?ansi_start

        ldx in_pre
        bne ?pre_ch
        cmp #13
        beq ?ws
        cmp #10
        beq ?ws
        cmp #9
        bne ?rc
?ws     lda #CH_SPACE
?rc     jmp render_char
?pre_ch cmp #10
        beq ?pre_nl
        cmp #13
        beq ?skip              ; CR in pre -> skip
        jmp render_out_char    ; direct output, preserve spaces
?pre_nl jmp render_do_nl

?ansi_start
        inc ansi_state         ; 0 -> 1: consume ESC, don't emit
        jmp update_emit_skip

?ansi_cont
        jmp ansi_process       ; handle ANSI continuation byte
?skip   rts
.endp

; ----------------------------------------------------------------------------
; update_emit_skip - Recompute the combined per-character flags
; emit_skip = zp_in_skip OR (!in_title AND (zp_in_head OR skip_to_heading
;             OR skip_to_frag))
; skip_hf   = skip_to_heading OR skip_to_frag
; emit_slow = emit_skip OR ansi_state OR in_pre OR in_title (0 = plain text)
; In <title> only script/style skip applies -- title text is always
; collected into title_buf (render_char routes it there).
; MUST be called after changing any source flag. Clobbers: A
; ----------------------------------------------------------------------------
.proc update_emit_skip
        lda skip_to_heading
        ora skip_to_frag
        sta skip_hf
        lda in_title
        beq ?notitle
        lda zp_in_skip
        bpl ?set               ; always (flags are 0/1)
?notitle
        lda zp_in_head
        ora skip_hf
        ora zp_in_skip
?set    sta emit_skip
        ora ansi_state
        ora in_pre
        ora in_title
        sta emit_slow
        rts
.endp


; --- Parser state variables ---
; (in_pre and utf8_skip moved to zero page — tested per emitted/text char)
is_closing     dta 0          ; 1 = closing tag (</...>), set when '/' seen at tag start
in_title       dta 0          ; 1 = inside <title>: chars go to title_buf via render_char
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
; (ansi_state moved to zero page — tested per emitted char)
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
        sbc #'0'-1             ; C = 0 (A < '9'+1): A = digit
        sta ?tmp
        lda ansi_param         ; (4p + p) * 2 = 10p, mod 256 as before
        asl
        asl
        clc
        adc ansi_param
        asl
        clc
        adc ?tmp               ; + digit
        sta ansi_param
        rts

?cmd    ; Non-digit: check for separator or command
        cmp #';'
        beq ?separator         ; ';' separates params (e.g. ESC[1;31m)
        cmp #'m'
        bne ?abort             ; unknown command letter - abort
        ; 'm' = SGR command: apply the last param and finish
        jsr ansi_apply_sgr
        jmp ?abort

?expect_bracket
        cmp #'['               ; CSI introducer
        bne ?abort
        inc ansi_state         ; 1 -> 2: parameter collection
        lda #0
        sta ansi_param         ; reset first parameter
        rts

?abort  lda #0                 ; not CSI, abort sequence
        sta ansi_state
        jmp update_emit_skip   ; plain text again

?separator
        jsr ansi_apply_sgr     ; apply current param
        lda #0
        sta ansi_param         ; reset for next param
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

?reset  sta ansi_bold           ; A = 0
        lda #ATTR_NORMAL
        sta zp_cur_attr        ; = render_set_attr
        rts

?bold   sta ansi_bold           ; A = 1
        rts

?unbold lda #0
        sta ansi_bold
        rts

?fg_std ; C = 0 (A < 38): code 30-37 -> palette $10-$17 (+8 when bold)
        adc #ATTR_ANSI_BASE-30 ; (adds $F2: C = 1 afterwards)
        ldx ansi_bold
        beq ?set
        adc #8-1               ; C = 1: +8
?set    sta zp_cur_attr        ; = render_set_attr
        rts

?fg_bright
        ; C = 0 (A < 98): code 90-97 -> bright palette $18-$1F
        adc #ATTR_ANSI_BASE+8-90
        sta zp_cur_attr
        rts
.endp

; Buffers
tag_name_buf   .ds TAG_BUF_SIZE
attr_name_buf  .ds ATTR_BUF_SIZE
attr_val_buf   .ds VAL_BUF_SIZE
entity_buf     .ds ENTITY_BUF_SZ
