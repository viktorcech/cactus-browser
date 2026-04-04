; ============================================================================
; HTML Tag Handlers - open/close tag actions, attribute processing, link storage
; ============================================================================

; Current tag ID - saved before dispatch for handlers that need it
current_tag_id dta 0

; ============================================================================
; process_tag - Handle parsed tag via jump table dispatch
; ============================================================================
.proc process_tag
        jsr lookup_tag
        sta current_tag_id

        ; In skip mode (script/style), only process their
        ; closing tags - ignore everything else inside the block
        ldx zp_in_skip
        beq ?not_skip
        ldx is_closing
        beq ?ret
        cmp #TAG_SCRIPT
        beq ?cls
        cmp #TAG_STYLE
        beq ?cls
?ret    rts
?cls    lda #0
        sta zp_in_skip
        rts

?not_skip
        ; In <head> mode - only process head-related tags
        ; If a known content tag appears, auto-clear head mode
        ; (safety for pages without explicit <body>)
        ldx zp_in_head
        beq ?dispatch
        cmp #TAG_TITLE
        beq ?dispatch
        cmp #TAG_SCRIPT
        beq ?dispatch
        cmp #TAG_STYLE
        beq ?dispatch
        cmp #TAG_HEAD
        beq ?dispatch
        cmp #TAG_BODY
        beq ?dispatch
        cmp #TAG_UNKNOWN
        beq ?ret              ; meta/link etc. - ignore in head
        ; Known content tag (p, div, h1...) - page has no <body>
        lda #0
        sta zp_in_head

?dispatch
        ldx current_tag_id
        lda is_closing
        bne ?close
        ; --- Open tag dispatch ---
        lda otbl_hi,x
        sta zp_tmp_ptr+1
        lda otbl_lo,x
        sta zp_tmp_ptr
        jmp (zp_tmp_ptr)
?close  ; --- Close tag dispatch ---
        lda ctbl_hi,x
        sta zp_tmp_ptr+1
        lda ctbl_lo,x
        sta zp_tmp_ptr
        jmp (zp_tmp_ptr)
.endp

; Handler for tags with no action
nop_tag rts

; ============================================================================
; Jump tables - 48 entries each (TAG_UNKNOWN=0 .. TAG_MAIN=47)
; ============================================================================
otbl_lo dta <nop_tag           ; 0  UNKNOWN
        dta <open_heading      ; 1  H1
        dta <open_heading      ; 2  H2
        dta <open_heading      ; 3  H3
        dta <open_para         ; 4  P
        dta <open_para         ; 5  BR
        dta <open_link         ; 6  A
        dta <open_ul           ; 7  UL
        dta <open_ol           ; 8  OL
        dta <open_li           ; 9  LI
        dta <open_bold         ; 10 B
        dta <open_bold         ; 11 STRONG
        dta <open_italic       ; 12 I
        dta <open_italic       ; 13 EM
        dta <open_title        ; 14 TITLE
        dta <open_skip         ; 15 SCRIPT
        dta <open_skip         ; 16 STYLE
        dta <open_img          ; 17 IMG
        dta <nop_tag           ; 18 INPUT
        dta <nop_tag           ; 19 FORM
        dta <open_div          ; 20 DIV
        dta <nop_tag           ; 21 SPAN
        dta <open_pre          ; 22 PRE
        dta <open_hr           ; 23 HR
        dta <nop_tag           ; 24 NOSCRIPT
        dta <open_table        ; 25 TABLE
        dta <open_tr           ; 26 TR
        dta <open_td           ; 27 TD
        dta <open_th           ; 28 TH
        dta <open_bq           ; 29 BLOCKQUOTE
        dta <open_dt           ; 30 DT
        dta <open_dd           ; 31 DD
        dta <open_code         ; 32 CODE
        dta <open_head         ; 33 HEAD
        dta <open_body         ; 34 BODY
        dta <open_heading      ; 35 H4
        dta <open_heading      ; 36 H5
        dta <open_heading      ; 37 H6
        dta <open_underline    ; 38 U
        dta <open_sup          ; 39 SUP
        dta <open_sub          ; 40 SUB
        dta <open_div          ; 41 NAV
        dta <open_div          ; 42 ARTICLE
        dta <open_div          ; 43 SECTION
        dta <open_div          ; 44 ASIDE
        dta <open_div          ; 45 HEADER
        dta <open_div          ; 46 FOOTER
        dta <open_div          ; 47 MAIN

