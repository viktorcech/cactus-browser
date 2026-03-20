; ============================================================================
; HTML Parser Module - Streamovy byte-by-byte parser
; ============================================================================

; Parser states
PS_NORMAL      = 0
PS_IN_TAG      = 1
PS_IN_ENTITY   = 2
PS_IN_ATTRNAME = 3
PS_IN_ATTRVAL  = 4
PS_SKIP_TAG    = 5

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

TAG_BUF_SIZE   = 16
ATTR_BUF_SIZE  = 16
VAL_BUF_SIZE   = 128
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
        rts
.endp

; ============================================================================
; html_process_chunk - main parser loop
; Split into small sub-procs to avoid branch-out-of-range
; ============================================================================
chunk_idx  dta 0
in_quotes  dta 0

.proc html_process_chunk
        lda #0
        sta chunk_idx
.endp
        ; fall through to parse_loop_re

parse_loop_re
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
?noav   jmp parse_skipmode

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

        ldx zp_in_skip
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

; --- Skip mode (script/style) ---
.proc parse_skipmode
        cmp #'<'
        bne ?jlp
        lda #PS_IN_TAG
        sta zp_parse_state
        lda #0
        sta zp_tag_idx
        sta is_closing
?jlp    jmp parse_loop_re
.endp

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
        jsr render_flush_word
        rts
.endp

.proc html_emit_char
        ldx zp_in_skip
        bne ?skip
        cmp #13
        beq ?ws
        cmp #10
        beq ?ws
        cmp #9
        beq ?ws
        jsr render_char
        rts
?ws     lda #CH_SPACE
        jsr render_char
?skip   rts
.endp

; ============================================================================
; process_tag - Handle parsed tag (split into open/close sub-procs)
; ============================================================================
.proc process_tag
        jsr lookup_tag

        ldx is_closing
        bne ?closing

        ; Opening tags - use jump table approach
        cmp #TAG_H1
        beq ?joh
        cmp #TAG_H2
        beq ?joh
        cmp #TAG_H3
        beq ?joh
        cmp #TAG_P
        beq ?jop
        cmp #TAG_BR
        beq ?jop
        cmp #TAG_A
        beq ?joa
        cmp #TAG_UL
        beq ?joul
        cmp #TAG_OL
        beq ?jool
        cmp #TAG_LI
        beq ?joli
        cmp #TAG_B
        beq ?jobold
        cmp #TAG_STRONG
        beq ?jobold
        cmp #TAG_I
        beq ?joital
        cmp #TAG_EM
        beq ?joital
        cmp #TAG_TITLE
        jmp open_tag_more

?joh    jmp open_heading
?jop    jmp open_para
?joa    jmp open_link
?joul   jmp open_ul
?jool   jmp open_ol
?joli   jmp open_li
?jobold jmp open_bold
?joital jmp open_italic

?closing
        cmp #TAG_H1
        beq ?jch
        cmp #TAG_H2
        beq ?jch
        cmp #TAG_H3
        beq ?jch
        cmp #TAG_P
        beq ?jcp
        cmp #TAG_A
        beq ?jca
        cmp #TAG_UL
        beq ?jcl
        cmp #TAG_OL
        beq ?jcl
        cmp #TAG_B
        beq ?jcb
        cmp #TAG_STRONG
        beq ?jcb
        cmp #TAG_I
        beq ?jci
        cmp #TAG_EM
        beq ?jci
        cmp #TAG_TITLE
        jmp close_tag_more

?jch    jmp close_heading
?jcp    jmp close_para
?jca    jmp close_link
?jcl    jmp close_list
?jcb    jmp close_bold
?jci    jmp close_italic
.endp

; Remaining open tag checks
.proc open_tag_more
        beq ?otitle
        cmp #TAG_SCRIPT
        beq ?oskip
        cmp #TAG_STYLE
        beq ?oskip
        cmp #TAG_IMG
        beq ?oimg
        cmp #TAG_HR
        beq ?ohr
        cmp #TAG_DIV
        beq ?odiv
        rts

