; ============================================================================
; URL Utilities - resolve, prefix, lowercase, image extension check
; ============================================================================

; ----------------------------------------------------------------------------
; http_ensure_prefix - Add "N:http://" to url_buffer if missing
; ----------------------------------------------------------------------------
.proc http_ensure_prefix
        ; Check if url_buffer starts with "N:" (already has FujiNet prefix)
        lda url_buffer
        cmp #'N'
        beq ?chkcolon
        cmp #'n'
        bne ?chkhttp
?chkcolon
        lda url_buffer+1
        cmp #':'
        beq ?ok
?chkhttp
        ; Check if starts with "http" - need to prepend "N:" only
        lda url_buffer
        cmp #'h'
        beq ?addN
        cmp #'H'
        beq ?addN
        jmp ?addFull

        ; Has "http://..." but missing "N:" - shift by 2 and prepend "N:"
?addN   ldy url_length
        cpy #URL_BUF_SIZE-3
        bcc ?sh2
        ldy #URL_BUF_SIZE-3
?sh2    clc
        tya
        adc #2
        tax
        stx url_length
?sh2lp  dex
        dey
        bmi ?cp2
        lda url_buffer,y
        sta url_buffer,x
        jmp ?sh2lp
?cp2    lda #'N'
        sta url_buffer
        lda #':'
        sta url_buffer+1
        ldy url_length
        lda #0
        sta url_buffer,y
        jmp ?ok

?addFull
        ; No http prefix - shift buffer right by 9 and prepend "N:http://"
        ldy url_length
        cpy #URL_BUF_SIZE-10
        bcc ?shift
        ldy #URL_BUF_SIZE-10
?shift
        clc
        tya
        adc #9
        tax                     ; X = new end position
        stx url_length
?shlp   dex
        dey
        bmi ?copy
        lda url_buffer,y
        sta url_buffer,x
        jmp ?shlp

?copy   ; Copy "N:http://" to start
        ldx #0
?cplp   lda ?prefix,x
        sta url_buffer,x
        inx
        cpx #9
        bne ?cplp
        ; Null-terminate
        ldy url_length
        lda #0
        sta url_buffer,y
?ok     rts

?prefix dta c'N:http://'
.endp

; ----------------------------------------------------------------------------
; http_save_base - Save current url_buffer as base URL (up to last '/')
; Call BEFORE overwriting url_buffer with a new link URL
; ----------------------------------------------------------------------------
.proc http_save_base
        ; Find last '/' in url_buffer, but ignore "://" slashes
        ; Strategy: find position after "://", then last '/' after that
        ldy #0
        sty zp_tmp1            ; zp_tmp1 = index after last path '/'
        sty zp_tmp2            ; zp_tmp2 = position after "://"

        ; First find "://" to know where host starts
?find_scheme
        lda url_buffer,y
        beq ?check
        cmp #':'
        bne ?fs_next
        ; Check if followed by "//"
        iny
        lda url_buffer,y
        cmp #'/'
        bne ?fs_next
        iny
        lda url_buffer,y
        cmp #'/'
        bne ?fs_next
        iny                    ; Y = position after "://"
        sty zp_tmp2
        jmp ?scan_path
?fs_next
        iny
        bne ?find_scheme

?scan_path
        ; Now scan for '/' in the path portion (after host)
        lda url_buffer,y
        beq ?check
        cmp #'/'
        bne ?sp_next
        iny
        sty zp_tmp1            ; save position after this '/'
        dey
?sp_next
        iny
        bne ?scan_path

?check  ; If no path '/' found (zp_tmp1 <= zp_tmp2), use whole URL + "/"
        lda zp_tmp1
        cmp zp_tmp2
        bcc ?use_all
        beq ?use_all
        ; Good - copy up to last path '/'
        jmp ?copy

?use_all
        ; No path slash - copy whole URL and append "/"
        ldy #0