otbl_hi dta >nop_tag           ; 0  UNKNOWN
        dta >open_heading      ; 1  H1
        dta >open_heading      ; 2  H2
        dta >open_heading      ; 3  H3
        dta >open_para         ; 4  P
        dta >open_para         ; 5  BR
        dta >open_link         ; 6  A
        dta >open_ul           ; 7  UL
        dta >open_ol           ; 8  OL
        dta >open_li           ; 9  LI
        dta >open_bold         ; 10 B
        dta >open_bold         ; 11 STRONG
        dta >open_italic       ; 12 I
        dta >open_italic       ; 13 EM
        dta >open_title        ; 14 TITLE
        dta >open_skip         ; 15 SCRIPT
        dta >open_skip         ; 16 STYLE
        dta >open_img          ; 17 IMG
        dta >nop_tag           ; 18 INPUT
        dta >nop_tag           ; 19 FORM
        dta >open_div          ; 20 DIV
        dta >nop_tag           ; 21 SPAN
        dta >open_pre          ; 22 PRE
        dta >open_hr           ; 23 HR
        dta >nop_tag           ; 24 NOSCRIPT
        dta >open_table        ; 25 TABLE
        dta >open_tr           ; 26 TR
        dta >open_td           ; 27 TD
        dta >open_th           ; 28 TH
        dta >open_bq           ; 29 BLOCKQUOTE
        dta >open_dt           ; 30 DT
        dta >open_dd           ; 31 DD
        dta >open_code         ; 32 CODE
        dta >open_head         ; 33 HEAD
        dta >open_body         ; 34 BODY
        dta >open_heading      ; 35 H4
        dta >open_heading      ; 36 H5
        dta >open_heading      ; 37 H6
        dta >open_underline    ; 38 U
        dta >open_sup          ; 39 SUP
        dta >open_sub          ; 40 SUB
        dta >open_div          ; 41 NAV
        dta >open_div          ; 42 ARTICLE
        dta >open_div          ; 43 SECTION
        dta >open_div          ; 44 ASIDE
        dta >open_div          ; 45 HEADER
        dta >open_div          ; 46 FOOTER
        dta >open_div          ; 47 MAIN