?otitle jsr render_flush_word
        lda #1
        sta in_title
        rts
?oskip  lda #1
        sta zp_in_skip
        rts
?oimg   jsr render_flush_word
        lda #<m_img
        ldx #>m_img
        jsr render_string
        rts
?ohr    jsr render_flush_word
        jsr render_newline
        jsr render_hr_line
        jsr render_newline
        rts
?odiv   jsr render_flush_word
        jsr render_newline
        rts

m_img   dta c'[IMG]',0
.endp

; Remaining close tag checks
.proc close_tag_more
        beq ?ctitle
        cmp #TAG_SCRIPT
        beq ?cskip
        cmp #TAG_STYLE
        beq ?cskip
        cmp #TAG_DIV
        beq ?cdiv
        rts

?ctitle lda #0
        sta in_title
        rts
?cskip  lda #0
        sta zp_in_skip
        lda #PS_NORMAL
        sta zp_parse_state
        rts
?cdiv   jsr render_flush_word
        jsr render_newline
        rts
.endp

; Tag action procs
.proc open_heading
        jsr render_flush_word
        jsr render_newline
        lda #1
        sta zp_in_heading
        lda #ATTR_HEADING
        jsr render_set_attr
        rts
.endp

.proc open_para
        jsr render_flush_word
        jsr render_newline
        rts
.endp

.proc open_link
        jsr render_flush_word
        lda #1
        sta zp_in_link
        lda #ATTR_LINK
        jsr render_set_attr
        jsr render_link_prefix
        rts
.endp

.proc open_ul
        lda #0
        sta zp_list_type
        lda #1
        sta zp_in_list
        lda zp_indent
        clc
        adc #2
        sta zp_indent
        rts
.endp

.proc open_ol
        lda #1
        sta zp_list_type
        sta zp_in_list
        lda #0
        sta zp_list_item
        lda zp_indent
        clc
        adc #2
        sta zp_indent
        rts
.endp

.proc open_li
        jsr render_flush_word
        jsr render_newline
        jsr render_list_bullet
        rts
.endp

.proc open_bold
        lda #1
        sta zp_in_bold
        rts
.endp

.proc open_italic
        lda #ATTR_DECOR
        jsr render_set_attr
        rts
.endp

.proc close_heading
        jsr render_flush_word
        lda #0
        sta zp_in_heading
        lda #ATTR_NORMAL
        jsr render_set_attr
        jsr render_newline
        rts
.endp

.proc close_para
        jsr render_flush_word
        jsr render_newline
        rts
.endp

.proc close_link
        jsr render_flush_word
        lda #0
        sta zp_in_link
        lda #ATTR_NORMAL
        jsr render_set_attr
        rts
.endp

.proc close_list
        lda #0
        sta zp_in_list
        lda zp_indent
        sec
        sbc #2
        bcs ?ok
        lda #0
?ok     sta zp_indent
        rts
.endp

.proc close_bold
        lda #0
        sta zp_in_bold
        rts
.endp

.proc close_italic
        lda #ATTR_NORMAL
        jsr render_set_attr
        rts
.endp

; ============================================================================
; process_attr
; ============================================================================
.proc process_attr
        lda attr_name_buf
        cmp #'h'
        bne ?done
        lda attr_name_buf+1
        cmp #'r'
        bne ?done
        lda attr_name_buf+2
        cmp #'e'
        bne ?done
        lda attr_name_buf+3
        cmp #'f'
        bne ?done
        jsr store_link_url
?done   rts
.endp

; ============================================================================
; store_link_url
; ============================================================================
MAX_LINKS      = 32
LINK_URL_SIZE  = 128

.proc store_link_url
        lda zp_link_num
        cmp #MAX_LINKS
        bcs ?full

        lda zp_link_num
        lsr
        tax
        lda #0
        ror
        clc
        adc #<link_urls
        sta zp_tmp_ptr
        txa
        adc #>link_urls
        sta zp_tmp_ptr+1

        ldy #0
