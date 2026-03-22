; ============================================================================
; HTML Tag Handlers - open/close tag actions, attribute processing, link storage
; ============================================================================

; ============================================================================
; process_tag - Handle parsed tag (split into open/close sub-procs)
; ============================================================================
.proc process_tag
        jsr lookup_tag

        ; In skip mode (script/style), only process their
        ; closing tags - ignore everything else inside the block
        ldx zp_in_skip
        beq ?not_skip
        ldx is_closing
        beq ?skip_ret
        cmp #TAG_SCRIPT
        beq ?cls
        cmp #TAG_STYLE
        beq ?cls
?skip_ret rts
?cls    lda #0
        sta zp_in_skip
        rts

?not_skip
        ; In <head> mode - only process head-related tags
        ; If a known content tag appears, auto-clear head mode
        ; (safety for pages without explicit <body>)
        ldx zp_in_head
        beq ?full
        cmp #TAG_TITLE
        beq ?full
        cmp #TAG_SCRIPT
        beq ?full
        cmp #TAG_STYLE
        beq ?full
        cmp #TAG_HEAD
        beq ?full
        cmp #TAG_BODY
        beq ?full
        cmp #TAG_UNKNOWN
        beq ?skip_in_head     ; meta/link etc. - ignore in head
        ; Known content tag (p, div, h1...) - page has no <body>
        pha
        lda #0
        sta zp_in_head
        pla
        jmp ?full
?skip_in_head rts

?full   ldx is_closing
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
        cmp #TAG_NOSCRIPT
        beq ?onoscript
        cmp #TAG_HEAD
        beq ?ohead
        cmp #TAG_BODY
        beq ?obody
        jmp open_tag_tbl

?otitle jsr render_flush_word
        lda #1
        sta in_title
        rts
?oskip  lda #1
        sta zp_in_skip
        rts