ctbl_lo dta <nop_tag           ; 0  UNKNOWN
        dta <close_heading     ; 1  H1
        dta <close_heading     ; 2  H2
        dta <close_heading     ; 3  H3
        dta <close_para        ; 4  P
        dta <nop_tag           ; 5  BR (no close)
        dta <close_link        ; 6  A
        dta <close_list        ; 7  UL
        dta <close_list        ; 8  OL
        dta <nop_tag           ; 9  LI (no close)
        dta <close_bold        ; 10 B
        dta <close_bold        ; 11 STRONG
        dta <close_italic      ; 12 I
        dta <close_italic      ; 13 EM
        dta <close_title       ; 14 TITLE
        dta <close_skip        ; 15 SCRIPT
        dta <close_skip        ; 16 STYLE
        dta <nop_tag           ; 17 IMG (no close)
        dta <nop_tag           ; 18 INPUT
        dta <nop_tag           ; 19 FORM
        dta <close_div         ; 20 DIV
        dta <nop_tag           ; 21 SPAN
        dta <close_pre         ; 22 PRE
        dta <nop_tag           ; 23 HR (no close)
        dta <nop_tag           ; 24 NOSCRIPT
        dta <close_table       ; 25 TABLE
        dta <nop_tag           ; 26 TR
        dta <nop_tag           ; 27 TD
        dta <close_th          ; 28 TH
        dta <close_bq          ; 29 BLOCKQUOTE
        dta <close_dt          ; 30 DT
        dta <close_dd          ; 31 DD
        dta <close_code        ; 32 CODE
        dta <close_head        ; 33 HEAD
        dta <nop_tag           ; 34 BODY
        dta <close_heading     ; 35 H4
        dta <close_heading     ; 36 H5
        dta <close_heading     ; 37 H6
        dta <close_italic      ; 38 U   (= ATTR_NORMAL)
        dta <close_italic      ; 39 SUP (= ATTR_NORMAL)
        dta <close_italic      ; 40 SUB (= ATTR_NORMAL)
        dta <close_div         ; 41 NAV
        dta <close_div         ; 42 ARTICLE
        dta <close_div         ; 43 SECTION
        dta <close_div         ; 44 ASIDE
        dta <close_div         ; 45 HEADER
        dta <close_div         ; 46 FOOTER
        dta <close_div         ; 47 MAIN

ctbl_hi dta >nop_tag           ; 0  UNKNOWN
        dta >close_heading     ; 1  H1
        dta >close_heading     ; 2  H2
        dta >close_heading     ; 3  H3
        dta >close_para        ; 4  P
        dta >nop_tag           ; 5  BR
        dta >close_link        ; 6  A
        dta >close_list        ; 7  UL
        dta >close_list        ; 8  OL
        dta >nop_tag           ; 9  LI
        dta >close_bold        ; 10 B
        dta >close_bold        ; 11 STRONG
        dta >close_italic      ; 12 I
        dta >close_italic      ; 13 EM
        dta >close_title       ; 14 TITLE
        dta >close_skip        ; 15 SCRIPT
        dta >close_skip        ; 16 STYLE
        dta >nop_tag           ; 17 IMG
        dta >nop_tag           ; 18 INPUT
        dta >nop_tag           ; 19 FORM
        dta >close_div         ; 20 DIV
        dta >nop_tag           ; 21 SPAN
        dta >close_pre         ; 22 PRE
        dta >nop_tag           ; 23 HR
        dta >nop_tag           ; 24 NOSCRIPT
        dta >close_table       ; 25 TABLE
        dta >nop_tag           ; 26 TR
        dta >nop_tag           ; 27 TD
        dta >close_th          ; 28 TH
        dta >close_bq          ; 29 BLOCKQUOTE
        dta >close_dt          ; 30 DT
        dta >close_dd          ; 31 DD
        dta >close_code        ; 32 CODE
        dta >close_head        ; 33 HEAD
        dta >nop_tag           ; 34 BODY
        dta >close_heading     ; 35 H4
        dta >close_heading     ; 36 H5
        dta >close_heading     ; 37 H6
        dta >close_italic      ; 38 U
        dta >close_italic      ; 39 SUP
        dta >close_italic      ; 40 SUB
        dta >close_div         ; 41 NAV
        dta >close_div         ; 42 ARTICLE
        dta >close_div         ; 43 SECTION
        dta >close_div         ; 44 ASIDE
        dta >close_div         ; 45 HEADER
        dta >close_div         ; 46 FOOTER
        dta >close_div         ; 47 MAIN

; ============================================================================
; Open tag handlers (extracted from old dispatch procs)
; ============================================================================

.proc open_title
        jsr render_flush_word
        lda #1
        sta in_title
        rts
.endp

.proc open_skip
        lda #1
        sta zp_in_skip
        rts
.endp

.proc open_img
        jsr render_flush_word
        lda img_src_len
        beq ?nourl
        jsr store_img_as_link
?nourl  rts
.endp