?cp     lda attr_val_buf,y
        sta (zp_tmp_ptr),y
        beq ?ok
        iny
        cpy #LINK_URL_SIZE-1
        bne ?cp
        lda #0
        sta (zp_tmp_ptr),y
?ok     inc zp_link_num
?full   rts
.endp

; ============================================================================
; lookup_tag
; ============================================================================
NUM_TAGS = 23

.proc lookup_tag
        ldx #0
?next   lda tag_tbl_lo,x
        sta zp_tmp_ptr
        lda tag_tbl_hi,x
        sta zp_tmp_ptr+1

        ldy #0
?cmp    lda (zp_tmp_ptr),y
        beq ?chk
        cmp tag_name_buf,y
        bne ?skip
        iny
        bne ?cmp

?chk    lda tag_name_buf,y
        beq ?found
?skip   inx
        cpx #NUM_TAGS
        bne ?next
        lda #TAG_UNKNOWN
        rts
?found  lda tag_ids,x
        rts
.endp

ts_h1     dta c'h1',0
ts_h2     dta c'h2',0
ts_h3     dta c'h3',0
ts_p      dta c'p',0
ts_br     dta c'br',0
ts_a      dta c'a',0
ts_ul     dta c'ul',0
ts_ol     dta c'ol',0
ts_li     dta c'li',0
ts_b      dta c'b',0
ts_strong dta c'strong',0
ts_i      dta c'i',0
ts_em     dta c'em',0
ts_title  dta c'title',0
ts_script dta c'script',0
ts_style  dta c'style',0
ts_img    dta c'img',0
ts_input  dta c'input',0
ts_form   dta c'form',0
ts_div    dta c'div',0
ts_span   dta c'span',0
ts_pre    dta c'pre',0
ts_hr     dta c'hr',0

tag_tbl_lo
        dta <ts_h1, <ts_h2, <ts_h3, <ts_p
        dta <ts_br, <ts_a, <ts_ul, <ts_ol
        dta <ts_li, <ts_b, <ts_strong, <ts_i
        dta <ts_em, <ts_title, <ts_script, <ts_style
        dta <ts_img, <ts_input, <ts_form, <ts_div
        dta <ts_span, <ts_pre, <ts_hr

tag_tbl_hi
        dta >ts_h1, >ts_h2, >ts_h3, >ts_p
        dta >ts_br, >ts_a, >ts_ul, >ts_ol
        dta >ts_li, >ts_b, >ts_strong, >ts_i
        dta >ts_em, >ts_title, >ts_script, >ts_style
        dta >ts_img, >ts_input, >ts_form, >ts_div
        dta >ts_span, >ts_pre, >ts_hr

tag_ids dta TAG_H1, TAG_H2, TAG_H3, TAG_P
        dta TAG_BR, TAG_A, TAG_UL, TAG_OL
        dta TAG_LI, TAG_B, TAG_STRONG, TAG_I
        dta TAG_EM, TAG_TITLE, TAG_SCRIPT, TAG_STYLE
        dta TAG_IMG, TAG_INPUT, TAG_FORM, TAG_DIV
        dta TAG_SPAN, TAG_PRE, TAG_HR

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
        bcc ?unk
        cmp #10
        bcs ?unk
        pha
        lda zp_tmp1
        asl
        asl
        clc
        adc zp_tmp1
        asl
        sta zp_tmp1
        pla
        clc
        adc zp_tmp1
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

.proc to_lower
        cmp #'A'
        bcc ?ok
        cmp #'Z'+1
        bcs ?ok
        ora #$20
?ok     rts
.endp

; State variables
is_closing     dta 0
in_title       dta 0

; Buffers
tag_name_buf   .ds TAG_BUF_SIZE
attr_name_buf  .ds ATTR_BUF_SIZE
attr_val_buf   .ds VAL_BUF_SIZE
entity_buf     .ds ENTITY_BUF_SZ

; Link storage is in data.asm (at $9200+ to avoid MEMAC B conflict)
