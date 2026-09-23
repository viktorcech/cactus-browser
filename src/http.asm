; ============================================================================
; HTTP Module - HTTP GET workflow
; URL utilities in url.asm
; ============================================================================

; ----------------------------------------------------------------------------
; http_download - Download URL into VRAM page buffer (Phase 1)
; Input: url_buffer, url_length set
; Output: C=0 ok (pb_total set), C=1 error
; After return: N1: is CLOSED, data is in VRAM page buffer
; ----------------------------------------------------------------------------
.proc http_download
        lda #KEY_NONE
        sta CH                 ; clear any leftover keypress
        jsr ui_status_loading
        jsr vbxe_pb_init_write
        jsr fn_open
        jcs ?open_err
        lda #1
        sta dl_active
        lda #0
        sta img_deferred
        sta http_idle_cnt
        sta http_bytes_lo
        sta http_bytes_hi
        sta http_remain_lo
        sta http_remain_hi

        ; --- Main download loop ---
        ; Read from network → rx_buffer → VRAM page buffer
?rdlp   lda http_remain_lo
        ora http_remain_hi
        bne ?do_read

        jsr fn_status
        jcs ?rd_err
        lda zp_fn_error
        beq ?no_err
        cmp #136               ; 136 ($88) = EOF (FujiNet convention: server closed)
        jeq ?done
        jmi ?rd_err
?no_err
        lda zp_fn_bytes_lo
        ora zp_fn_bytes_hi
        jeq ?no_data
        lda zp_fn_bytes_lo     ; remain = bytes waiting (already in zp_fn_bytes)
        sta http_remain_lo
        lda zp_fn_bytes_hi
        sta http_remain_hi
        jmp ?rd_go

?do_read
        lda http_remain_lo
        sta zp_fn_bytes_lo
        lda http_remain_hi
        sta zp_fn_bytes_hi
?rd_go  lda #0
        sta http_idle_cnt

        ; Read up to 2KB per SIO call into img_big_buf (8x fewer SIO
        ; transactions than the old 255-byte fn_read path — same routine
        ; the image fetcher uses; page download and image fetch never
        ; run concurrently, so sharing img_big_buf is safe)
        jsr fn_read_img
        bcc ?rd_ok
        lda #0
        sta http_remain_lo
        sta http_remain_hi
        jmp ?rd_err
?rd_ok
        ; remain -= chunk (16-bit)
        lda http_remain_lo
        sec
        sbc img_chunk_lo
        sta http_remain_lo
        lda http_remain_hi
        sbc img_chunk_hi
        sta http_remain_hi

        lda img_chunk_lo
        ora img_chunk_hi
        jeq ?rdlp
        ; Track bytes for progress display (16-bit add)
        lda http_bytes_lo
        clc
        adc img_chunk_lo
        sta http_bytes_lo
        lda http_bytes_hi
        adc img_chunk_hi
        sta http_bytes_hi
 .if 1                          ; 2026-09-23 (fix: progress after pb_total is updated)
        ; Write img_big_buf → VRAM page buffer (fast block copy)
        jsr vbxe_pb_write_big

        ; Update 24-bit total (img_chunk preserved by vbxe_pb_write_big)
        clc
        lda pb_total
        adc img_chunk_lo
        sta pb_total
        lda pb_total+1
        adc img_chunk_hi
        sta pb_total+1
        bcc ?nc_t
        inc pb_total+2
?nc_t
        jsr ui_status_progress ; shows pb_total in kB
 .else
        jsr ui_status_progress

        ; Write img_big_buf → VRAM page buffer (fast block copy)
        jsr vbxe_pb_write_big

        ; Update 24-bit total (img_chunk preserved by vbxe_pb_write_big)
        clc
        lda pb_total
        adc img_chunk_lo
        sta pb_total
        lda pb_total+1
        adc img_chunk_hi
        sta pb_total+1
        bcc ?nc_t
        inc pb_total+2
?nc_t
 .endif
 .if 1                          ; 2026-09-23 (fix: page buffer overran VRAM into bank 0)
        ; 384 kB download limit (pb_total+2 >= 6): the page buffer starts at
        ; VRAM $14000, so the last 2 KB chunk ends by $74800 < $80000. At 7
        ; a page over ~432 kB wrapped into bank 0 (screen, BCBs, XDL, font)
        lda pb_total+2
        cmp #6
        bcs ?done
 .else
        ; 400kB download limit (pb_total+2 >= 6 = 384kB+)
        lda pb_total+2
        cmp #7
        bcs ?done
 .endif

        ; Check keyboard abort: Space/Return are only cleared, any other
        ; key stops the download
        lda CH
        cmp #KEY_NONE
        jeq ?rdlp
        cmp #KEY_SPACE
        beq ?clr_dl
        cmp #KEY_RETURN
        bne ?done
