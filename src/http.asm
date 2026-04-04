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
        bcc ?opened
        jmp ?open_err
?opened
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
        bcc ?st_ok
        jmp ?rd_err
?st_ok
        lda zp_fn_error
        beq ?no_err
        cmp #136               ; 136 ($88) = EOF (FujiNet convention: server closed)
        beq ?jdone
        bmi ?jrd_err
        jmp ?no_err
?jdone  jmp ?done
?jrd_err jmp ?rd_err
?no_err
        lda zp_fn_bytes_lo
        ora zp_fn_bytes_hi
        bne ?has_data
        jmp ?no_data
?has_data
        lda zp_fn_bytes_lo
        sta http_remain_lo
        lda zp_fn_bytes_hi
        sta http_remain_hi

?do_read
        lda #0
        sta http_idle_cnt
        lda http_remain_lo
        sta zp_fn_bytes_lo
        lda http_remain_hi
        sta zp_fn_bytes_hi

        jsr fn_read
        bcc ?rd_ok
        lda #0
        sta http_remain_lo
        sta http_remain_hi
        jmp ?rd_err
?rd_ok
        lda http_remain_lo
        sec
        sbc zp_rx_len
        sta http_remain_lo
        bcs ?no_borrow
        dec http_remain_hi
?no_borrow

        lda zp_rx_len
        beq ?rdlp

        ; Track bytes for progress display
        lda http_bytes_lo
        clc
        adc zp_rx_len
        sta http_bytes_lo
        bcc ?no_ov
        inc http_bytes_hi
?no_ov  jsr ui_status_progress

        ; Write rx_buffer → VRAM page buffer
        jsr vbxe_pb_write_chunk

        ; Update 24-bit total
        clc
        lda pb_total
        adc zp_rx_len
        sta pb_total
        bcc ?nc_t
        inc pb_total+1
        bne ?nc_t
        inc pb_total+2
?nc_t
        ; 400kB download limit (pb_total+2 >= 6 = 384kB+)
        lda pb_total+2
        cmp #7
        bcs ?done

        ; Check keyboard abort
        lda CH
        cmp #KEY_NONE
        bne ?chk_key
        jmp ?rdlp
?chk_key
        cmp #KEY_SPACE
        beq ?clr_dl
        cmp #KEY_RETURN
        beq ?clr_dl
        jmp ?done              ; any other key = stop download
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
        beq ?clr_sp
        jmp ?done
?clr_sp lda #KEY_NONE
        sta CH
?no_key
        inc http_idle_cnt
        lda http_idle_cnt
        ldx is_pal
        bne ?pal_to
        cmp #250               ; NTSC: 250 frames ≈ 4.2s (longer for buffered download)
        bcs ?done
        bcc ?wait
?pal_to cmp #240               ; PAL: 240 frames ≈ 4.8s
        bcs ?done

?wait   wait_frames 1
        jmp ?rdlp

?done   jsr fn_close
        lda #0
        sta dl_active
        ; Check if user clicked IMG during download
        lda img_deferred
        beq ?no_defer
        lda #0
        sta img_deferred
        lda #KEY_NONE
        sta CH                 ; clear auto-repeat from --More--
        jsr img_fetch_single
?no_defer
        clc
        rts

?open_err
        jsr fn_close
        lda #0
        sta dl_active
        jsr ui_status_error
        lda #<m_operr
        ldx #>m_operr
        jsr ui_show_error
        sec
        rts

?rd_err lda zp_fn_error
        sta m_rderr_code
        jsr fn_close
        lda #0
        sta dl_active
        jsr ui_status_error
        lda m_rderr_code
        lsr
        lsr
        lsr
        lsr
        jsr nibble_to_hex
        sta m_rderr_hex
        lda m_rderr_code
        and #$0F
        jsr nibble_to_hex
        sta m_rderr_hex+1
        lda #<m_rderr
        ldx #>m_rderr
        jsr ui_show_error
        sec
        rts

m_operr dta c'Connection failed - check URL (press key)',0
m_rderr dta c'Read err $'
m_rderr_hex dta c'00',0
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

?loop   ; Check if all data read: pb_read == pb_total?
        lda pb_read+2
        cmp pb_total+2
        bne ?more
        lda pb_read+1
        cmp pb_total+1
        bne ?more
        lda pb_read
        cmp pb_total
        beq ?done

?more   ; Determine chunk size: min(255, bytes_left)
        ; 24-bit subtraction: remaining = pb_total - pb_read
        lda pb_total
        sec
        sbc pb_read
        pha                    ; save low byte of remaining
        lda pb_total+1
        sbc pb_read+1
        tax                    ; X = middle byte of remaining
        lda pb_total+2
        sbc pb_read+2          ; A = high byte of remaining
        ; If high or middle byte > 0, remaining > 255 -> cap at 255
        bne ?full              ; high byte > 0
        txa
        bne ?full              ; middle byte > 0
        ; Remaining fits in low byte (0-255)
        pla                    ; A = exact remaining count
        jmp ?read

?full   pla                    ; discard saved low byte
        lda #255               ; cap at 255

?read   ; Save VRAM read state before chunk (for rewind after img_fetch)
        sta pb_chunk_size
        lda pb_rd_bank
        sta pb_rd_save_bank
        lda zp_pb_rd_ptr
        sta pb_rd_save_lo
        lda zp_pb_rd_ptr+1
        sta pb_rd_save_hi

        lda pb_chunk_size
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
        bne ?done
        jmp ?loop

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
        status_msg COL_RED, m_unsupported
        rts
?not_bin
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
        jmp ?skip_render

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

m_nodata dta c'Empty response - check URL (press key)',0
m_unsupported dta c'File type not supported (press key)',0
.endp
