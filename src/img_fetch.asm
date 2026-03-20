; ============================================================================
; Image Fetch Module - Download and display VBXE image via FujiNet
; Format: 2B width(LE) + 1B height + 768B palette + w*h pixels
; ============================================================================

img_test_url dta c'N:https://turiecfoto.sk/vbxe.php?url=https://picsum.photos/160/100&w=160&h=100',0

img_hdr_w   dta a(0)
img_hdr_h   dta b(0)
img_pal_cnt dta a(0)

; ----------------------------------------------------------------------------
; img_fetch_test - Fetch and display test image
; Press I in browser
; ----------------------------------------------------------------------------
.proc img_fetch_test
        jsr ui_status_loading

        lda #<img_test_url
        ldx #>img_test_url
        jsr http_set_url

        jsr fn_open
        bcc ?ok1
        jmp ?err_open
?ok1
        ; Read 3-byte header
        jsr img_read_header
        bcc ?ok2
        jmp ?err_read
?ok2
        ; Allocate VRAM
        lda img_hdr_h
        ldx img_hdr_w
        ldy img_hdr_w+1
        jsr vbxe_img_alloc
        bcc ?ok3
        jmp ?err_read
?ok3
        ; Read palette
        jsr img_read_palette
        bcc ?ok4
        jmp ?err_read
?ok4
        ; Set VBXE palette
        lda #<img_pal_buf
        sta zp_tmp_ptr
        lda #>img_pal_buf
        sta zp_tmp_ptr+1
        jsr vbxe_img_setpal

        ; Read pixels
        jsr vbxe_img_begin_write
        jsr img_read_pixels
        jsr vbxe_img_end_write

        jsr fn_close

        ; Show image at row 4
        lda #4
        jsr vbxe_img_show
        jsr ui_status_done
        clc
        rts

?err_read
        jsr fn_close
?err_open
        jsr ui_status_error
        lda #<m_imgerr
        ldx #>m_imgerr
        jsr ui_show_error
        sec
        rts

m_imgerr dta c'Image load failed',0
.endp

; ----------------------------------------------------------------------------
; img_read_header - Read 3-byte image header
; Output: img_hdr_w, img_hdr_h set, C=0 ok
; ----------------------------------------------------------------------------
.proc img_read_header
        ; Wait for 3 bytes
?wt     jsr fn_status
        bcs ?err
        lda zp_fn_bytes_lo
        cmp #3
        bcc ?wt

        lda #3
        sta zp_fn_bytes_lo
        lda #0
        sta zp_fn_bytes_hi
        jsr fn_read
        bcs ?err

        lda rx_buffer
        sta img_hdr_w
        lda rx_buffer+1
        sta img_hdr_w+1
        lda rx_buffer+2
        sta img_hdr_h
        clc
        rts
?err    sec
        rts
.endp

; ----------------------------------------------------------------------------
; img_read_palette - Read 768 bytes of palette data
; Output: img_pal_buf filled, C=0 ok
; ----------------------------------------------------------------------------
.proc img_read_palette
        lda #<img_pal_buf
        sta zp_tmp_ptr
        lda #>img_pal_buf
        sta zp_tmp_ptr+1
        lda #0
        sta img_pal_cnt
        sta img_pal_cnt+1

?lp     jsr fn_status
        bcs ?err
        lda zp_fn_bytes_lo
        ora zp_fn_bytes_hi
        beq ?wait

        jsr fn_read
        bcs ?err
        lda zp_rx_len
        beq ?lp

        ; Copy to palette buffer
        ldy #0
?cp     cpy zp_rx_len
        beq ?chk
        lda rx_buffer,y
        sty zp_tmp3
        ldy #0
        sta (zp_tmp_ptr),y
        ldy zp_tmp3

        inc zp_tmp_ptr
        bne ?nc1
        inc zp_tmp_ptr+1
?nc1    inc img_pal_cnt
        bne ?nc2
        inc img_pal_cnt+1
?nc2    ; Check if 768 ($300) bytes done
        lda img_pal_cnt+1
        cmp #3
        bcs ?done
        iny
        jmp ?cp

?chk    lda img_pal_cnt+1
        cmp #3
        bcc ?lp
?done   clc
        rts

?wait   ldx #2
?dly    lda RTCLOK+2
?dw     cmp RTCLOK+2
        beq ?dw
        dex
        bne ?dly
        jmp ?lp

?err    sec
        rts
.endp

; ----------------------------------------------------------------------------
; img_read_pixels - Stream pixel data into VBXE VRAM
; Must call vbxe_img_begin_write first
; Output: C=0 ok
; ----------------------------------------------------------------------------
.proc img_read_pixels
?lp     jsr fn_status
        bcs ?err
        lda zp_fn_error
        cmp #136
        beq ?done
        lda zp_fn_connected
        beq ?done
        lda zp_fn_bytes_lo
        ora zp_fn_bytes_hi
        beq ?wait

        jsr fn_read
        bcs ?err
        lda zp_rx_len
        beq ?lp

        ; Write to VRAM
        ldy #0
?wr     cpy zp_rx_len
        beq ?lp
        lda rx_buffer,y
        sty zp_tmp3
        jsr vbxe_img_write_byte
        ldy zp_tmp3
        iny
        jmp ?wr

?wait   ldx #2
?dly    lda RTCLOK+2
?dw     cmp RTCLOK+2
        beq ?dw
        dex
        bne ?dly
        jmp ?lp

?done   clc
        rts
?err    sec
        rts
.endp

; Palette buffer (768 bytes)
img_pal_buf .ds 768