?clr_dl lda #KEY_NONE
        sta CH
        jmp ?rdlp

?no_data
        lda zp_fn_connected
        beq ?done

        lda CH
        cmp #KEY_NONE
        beq ?no_key
        cmp #KEY_SPACE
        beq ?clr_sp
        cmp #KEY_RETURN
        bne ?done
?clr_sp lda #KEY_NONE
        sta CH
?no_key
        inc http_idle_cnt
        lda http_idle_cnt
        ldx is_pal
        bne ?pal_to
        cmp #250               ; NTSC: 250 frames ≈ 4.2s (longer for buffered download)
        bcc ?wait
        bcs ?done              ; always
?pal_to cmp #240               ; PAL: 240 frames ≈ 4.8s
        bcs ?done

?wait   wait_frames 1
        jeq ?rdlp              ; always (wait_frames returns Z = 1)

?done   jsr fn_close
        lda #0
        sta dl_active
        ; Check if user clicked IMG during download
        ldx img_deferred
        beq ?no_defer
        sta img_deferred       ; A = 0
        lda #KEY_NONE
        sta CH                 ; clear auto-repeat from --More--
        jsr img_fetch_single
?no_defer
        clc
        rts

?open_err
        jsr ?stop
        lda #<m_operr
        ldx #>m_operr
        bne ?show              ; always (hi byte != 0)

?rd_err lda zp_fn_error
        sta m_rderr_code
        jsr ?stop
        lda m_rderr_code
        jsr byte_to_hex
        sta m_rderr_hex
        stx m_rderr_hex+1
        lda #<m_rderr
        ldx #>m_rderr
?show   jsr ui_show_error
        sec
        rts

?stop   jsr fn_close           ; close N1:, red status bar
        lda #0
        sta dl_active
        jmp ui_status_error

 .if 1                          ; 2026-09-23 (one status bar for everything)
m_operr dta c' Connection failed - check the URL',1,c'any key',0
m_rderr dta c' Read error $'
m_rderr_hex dta c'00',1,c'any key',0
 .else
m_operr dta c'Connection failed - check URL (press key)',0
m_rderr dta c'Read err $'
m_rderr_hex dta c'00',0
 .endif
m_rderr_code dta b(0)
http_idle_cnt dta b(0)
.endp

; --- Global download state ---
; Total bytes transferred (for progress display, reset at <body>)
http_bytes_lo dta b(0)
http_bytes_hi dta b(0)
; Remaining bytes from last STATUS call (skip redundant STATUS when >0)
http_remain_lo dta b(0)
http_remain_hi dta b(0)
; Download active flag: 1=N1: open for page download, 0=closed
; Guards img_fetch_single from using N1: while page downloads
; MUST be below $4000 — MEMAC B corrupts $4000-$7FFF during VRAM ops
dl_active   dta b(0)
; Deferred image fetch: 1=user clicked IMG link during active download
; After http_download closes N1:, checks this flag and calls img_fetch_single
; MUST be below $4000 — same MEMAC B reason as dl_active
img_deferred dta b(0)

; ----------------------------------------------------------------------------
; http_render - Render HTML from VRAM page buffer (Phase 2)
; Two-phase architecture:
;   Phase 1 (http_download): network → rx_buffer → VRAM page buffer
;   Phase 2 (http_render):   VRAM page buffer → rx_buffer → html parser
; N1: is closed during Phase 2 — free for image fetches via img_fetch_single
; Input: pb_total set by http_download (24-bit byte count in VRAM)
; Reads 255-byte chunks from VRAM, feeds to html_process_chunk
; Saves VRAM read position before each chunk for rewind after img_fetch
; ----------------------------------------------------------------------------
.proc http_render
        jsr vbxe_pb_init_read

?loop   ; remaining = pb_total - pb_read (24-bit): 0 = done,
        ; chunk size = min(255, remaining)
        lda pb_total
        sec
        sbc pb_read
        tay                    ; Y = low byte of remaining
        lda pb_total+1
        sbc pb_read+1
        tax                    ; X = middle byte
        lda pb_total+2
        sbc pb_read+2
        bne ?full              ; remaining > 255 -> cap at 255
        txa
        bne ?full
        tya                    ; exact remaining count
        beq ?done              ; all read
        bne ?read              ; always
?full   lda #255               ; cap at 255