.proc open_hr
        jsr render_flush_word
        jsr render_newline
        jsr render_hr_line
        jmp render_newline
.endp

.proc open_div
        jsr render_flush_word
        lda zp_render_col
        beq ?skip
        jmp render_do_nl
?skip   rts
.endp

.proc open_head
        lda #1
        sta zp_in_head
        rts
.endp

.proc open_body
        lda #0
        sta zp_in_head
        sta http_bytes_lo
        sta http_bytes_hi
        rts
.endp

open_underline
        lda #ATTR_UNDERLINE
        .byte $2C              ; BIT abs - skip next 2 bytes
open_sup
        lda #ATTR_SUP
        .byte $2C              ; BIT abs - skip next 2 bytes
open_sub
        lda #ATTR_SUB
        jmp render_set_attr

.proc open_table
        jsr render_flush_word
        jsr render_newline
        jsr render_tbl_line
        lda #0
        sta td_count
        rts
.endp

.proc open_tr
        jsr render_flush_word
        lda td_count
        beq ?first
        jsr render_newline
        jsr render_tbl_line
?first  jsr render_newline
        lda #0
        sta td_count
        rts
.endp

.proc open_td
        jsr render_flush_word
        lda td_count
        beq ?first
        lda #<m_tbl_sep
        ldx #>m_tbl_sep
        jsr render_string
?first  inc td_count
        rts
.endp

.proc open_th
        jsr render_flush_word
        lda td_count
        beq ?first
        lda #<m_tbl_sep
        ldx #>m_tbl_sep
        jsr render_string
?first  inc td_count
        lda #ATTR_H3
        jmp render_set_attr
.endp

m_tbl_sep dta c' | ',0

.proc open_bq
        jsr render_flush_word
        jsr render_newline
        lda zp_indent
        clc
        adc #2
        sta zp_indent
        rts
.endp

.proc open_dt
        jsr render_flush_word
        jsr render_newline
        lda #ATTR_H3
        jmp render_set_attr
.endp

open_dd = open_bq

.proc open_code
        lda #ATTR_DECOR
        jmp render_set_attr
.endp

.proc open_pre
        jsr render_flush_word
        jsr render_newline
        lda #1
        sta in_pre
        lda #ATTR_DECOR
        jmp render_set_attr
.endp

; ============================================================================
; Close tag handlers (extracted from old dispatch procs)
; ============================================================================

.proc close_title
        lda #0
        sta in_title
        ldx title_len
        sta title_buf,x
        rts
.endp

.proc close_skip
        lda #0
        sta zp_in_skip
        lda #PS_NORMAL
        sta zp_parse_state
        rts
.endp

close_div = open_div

.proc close_head
        lda #0
        sta zp_in_head
        rts
.endp

.proc close_table
        jsr render_flush_word
        jsr render_newline
        jsr render_tbl_line
        jmp render_newline
.endp

.proc close_bq
        jsr render_flush_word
        jsr render_newline
        lda zp_indent
        sec
        sbc #2
        bcs ?ok
        lda #0
?ok     sta zp_indent
        rts
.endp

.proc close_dd
        lda zp_indent
        sec
        sbc #2
        bcs ?ok
        lda #0
?ok     sta zp_indent
        rts
.endp

.proc close_pre
        jsr render_flush_word
        jsr render_newline
        lda #0
        sta in_pre
        lda #ATTR_NORMAL
        jmp render_set_attr
.endp

; ============================================================================
; Tag action procs (existing, open_heading modified to use current_tag_id)
; ============================================================================
.proc open_heading
        lda #0
        sta skip_to_heading
        jsr render_flush_word
        jsr render_newline
        jsr render_newline         ; blank line above heading
        lda current_tag_id
        cmp #TAG_H1
        beq ?h1
        cmp #TAG_H2
        beq ?h2
        cmp #TAG_H4
        beq ?h4
        cmp #TAG_H5
        beq ?h5
        cmp #TAG_H6
        beq ?h6
        lda #ATTR_H3
        .byte $2C              ; BIT abs - skip next 2 bytes
