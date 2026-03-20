; ============================================================================
; Network Abstraction Layer
; Dispatches to FujiNet (N:) or Atari 850 (R:) based on zp_net_device
; FujiNet is preserved as default, 850 is additional option
; ============================================================================

NET_FUJINET = 0
NET_MODEM   = 1

; ----------------------------------------------------------------------------
; net_open - Open connection / send request
; For FujiNet: SIO open to N: device
; For 850: send GET request to proxy over serial
; ----------------------------------------------------------------------------
.proc net_open
        lda zp_net_device
        bne ?modem
        jmp fn_open
?modem  jmp m850_open
.endp

; ----------------------------------------------------------------------------
; net_status - Get connection status
; Sets: zp_fn_bytes_lo/hi, zp_fn_connected, zp_fn_error
; ----------------------------------------------------------------------------
.proc net_status
        lda zp_net_device
        bne ?modem
        jmp fn_status
?modem  jmp m850_status
.endp

; ----------------------------------------------------------------------------
; net_read - Read data into rx_buffer
; Sets: zp_rx_len
; ----------------------------------------------------------------------------
.proc net_read
        lda zp_net_device
        bne ?modem
        jmp fn_read
?modem  jmp m850_read
.endp

; ----------------------------------------------------------------------------
; net_close - Close connection / end request
; For FujiNet: SIO close
; For 850: no-op (keeps serial connection alive)
; ----------------------------------------------------------------------------
.proc net_close
        lda zp_net_device
        bne ?modem
        jmp fn_close
?modem  jmp m850_close
.endp

; ----------------------------------------------------------------------------
; net_init - Device selection and initialization at startup
; Shows selection screen, initializes chosen device
; ----------------------------------------------------------------------------
.proc net_init
        lda #NET_FUJINET
        sta zp_net_device

        ; Device selection prompt
        lda #8
        ldx #0
        jsr vbxe_setpos
        lda #ATTR_NORMAL
        jsr vbxe_setattr
        lda #<m_sel1
        ldx #>m_sel1
        jsr vbxe_print

        lda #10
        ldx #4
        jsr vbxe_setpos
        lda #ATTR_LINK
        jsr vbxe_setattr
        lda #<m_sel_f
        ldx #>m_sel_f
        jsr vbxe_print

        lda #11
        ldx #4
        jsr vbxe_setpos
        lda #<m_sel_m
        ldx #>m_sel_m
        jsr vbxe_print

        lda #ATTR_NORMAL
        jsr vbxe_setattr

?wait   jsr kbd_get
        cmp #'f'
        beq ?fn
        cmp #'F'
        beq ?fn
        cmp #'m'
        beq ?modem
        cmp #'M'
        beq ?modem
        jmp ?wait

?fn     lda #NET_FUJINET
        sta zp_net_device
        clc
        rts

?modem  lda #NET_MODEM
        sta zp_net_device

        ; Detect R: handler in HATABS
        jsr m850_detect
        bcc ?r_found

        lda #<m_nor
        ldx #>m_nor
        jsr ui_show_error
        jmp net_init           ; back to selection

?r_found
        ; Extract handler vectors
        jsr m850_init_vectors

        ; Open and configure serial port
        jsr m850_open_port
        bcc ?port_ok

        lda #<m_porterr
        ldx #>m_porterr
        jsr ui_show_error
        jmp net_init

?port_ok
        ; Show ready status
        lda #13
        ldx #0
        jsr vbxe_setpos
        lda #ATTR_NORMAL
        jsr vbxe_setattr
        lda #<m_ready
        ldx #>m_ready
        jsr vbxe_print

        ; Brief pause for user to see status
        ldx #60
?dly    lda RTCLOK+2
?dw     cmp RTCLOK+2
        beq ?dw
        dex
        bne ?dly

        clc
        rts

m_sel1    dta c'Select network device:',0
m_sel_f   dta c'F - FujiNet',0
m_sel_m   dta c'M - Serial port (850 Interface)',0
m_nor     dta c'R: handler not found. 850 not connected?',0
m_porterr dta c'Cannot open R: port',0
m_ready   dta c'R: port open - 19200 baud - ready',0
.endp

; ----------------------------------------------------------------------------
; net_shutdown - Cleanup on exit
; For FujiNet: nothing needed
; For 850: close serial port
; ----------------------------------------------------------------------------
.proc net_shutdown
        lda zp_net_device
        beq ?done
        jsr m850_close_port
?done   rts
.endp
