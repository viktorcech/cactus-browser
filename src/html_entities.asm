; ============================================================================
; HTML Entity Decoding & Tag Lookup Tables
; ============================================================================

; ============================================================================
; lookup_tag - Find tag ID from tag_name_buf
; Tables are sorted alphabetically and indexed by first letter: only the
; matching letter's bucket is scanned (1-9 candidates) instead of all 47
; entries. Unknown tags (meta, link, ...) — the most common case on real
; pages — no longer pay a full-table scan, and non-letter names like
; "!doctype" bail out immediately.
; Output: A = tag ID
; ============================================================================
NUM_TAGS = 47

        .align $100            ; bucket loop in one page
.proc lookup_tag
        lda tag_name_buf
        sec
        sbc #'a'
        cmp #26                ; (bytes below 'a' wrap to >= 26)
        bcs ?unk               ; first char not a-z -> unknown
        tax
        lda letter_start+1,x   ; bucket end = next letter's start
        sta ?end+1
        lda letter_start,x
        tax
?next
?end    cpx #0                 ; bucket exhausted? (operand patched)
        beq ?unk
        lda tag_tbl_lo,x
        sta zp_tmp_ptr
        lda tag_tbl_hi,x
        sta zp_tmp_ptr+1

        ldy #1                 ; first letter matched by the bucket
?cmp    lda (zp_tmp_ptr),y
        beq ?chk
        cmp tag_name_buf,y
        bne ?skip
        iny
        bne ?cmp
        ert >?cmp <> >*         ; hot loop: keep it in one page

?chk    lda tag_name_buf,y
        beq ?found
?skip   inx
        bne ?next              ; always taken (X < NUM_TAGS)
?unk    lda #TAG_UNKNOWN
        rts
?found  lda tag_ids,x
        rts
.endp

; Tag strings, alphabetical order (digits sort before letters: h1 < head)
ts_a      dta c'a',0
ts_article dta c'article',0
ts_aside  dta c'aside',0
ts_b      dta c'b',0
ts_blockquote dta c'blockquote',0
ts_body   dta c'body',0
ts_br     dta c'br',0
ts_code   dta c'code',0
ts_dd     dta c'dd',0
ts_div    dta c'div',0
ts_dt     dta c'dt',0
ts_em     dta c'em',0
ts_footer dta c'footer',0
ts_form   dta c'form',0
ts_h1     dta c'h1',0
ts_h2     dta c'h2',0
ts_h3     dta c'h3',0
ts_h4     dta c'h4',0
ts_h5     dta c'h5',0
ts_h6     dta c'h6',0
ts_head   dta c'head',0
ts_header_tag dta c'header',0
ts_hr     dta c'hr',0
ts_i      dta c'i',0
ts_img    dta c'img',0
ts_input  dta c'input',0
ts_li     dta c'li',0
ts_main   dta c'main',0
ts_nav    dta c'nav',0
ts_noscript dta c'noscript',0
ts_ol     dta c'ol',0
ts_p      dta c'p',0
ts_pre    dta c'pre',0
ts_script dta c'script',0
ts_section dta c'section',0
ts_span   dta c'span',0
ts_strong dta c'strong',0
ts_style  dta c'style',0
ts_sub    dta c'sub',0
ts_sup    dta c'sup',0
ts_table  dta c'table',0
ts_td     dta c'td',0
ts_th     dta c'th',0
ts_title  dta c'title',0
ts_tr     dta c'tr',0
ts_u      dta c'u',0
ts_ul     dta c'ul',0

; First-letter index: start position of each letter's bucket in the
; tables below (27 entries: a-z + sentinel; empty bucket = same as next)
letter_start
        dta 0                  ; a: a, article, aside
        dta 3                  ; b: b, blockquote, body, br
        dta 7                  ; c: code
        dta 8                  ; d: dd, div, dt
        dta 11                 ; e: em
        dta 12                 ; f: footer, form
        dta 14                 ; g: (none)
        dta 14                 ; h: h1-h6, head, header, hr
        dta 23                 ; i: i, img, input
        dta 26                 ; j: (none)
        dta 26                 ; k: (none)
        dta 26                 ; l: li
        dta 27                 ; m: main
        dta 28                 ; n: nav, noscript
        dta 30                 ; o: ol
        dta 31                 ; p: p, pre
        dta 33                 ; q: (none)
        dta 33                 ; r: (none)
        dta 33                 ; s: script, section, span, strong, style, sub, sup
        dta 40                 ; t: table, td, th, title, tr
        dta 45                 ; u: u, ul
        dta 47                 ; v: (none)
        dta 47                 ; w: (none)
        dta 47                 ; x: (none)
        dta 47                 ; y: (none)
        dta 47                 ; z: (none)
        dta 47                 ; sentinel (end of table)