?ua     lda url_buffer,y
        beq ?ua_slash
        sta base_url,y
        iny
        bne ?ua
?ua_slash
        lda #'/'
        sta base_url,y
        iny
        lda #0
        sta base_url,y
        rts

?copy   ; Copy url_buffer[0..zp_tmp1-1] to base_url
        ldy #0
?cplp   cpy zp_tmp1
        beq ?term
        lda url_buffer,y
        sta base_url,y
        iny
        bne ?cplp
?term   lda #0
        sta base_url,y
        rts
.endp

; ----------------------------------------------------------------------------
; http_resolve_url - Resolve relative URL in url_buffer against base_url
; Absolute URLs (http://...) pass through unchanged
; Relative URLs get base_url prepended
; ----------------------------------------------------------------------------
.proc http_resolve_url
        ; Check if already absolute: must start with "http" or "N:"
        lda url_buffer
        cmp #'N'
        bne ?not_n
        lda url_buffer+1
        cmp #':'
        beq ?done              ; "N:..." = absolute
?not_n  lda url_buffer
        cmp #'h'
        beq ?chk_http
        cmp #'H'
        beq ?chk_http
        jmp ?not_abs
?chk_http
        lda url_buffer+1
        cmp #'t'
        bne ?not_abs
        lda url_buffer+2
        cmp #'t'
        bne ?not_abs
        lda url_buffer+3
        cmp #'p'
        beq ?done              ; "http..." = absolute
?not_abs

        ; Check if root-relative (starts with '/')
        cmp #'/'
        beq ?root_rel

        ; --- Relative URL: prepend base_url ---
        ; Step 1: copy url_buffer to rx_buffer (temp)
        ldy #0
?s1     lda url_buffer,y
        sta rx_buffer,y
        beq ?s1d
        iny
        bne ?s1
?s1d
        ; Step 2: copy base_url to url_buffer
        ldy #0
?s2     lda base_url,y
        beq ?s2d
        sta url_buffer,y
        iny
        bne ?s2
?s2d    ; Y = length of base_url
        ; Step 3: append relative URL from rx_buffer
        ldx #0
?s3     lda rx_buffer,x
        sta url_buffer,y
        beq ?upd
        iny
        inx
        cpy #URL_BUF_SIZE-1
        bne ?s3
        lda #0
        sta url_buffer,y
?upd    sty url_length
?done   rts

?root_rel
        ; Root-relative: find host part in base_url
        ; Look for "://" then the next "/" after that
        ldy #0
?rr1    lda base_url,y
        beq ?rr_use_all        ; no "://" found, use whole base
        cmp #':'
        bne ?rr1n
        iny
        lda base_url,y
        cmp #'/'
        bne ?rr1n
        iny
        lda base_url,y
        cmp #'/'
        beq ?rr_found_scheme
        dey
?rr1n   iny
        bne ?rr1

?rr_found_scheme
        ; Y points to 2nd '/' of "://", skip to find host end
        iny                    ; skip past "//"
?rr2    lda base_url,y
        beq ?rr_host_end       ; end of base = host only, no path
        cmp #'/'
        beq ?rr_host_end
        iny
        bne ?rr2

?rr_host_end
        ; Y = position of '/' after host (or end of string)
        sty zp_tmp1

        ; Save original url_buffer to rx_buffer
        ldy #0
?rr3    lda url_buffer,y
        sta rx_buffer,y
        beq ?rr3d
        iny
        bne ?rr3
?rr3d
        ; Copy host part of base_url
        ldy #0
?rr4    cpy zp_tmp1
        beq ?rr4d
        lda base_url,y
        sta url_buffer,y
        iny
        bne ?rr4
?rr4d
        ; Append root-relative path from rx_buffer
        ldx #0
?rr5    lda rx_buffer,x
        sta url_buffer,y
        beq ?rr_upd
        iny
        inx
        cpy #URL_BUF_SIZE-1
        bne ?rr5
        lda #0
        sta url_buffer,y
?rr_upd sty url_length
        rts

?rr_use_all
        ; Fallback: use whole base_url + url_buffer
        jmp ?s1                ; treat as relative
.endp

; ----------------------------------------------------------------------------
; http_check_img_ext - Check if url_buffer ends with image extension
; Output: C=1 if image (.png, .jpg, .gif), C=0 if not
; ----------------------------------------------------------------------------
.proc http_check_img_ext
        ; Find last '.' in URL
        ldy #0
        ldx #$FF               ; X = position of last dot ($FF=none)
?scan   lda url_buffer,y
        beq ?check
        cmp #'.'
        bne ?next
        tya
        tax                    ; X = dot position
?next   iny
        bne ?scan
?check  cpx #$FF
        bne ?has_dot
        clc
        rts                    ; no dot found
?has_dot
        ; Y = end of URL, X = last dot
        ; Compare extension (after dot) against known types
        inx                    ; X = first char after dot
        lda url_buffer,x
        jsr to_lower
        cmp #'p'
        beq ?p
        cmp #'j'
        beq ?j
        cmp #'g'
        beq ?g
        jmp ?no
?p      ; "png"
        inx
        lda url_buffer,x
        jsr to_lower
        cmp #'n'
        bne ?no
        inx
        lda url_buffer,x
        jsr to_lower
        cmp #'g'
        bne ?no
        inx
        lda url_buffer,x
        beq ?yes               ; null after "png" = match
        jmp ?no
?j      ; "jpg" or "jpeg"
        inx
        lda url_buffer,x
        jsr to_lower
        cmp #'p'
        bne ?no
        inx
        lda url_buffer,x
        jsr to_lower
        cmp #'g'
        bne ?je
        inx
        lda url_buffer,x
        beq ?yes               ; null after "jpg" = match
        jmp ?no
?je     cmp #'e'               ; jpeg
        bne ?no
        inx
        lda url_buffer,x
        jsr to_lower
        cmp #'g'
        bne ?no
        inx
        lda url_buffer,x
        beq ?yes
        jmp ?no
?g      ; "gif"
        inx
        lda url_buffer,x
        jsr to_lower
        cmp #'i'
        bne ?no
        inx
        lda url_buffer,x
        jsr to_lower
        cmp #'f'
        bne ?no
        inx
        lda url_buffer,x
        beq ?yes               ; null after "gif" = match
?no     clc
        rts
?yes    sec
        rts
.endp

; ----------------------------------------------------------------------------
; http_check_binary_ext - Check if url_buffer ends with unsupported extension
; Output: C=1 if binary (pdf, doc, zip, etc.), C=0 if ok
; ----------------------------------------------------------------------------
.proc http_check_binary_ext
        ; Find last '.' in URL
        ldy #0
        ldx #$FF
?scan   lda url_buffer,y
        beq ?check
        cmp #'.'
        bne ?next
        tya
        tax
?next   iny
        bne ?scan
?check  cpx #$FF
        bne ?has_dot
        clc
        rts
?has_dot
        inx                    ; X = first char after dot
        ; Store ext start position
        stx zp_tmp1

        ; Compare against blocked extensions table
        ; Table format: null-terminated strings, double null = end
        ldx #0
?tloop  lda bin_ext_tbl,x
        beq ?no                ; double null = end of table
        ldy zp_tmp1           ; Y = url ext start
?tcmp   lda bin_ext_tbl,x
        beq ?tend              ; end of table entry
        pha
        lda url_buffer,y
        jsr to_lower
        sta zp_tmp2
        pla
        cmp zp_tmp2
        bne ?tskip
        inx
        iny
        jmp ?tcmp
?tend   ; Table entry ended — check URL ext also ended
        lda url_buffer,y
        beq ?yes               ; both ended = match!
?tskip  ; Skip to next entry (find next null)
        lda bin_ext_tbl,x
        beq ?tnxt
        inx
        jmp ?tskip
?tnxt   inx                    ; skip the null
        jmp ?tloop
?no     clc
        rts
?yes    sec
        rts

bin_ext_tbl
        dta c'pdf',0
        dta c'doc',0
        dta c'docx',0
        dta c'xls',0
        dta c'xlsx',0
        dta c'zip',0
        dta c'rar',0
        dta c'7z',0
        dta c'exe',0
        dta c'mp3',0
        dta c'mp4',0
        dta c'avi',0
        dta c'mov',0
        dta c'wmv',0
        dta c'mkv',0
        dta c'flv',0
        dta c'wav',0
        dta c'flac',0
        dta c'ogg',0
        dta c'ppt',0
        dta c'pptx',0
        dta c'tar',0
        dta c'gz',0
        dta c'iso',0
        dta c'bin',0
        dta c'apk',0
        dta c'dmg',0
        dta c'swf',0
        dta b(0)               ; end of table
.endp

; ----------------------------------------------------------------------------
; http_url_tolower - Convert DOMAIN part of url_buffer to lowercase
; Only lowercases up to first '/' after "://" (path is case-sensitive!)
; ----------------------------------------------------------------------------
.proc http_url_tolower
        ldy #0
        ; Find "://" first
?fs     lda url_buffer,y
        beq ?done
        cmp #':'
        bne ?fs_n
        iny
        lda url_buffer,y
        cmp #'/'
        bne ?fs_n
        iny
        lda url_buffer,y
        cmp #'/'
        beq ?found
        dey
?fs_n   iny
        bne ?fs
        rts                    ; no "://" found, don't touch
?found  iny                    ; skip past "//"
        ; Lowercase until end of domain (next '/' or end)
?lp     lda url_buffer,y
        beq ?done
        cmp #'/'
        beq ?done              ; reached path, stop lowercasing
        cmp #'A'
        bcc ?next
        cmp #'Z'+1
        bcs ?next
        ora #$20
        sta url_buffer,y
?next   iny
        bne ?lp
?done   rts
.endp

; ----------------------------------------------------------------------------
; nibble_to_hex - Convert low nibble (0-15) in A to ASCII hex char
; Input: A = 0-15. Output: A = '0'-'9' or 'A'-'F'
; Note: exploits carry from CMP: C=1 when A>=10, C=0 when A<10
; ----------------------------------------------------------------------------
.proc nibble_to_hex
        cmp #10
        bcc ?dig
        adc #'A'-11          ; C=1 from CMP, so adds 'A'-10
        rts
?dig    adc #'0'             ; C=0 from CMP, so adds '0'
        rts
.endp

; ----------------------------------------------------------------------------
; Proxy mode
; ----------------------------------------------------------------------------
use_proxy  dta b(0)           ; 0=direct, 1=proxy

; ----------------------------------------------------------------------------
; http_apply_proxy - Wrap url_buffer with proxy prefix
; Only called when use_proxy=1. Strips N: and http:// from original URL,
; builds: N:https://turiecfoto.sk/proxy.php?url= + bare_url
; ----------------------------------------------------------------------------
.proc http_apply_proxy
        lda use_proxy
        bne ?go
        rts
?go
        ; Skip if URL already points to our server (proxy or search)
        ; Check for "turiecfoto" substring in first 60 chars
        ldy #0
?chk    lda url_buffer,y
        beq ?ok                ; end of string, not found - proceed
        cmp #'t'
        bne ?cn
        lda url_buffer+1,y
        cmp #'u'
        bne ?cn
        lda url_buffer+2,y
        cmp #'r'
        bne ?cn
        lda url_buffer+3,y
        cmp #'i'
        bne ?cn
        rts                    ; "turi" found - our server, skip proxy
?cn     iny
        cpy #60
        bne ?chk
?ok
        ; Find start of bare URL (skip N: and http://)
        ldy #0
        lda url_buffer
        cmp #'N'
        bne ?bare
        lda url_buffer+1
        cmp #':'
        bne ?bare
        ldy #2                 ; skip "N:"
        lda url_buffer+2
        cmp #'h'
        bne ?bare
        lda url_buffer+6
        cmp #'/'
        bne ?bare
        ldy #9                 ; skip "N:http://"
        ; Check for https (extra s)
        lda url_buffer+5
        cmp #'s'
        bne ?bare
        iny                    ; skip "N:https://"

?bare   ; Y = start of bare URL in url_buffer
        ; Copy bare URL to rx_buffer (temp)
        ldx #0
?cp1    lda url_buffer,y
        sta rx_buffer,x
        beq ?cp1d
        iny
        inx
        cpx #200
        bne ?cp1
        lda #0
        sta rx_buffer,x
?cp1d
        ; Copy proxy prefix to url_buffer
        ldy #0
?pfx    lda proxy_prefix,y
        beq ?pfxd
        sta url_buffer,y
        iny
        bne ?pfx
?pfxd   ; Y = length of prefix
        ; Append bare URL from rx_buffer
        ldx #0
?cp2    lda rx_buffer,x
        sta url_buffer,y
        beq ?upd
        iny
        inx
        cpy #URL_BUF_SIZE-1
        bne ?cp2
        lda #0
        sta url_buffer,y
?upd    sty url_length
?done   rts

.endp

proxy_prefix dta c'N:https://turiecfoto.sk/proxy.php?url=',0

; ----------------------------------------------------------------------------
; url_build_search - Convert search query in url_buffer to search URL
; Input: url_buffer = "search terms", url_length = length
; Output: url_buffer = "turiecfoto.sk/search.php?q=search+terms"
; Note: http_ensure_prefix will add "N:http://" later
; ----------------------------------------------------------------------------
.proc url_build_search
        ; Copy query from url_buffer to rx_buffer (temp)
        ldy #0
?cp1    lda url_buffer,y
        sta rx_buffer,y
        beq ?cp1d
        iny
        cpy #200
        bne ?cp1
        lda #0
        sta rx_buffer,y
?cp1d
        ; Copy search prefix to url_buffer
        ldy #0
?pfx    lda search_prefix,y
        beq ?pfxd
        sta url_buffer,y
        iny
        bne ?pfx
?pfxd   ; Y = length of prefix
        ; Append query from rx_buffer, encoding spaces as '+'
        ldx #0
?cp2    lda rx_buffer,x
        beq ?done
        cmp #' '
        bne ?nosp
        lda #'+'
?nosp   sta url_buffer,y
        iny
        inx
        cpy #URL_BUF_SIZE-1
        bne ?cp2
?done   lda #0
        sta url_buffer,y
        sty url_length
        rts
.endp

search_prefix dta c'turiecfoto.sk/search.php?q=',0

; ----------------------------------------------------------------------------
; http_extract_frag - Extract #fragment from url_buffer
; Sets skip_to_frag=1 and fills frag_buf if '#' found
; Strips '#...' from url_buffer (server doesn't need it)
; ----------------------------------------------------------------------------
.proc http_extract_frag
        lda #0
        sta skip_to_frag
        ldy #0
?scan   lda url_buffer,y
        beq ?done              ; no fragment found
        cmp #'#'
        beq ?found
        iny
        bne ?scan
?done   rts
?found  ; Null-terminate URL at '#'
        lda #0
        sta url_buffer,y
        sty url_length
        ; Copy fragment (after '#') to frag_buf
        iny                    ; skip '#'
        ldx #0
?cp     lda url_buffer,y
        sta frag_buf,x
        beq ?set               ; null terminator copied
        iny
        inx
        cpx #FRAG_BUF_SZ-1
        bne ?cp
        lda #0
        sta frag_buf,x         ; force null-terminate
?set    lda #1
        sta skip_to_frag
        rts
.endp