?onoscript rts                 ; show noscript content (we don't run JS)
?ohead  lda #1
        sta zp_in_head
        rts
?obody  lda #0
        sta zp_in_head         ; clear head skip on <body>
        sta http_bytes_lo      ; reset download counter so limit
        sta http_bytes_hi      ; applies to body content only
        rts
?oimg   jsr render_flush_word
        lda img_src_len
        beq ?nourl
        jsr store_img_as_link
?nourl  rts
?ohr    jsr render_flush_word
        jsr render_newline
        jsr render_hr_line
        jsr render_newline
        rts
?odiv   jsr render_flush_word
        ; Only line-break if we have content on current line
        ; (avoids blank line spam from deeply nested divs)
        lda zp_render_col
        beq ?dskip
        jsr render_do_nl
?dskip  rts
.endp

; Remaining close tag checks
.proc close_tag_more
        beq ?ctitle
        cmp #TAG_SCRIPT
        beq ?cskip
        cmp #TAG_STYLE
        beq ?cskip
        cmp #TAG_NOSCRIPT
        beq ?cnoscript
        cmp #TAG_HEAD
        beq ?chead
        cmp #TAG_DIV
        beq ?cdiv
        jmp close_tag_tbl

?ctitle lda #0
        sta in_title
        ldx title_len
        sta title_buf,x        ; null-terminate title
        rts
?cskip  lda #0
        sta zp_in_skip
        lda #PS_NORMAL
        sta zp_parse_state
        rts
?cnoscript rts                 ; noscript close - nothing to do
?chead  lda #0
        sta zp_in_head
        rts
?cdiv   jsr render_flush_word
        lda zp_render_col
        beq ?dskip
        jsr render_do_nl
?dskip  rts
.endp

; --- Table, blockquote, dt/dd, code, pre open tags ---
.proc open_tag_tbl
        cmp #TAG_TABLE
        beq ?otable
        cmp #TAG_TR
        beq ?otr
        cmp #TAG_TD
        beq ?otd
        cmp #TAG_TH
        beq ?oth
        cmp #TAG_BLOCKQUOTE
        beq ?obq
        cmp #TAG_DT
        beq ?odt
        cmp #TAG_DD
        beq ?odd
        cmp #TAG_CODE
        beq ?ocode
        cmp #TAG_PRE
        beq ?opre
        rts

?otable jsr render_flush_word
        jsr render_newline
        lda #0
        sta td_count
        rts
?otr    jsr render_flush_word
        jsr render_newline
        lda #0
        sta td_count
        rts
?otd    jsr render_flush_word
        lda td_count
        beq ?td_first
        lda #<m_tbl_sep
        ldx #>m_tbl_sep
        jsr render_string
?td_first
        inc td_count
        rts
?oth    jsr render_flush_word
        lda td_count
        beq ?th_first
        lda #<m_tbl_sep
        ldx #>m_tbl_sep
        jsr render_string
?th_first
        inc td_count
        lda #ATTR_H3
        jsr render_set_attr
        rts
?obq    jsr render_flush_word
        jsr render_newline
        lda zp_indent
        clc
        adc #2
        sta zp_indent
        rts
?odt    jsr render_flush_word
        jsr render_newline
        lda #ATTR_H3
        jsr render_set_attr
        rts
?odd    jsr render_flush_word
        jsr render_newline
        lda zp_indent
        clc
        adc #2
        sta zp_indent
        rts
?ocode  lda #ATTR_DECOR
        jsr render_set_attr
        rts
?opre   jsr render_flush_word
        jsr render_newline
        lda #ATTR_DECOR
        jsr render_set_attr
        rts

m_tbl_sep dta c' | ',0
.endp

; --- Table, blockquote, dt/dd, code, pre close tags ---
.proc close_tag_tbl
        cmp #TAG_TABLE
        beq ?ctable
        cmp #TAG_TH
        beq ?cth
        cmp #TAG_BLOCKQUOTE
        beq ?cbq
        cmp #TAG_DT
        beq ?cdt
        cmp #TAG_DD
        beq ?cdd
        cmp #TAG_CODE
        beq ?ccode
        cmp #TAG_PRE
        beq ?cpre
        rts

?ctable jsr render_flush_word
        jsr render_newline
        rts
?cth    lda #ATTR_NORMAL
        jsr render_set_attr
        rts
?cbq    jsr render_flush_word
        jsr render_newline
        lda zp_indent
        sec
        sbc #2
        bcs ?bq_ok
        lda #0
?bq_ok  sta zp_indent
        rts
?cdt    lda #ATTR_NORMAL
        jsr render_set_attr
        rts
?cdd    lda zp_indent
        sec
        sbc #2
        bcs ?dd_ok
        lda #0
?dd_ok  sta zp_indent
        rts
?ccode  lda #ATTR_NORMAL
        jsr render_set_attr
        rts
?cpre   jsr render_flush_word
        jsr render_newline
        lda #ATTR_NORMAL
        jsr render_set_attr
        rts
.endp

; Tag action procs
.proc open_heading
        ; Clear skip-to-heading flag when heading found
        pha
        lda #0
        sta skip_to_heading
        pla
        pha
        jsr render_flush_word
        jsr render_newline
        lda #1
        sta zp_in_heading
        pla
        cmp #TAG_H1
        beq ?h1
        cmp #TAG_H2
        beq ?h2
        lda #ATTR_H3
        jmp ?set
?h1     lda #ATTR_H1
        jmp ?set
?h2     lda #ATTR_H2
?set    jsr render_set_attr
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
        lda zp_link_num
        cmp #MAX_LINKS
        bcc ?in_range
        lda #MAX_LINKS-1       ; cap at 63 = last blue palette slot
?in_range
        clc
        adc #ATTR_LINK_BASE    ; attr = $20 + link_num
        jsr render_set_attr
        jsr render_link_prefix
        lda zp_link_num
        cmp #MAX_LINKS
        bcs ?no_inc            ; don't increment past MAX_LINKS
        inc zp_link_num
?no_inc rts
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
        jsr store_link_url
        rts

?chk_src
        ; Check "src" attribute (for <img> tags)
        ; Must match exactly "src" (not "srcset" etc.)
        lda attr_name_buf
        cmp #'s'
        bne ?done
        lda attr_name_buf+1
        cmp #'r'
        bne ?done
        lda attr_name_buf+2
        cmp #'c'
        bne ?done
        lda attr_name_buf+3
        bne ?done              ; must be null (reject "srcset")
        jsr store_img_src
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
        jsr render_link_prefix     ; shows [N]
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