tag_tbl_lo
        dta <ts_a, <ts_article, <ts_aside
        dta <ts_b, <ts_blockquote, <ts_body, <ts_br
        dta <ts_code
        dta <ts_dd, <ts_div, <ts_dt
        dta <ts_em
        dta <ts_footer, <ts_form
        dta <ts_h1, <ts_h2, <ts_h3, <ts_h4, <ts_h5, <ts_h6
        dta <ts_head, <ts_header_tag, <ts_hr
        dta <ts_i, <ts_img, <ts_input
        dta <ts_li
        dta <ts_main
        dta <ts_nav, <ts_noscript
        dta <ts_ol
        dta <ts_p, <ts_pre
        dta <ts_script, <ts_section, <ts_span, <ts_strong, <ts_style
        dta <ts_sub, <ts_sup
        dta <ts_table, <ts_td, <ts_th, <ts_title, <ts_tr
        dta <ts_u, <ts_ul

tag_tbl_hi
        dta >ts_a, >ts_article, >ts_aside
        dta >ts_b, >ts_blockquote, >ts_body, >ts_br
        dta >ts_code
        dta >ts_dd, >ts_div, >ts_dt
        dta >ts_em
        dta >ts_footer, >ts_form
        dta >ts_h1, >ts_h2, >ts_h3, >ts_h4, >ts_h5, >ts_h6
        dta >ts_head, >ts_header_tag, >ts_hr
        dta >ts_i, >ts_img, >ts_input
        dta >ts_li
        dta >ts_main
        dta >ts_nav, >ts_noscript
        dta >ts_ol
        dta >ts_p, >ts_pre
        dta >ts_script, >ts_section, >ts_span, >ts_strong, >ts_style
        dta >ts_sub, >ts_sup
        dta >ts_table, >ts_td, >ts_th, >ts_title, >ts_tr
        dta >ts_u, >ts_ul

tag_ids dta TAG_A, TAG_ARTICLE, TAG_ASIDE
        dta TAG_B, TAG_BLOCKQUOTE, TAG_BODY, TAG_BR
        dta TAG_CODE
        dta TAG_DD, TAG_DIV, TAG_DT
        dta TAG_EM
        dta TAG_FOOTER, TAG_FORM
        dta TAG_H1, TAG_H2, TAG_H3, TAG_H4, TAG_H5, TAG_H6
        dta TAG_HEAD, TAG_HEADER, TAG_HR
        dta TAG_I, TAG_IMG, TAG_INPUT
        dta TAG_LI
        dta TAG_MAIN
        dta TAG_NAV, TAG_NOSCRIPT
        dta TAG_OL
        dta TAG_P, TAG_PRE
        dta TAG_SCRIPT, TAG_SECTION, TAG_SPAN, TAG_STRONG, TAG_STYLE
        dta TAG_SUB, TAG_SUP
        dta TAG_TABLE, TAG_TD, TAG_TH, TAG_TITLE, TAG_TR
        dta TAG_U, TAG_UL

; ============================================================================
; Entity decoding
; ============================================================================
.proc decode_entity
        lda entity_buf
        cmp #'a'
        beq ?amp
        cmp #'l'
        beq ?lt
        cmp #'g'
        beq ?gt
        cmp #'n'
        beq ?nbsp
        cmp #'q'
        beq ?quot
        cmp #'#'
        beq ?num
        lda #'?'
        rts

?amp    lda entity_buf+1
        cmp #'m'
        bne ?unk
        lda #'&'
        rts
?lt     lda entity_buf+1
        cmp #'t'
        bne ?unk
        lda #'<'
        rts
?gt     lda entity_buf+1
        cmp #'t'
        bne ?unk
        lda #'>'
        rts
?nbsp   lda entity_buf+1
        cmp #'b'
        bne ?unk
        lda #CH_SPACE
        rts
?quot   lda entity_buf+1
        cmp #'u'
        bne ?unk
        lda #'"'
        rts
?unk    lda #'?'
        rts

?num    lda #0
        sta zp_tmp1
        ldx #1
?nlp    lda entity_buf,x
        beq ?nd
        sec
        sbc #'0'
        cmp #10                ; ('0'-1 and below wrap to >= 10)
        bcs ?unk
        sta zp_tmp2            ; digit
        lda zp_tmp1            ; value = value * 10 + digit (mod 256)
        asl
        asl
        clc
        adc zp_tmp1
        asl
        clc
        adc zp_tmp2
        sta zp_tmp1
        inx
        cpx #4
        bne ?nlp
?nd     lda zp_tmp1
        rts
.endp

.proc emit_entity_buf
        ldx #0
?lp     cpx zp_entity_idx
        beq ?done
        lda entity_buf,x
        stx zp_tmp2
        jsr html_emit_char
        ldx zp_tmp2
        inx
        bne ?lp
?done   rts
.endp