?h1     lda #ATTR_H1
        .byte $2C
?h2     lda #ATTR_H2
        .byte $2C
?h4     lda #ATTR_H4
        .byte $2C
?h5     lda #ATTR_H5
        .byte $2C
?h6     lda #ATTR_H6
        jmp render_set_attr
.endp

.proc open_para
        jsr render_flush_word
        jmp render_newline
.endp

.proc open_link
        jsr render_flush_word
        lda #1
        sta zp_in_link
        lda zp_link_num
        cmp #MAX_LINKS
        bcc ?in_range
        lda #MAX_LINKS-1       ; cap at 63 = last blue palette slot
?in_range
        clc
        adc #ATTR_LINK_BASE    ; attr = $20 + link_num
        jsr render_set_attr
        lda zp_link_num
        cmp #MAX_LINKS
        bcs ?no_inc            ; don't increment past MAX_LINKS
        inc zp_link_num
?no_inc rts
.endp

.proc open_ul
        lda #0
        sta zp_list_type
        lda zp_indent
        clc
        adc #2
        sta zp_indent
        rts
.endp

.proc open_ol
        lda #1
        sta zp_list_type
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
        jmp render_list_bullet
.endp

open_bold = nop_tag

.proc open_italic
        lda #ATTR_DECOR
        jmp render_set_attr
.endp

.proc close_heading
        jsr render_flush_word
        lda #ATTR_NORMAL
        jsr render_set_attr
        jmp render_newline
.endp

close_para = open_para

.proc close_link
        jsr render_flush_word
        lda #0
        sta zp_in_link
        lda #ATTR_NORMAL
        jmp render_set_attr
.endp

.proc close_list
        lda zp_indent
        sec
        sbc #2
        bcs ?ok
        lda #0
?ok     sta zp_indent
        rts
.endp

close_bold = nop_tag

.proc close_italic
        lda #ATTR_NORMAL
        jmp render_set_attr
.endp

; Aliases for identical close handlers (reset attr to normal)
close_th = close_italic
close_dt = close_italic
close_code = close_italic

; ============================================================================
; process_attr
; ============================================================================
.proc process_attr
        ; Check "href" attribute (for <a> tags)
        lda attr_name_buf
        cmp #'h'
        bne ?chk_src
        lda attr_name_buf+1
        cmp #'r'
        bne ?chk_src
        lda attr_name_buf+2
        cmp #'e'
        bne ?chk_src
        lda attr_name_buf+3
        cmp #'f'
        bne ?chk_src
        jmp store_link_url

?chk_src
        ; Check "src" attribute (for <img> tags)
        ; Must match exactly "src" (not "srcset" etc.)
        lda attr_name_buf
        cmp #'s'
        bne ?chk_id
        lda attr_name_buf+1
        cmp #'r'
        bne ?chk_id
        lda attr_name_buf+2
        cmp #'c'
        bne ?chk_id
        lda attr_name_buf+3
        bne ?chk_id            ; must be null (reject "srcset")
        jsr store_img_src
        rts

?chk_id ; Check "id" attribute (for fragment anchors)
        lda skip_to_frag
        beq ?done              ; not looking for fragment
        lda attr_name_buf
        cmp #'i'
        bne ?chk_name
        lda attr_name_buf+1
        cmp #'d'
        bne ?chk_name
        lda attr_name_buf+2
        bne ?chk_name          ; must be exactly "id"
        jmp check_frag_match

?chk_name
        ; Check "name" attribute (for fragment anchors)
        lda attr_name_buf
        cmp #'n'
        bne ?done
        lda attr_name_buf+1
        cmp #'a'
        bne ?done
        lda attr_name_buf+2
        cmp #'m'
        bne ?done
        lda attr_name_buf+3
        cmp #'e'
        bne ?done
        lda attr_name_buf+4
        bne ?done              ; must be exactly "name"
        jmp check_frag_match