?read   ; Save VRAM read state before chunk (for rewind after img_fetch)
        sta pb_chunk_size
        tax
        lda pb_rd_bank
        sta pb_rd_save_bank
        lda zp_pb_rd_ptr
        sta pb_rd_save_lo
        lda zp_pb_rd_ptr+1
        sta pb_rd_save_hi

        txa                    ; = pb_chunk_size
        jsr vbxe_pb_read_chunk ; A→rx_buffer, sets zp_rx_len
        jsr html_process_chunk

        ; Update 24-bit read counter (use saved chunk size, not zp_rx_len
        ; which may have been reset to 0 by img_fetch during render)
        clc
        lda pb_read
        adc pb_chunk_size
        sta pb_read
        bcc ?nc1
        inc pb_read+1
        bne ?nc1
        inc pb_read+2
?nc1
        lda page_abort
        jeq ?loop

?done   jmp html_flush

pb_chunk_size    dta b(0)       ; bytes in current chunk (for 24-bit read counter)
pb_rd_save_bank  dta b(0)       ; VRAM read state saved before each chunk
pb_rd_save_lo    dta b(0)       ; (allows rewind after img_fetch destroys rx_buffer)
pb_rd_save_hi    dta b(0)
.endp

; ----------------------------------------------------------------------------
; http_navigate - Navigate: reset parser, fetch, render
; Input: url_buffer already set
; ----------------------------------------------------------------------------
.proc http_navigate
        jsr http_extract_frag   ; strip #fragment, set skip_to_frag
        jsr http_ensure_prefix
        jsr http_url_tolower
        jsr http_save_base
        ; Check if URL points to an image file BEFORE proxy
        ; (proxy would wrap URL, breaking image extension detection)
        jsr http_check_img_ext
        bcc ?not_img
        ; Image URL: copy to img_src_buf (strip N: prefix) and fetch
        ldy #0
        lda url_buffer
        cmp #'N'
        bne ?ci_nb
        lda url_buffer+1
        cmp #':'
        bne ?ci_nb
        ldy #2
?ci_nb  ldx #0
?ci_cp  lda url_buffer,y
        sta img_src_buf,x
        beq ?ci_go
        iny
        inx
        cpx #IMG_SRC_SIZE-1
        bne ?ci_cp
        lda #0
        sta img_src_buf,x
?ci_go  jmp img_fetch_single

?not_img
        ; Check for unsupported binary file types
        jsr http_check_binary_ext
        bcc ?not_bin
        ldy #COL_RED
        lda #<m_unsupported
        ldx #>m_unsupported
        jmp status_msg_sub
?not_bin
        ; Snapshot clean URL (pre-proxy, without N: prefix) for the
        ; bookmarks window 'A' = add current page
        ldy #0
        lda url_buffer
        cmp #'n'               ; http_url_tolower already ran
        bne ?cu_nb
        lda url_buffer+1
        cmp #':'
        bne ?cu_nb
        ldy #2                 ; skip "n:" prefix
?cu_nb  ldx #0
?cu_cp  lda url_buffer,y
        sta cur_page_url,x
        beq ?cu_d
        iny
        inx
        cpx #BK_SLOT_SZ-1
        bne ?cu_cp
        lda #0
        sta cur_page_url,x
?cu_d
        jsr http_apply_proxy
        ; Hide previous image if active
        lda img_active
        beq ?noimg
        jsr vbxe_img_hide
?noimg  jsr html_reset
        jsr render_reset
        jsr ui_clear_content
        jsr ui_show_url

        jsr http_download      ; Phase 1: network → VRAM buffer
        bcs ?skip_render       ; error → skip render

        ; Check if any data was received
        lda pb_total
        ora pb_total+1
        ora pb_total+2
        bne ?has_data
        ; No data → show error
        lda #<m_nodata
        ldx #>m_nodata
        jsr ui_show_error
        jmp ui_status_end

?has_data
        lda #0
        sta page_abort         ; reset abort flag for render phase
        jsr http_render        ; Phase 2: VRAM buffer → parser

        ; If user pressed Q during render, return to welcome screen
        ; But if pending_link is set, it's a link click — not quit!
        lda page_abort
        beq ?skip_render       ; no abort → show "End" status normally
        lda pending_link
        cmp #$FF
        bne ?skip_render       ; link click → let ui_main_loop follow it
        jsr fn_close
        jsr html_reset
        jsr render_reset
        jmp show_welcome

?skip_render
        jmp ui_status_end

 .if 1                          ; 2026-09-23 (one status bar for everything)
m_nodata dta c' Empty response - check the URL',1,c'any key',0
m_unsupported dta c' File type not supported',0
 .else
m_nodata dta c'Empty response - check URL (press key)',0
m_unsupported dta c'File type not supported (press key)',0
 .endif
.endp