?done   rts
.endp

; ============================================================================
; check_frag_match - Compare attr_val_buf against frag_buf
; If match: clear skip_to_frag (start rendering from here)
; ============================================================================
.proc check_frag_match
        ldy #0
?cmp    lda frag_buf,y
        cmp attr_val_buf,y
        bne ?done              ; mismatch
        tax                    ; Z=1 if null terminator
        beq ?match             ; both null → match!
        iny
        cpy #FRAG_BUF_SZ-1
        bne ?cmp
        rts                    ; too long, no match
?match  lda #0
        sta skip_to_frag       ; Fragment target found!
?done   rts
.endp

; ============================================================================
; Link URL storage
; ============================================================================
MAX_LINKS      = 64
LINK_URL_SIZE  = 128

; ============================================================================
; calc_link_addr - Calculate address of link_urls[A]
; Input: A = link index (0-63)
; Output: zp_tmp_ptr = address of link_urls[A] (128-byte slot)
; ============================================================================
.proc calc_link_addr
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
        rts
.endp

.proc store_link_url
        lda zp_link_num
        cmp #MAX_LINKS
        bcs ?full

        lda zp_link_num
        jsr calc_link_addr

        ldy #0
?cp     lda attr_val_buf,y
        sta (zp_tmp_ptr),y
        beq ?ok
        iny
        cpy #LINK_URL_SIZE-1
        bne ?cp
        lda #0
        sta (zp_tmp_ptr),y
?ok     ; Do NOT increment zp_link_num here - open_link does it
?full   rts
.endp

; ============================================================================
; Image source storage
; ============================================================================
IMG_SRC_SIZE = 256

.proc store_img_src
        ; Just copy attr_val_buf to img_src_buf (temp storage)
        ; Actual link storage happens in store_img_as_link when tag closes
        ldy #0
?cp     lda attr_val_buf,y
        sta img_src_buf,y
        beq ?done
        iny
        cpy #IMG_SRC_SIZE-1
        bne ?cp
        lda #0
        sta img_src_buf,y
?done   sty img_src_len
        rts
.endp

; ============================================================================
; store_img_as_link - Store IMG URL as link with "I:" prefix
; Shows [N]IMG with link color. URL stored as "I:" + img_src_buf in link_urls[]
; ============================================================================
.proc store_img_as_link
        ; Check link_num < MAX_LINKS
        lda zp_link_num
        cmp #MAX_LINKS
        bcs ?full

        lda zp_link_num
        jsr calc_link_addr

        ; Write "I:" prefix
        lda #'I'
        ldy #0
        sta (zp_tmp_ptr),y
        iny
        lda #':'
        sta (zp_tmp_ptr),y
        iny

        ; Copy img_src_buf after prefix (max 125 chars to fit in 128B slot)
        ldx #0
?cp     lda img_src_buf,x
        sta (zp_tmp_ptr),y
        beq ?ok
        iny
        inx
        cpy #LINK_URL_SIZE-1
        bne ?cp
        lda #0
        sta (zp_tmp_ptr),y

?ok     ; Show [N]IMG with link attr (attr = $20+link_num)
        lda zp_link_num
        clc
        adc #ATTR_LINK_BASE
        jsr render_set_attr
        lda #<m_imgtxt
        ldx #>m_imgtxt
        jsr render_string          ; shows "IMG"
        lda #ATTR_NORMAL
        jsr render_set_attr
        inc zp_link_num
?full   rts

m_imgtxt dta c'IMG',0
.endp

img_src_buf .ds IMG_SRC_SIZE       ; temp buffer for fetch
img_src_len dta b(0)

; Link storage is in data.asm (at $9200+ to avoid MEMAC B conflict)
