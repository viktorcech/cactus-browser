; ============================================================================
; Atari 850 Interface Module - R: Serial Port Support
; Uses standard CIO calls (no concurrent mode, no direct handler vectors)
; Compatible with Altirra Networked serial port device
;
; Protocol: Browser sends "GET <url>\r\n", proxy relays HTML + EOT ($04)
; ============================================================================

; CIO equates (CIOV, ICCOM, ICBAL, ICBAH, ICBLL, ICBLH, ICAX1, ICAX2,
; CIO_OPEN, CIO_CLOSE already defined in keyboard.asm)
CIOV_VEC   = CIOV
HATABS     = $031A

; IOCB #2 offset
IOCB2      = $20

; CIO commands for I/O
CIO_GET_BYTES = $07
CIO_PUT_BYTES = $0B
CIO_STATUS    = $0D

; R: XIO commands
XIO_FLUSH      = 32
XIO_BAUD       = 36
XIO_TRANSLATE  = 38

; Baud rate values
BAUD_19200 = 15

; Config defaults
M850_DEF_BAUD  = BAUD_19200
M850_STOPBITS1 = 0

; Proxy protocol
M850_EOT   = $04

; Config variables
m850_baudrate   dta b(M850_DEF_BAUD)
m850_stopbits   dta b(M850_STOPBITS1)
m850_hatabs_pos dta b(0)

; Single-byte buffer for putch
m850_txbyte     dta b(0)

; (850 handler loaded from AUTORUN on ATR disk, or via .loadobj before boot)

; ----------------------------------------------------------------------------
; m850_detect - Check if R: handler is present in HATABS
; ----------------------------------------------------------------------------
.proc m850_detect
        ldx #0
?lp     lda HATABS,x
        cmp #'R'
        beq ?found
        inx
        inx
        inx
        cpx #36
        bcc ?lp
        sec
        rts
?found  stx m850_hatabs_pos
        clc
        rts
.endp

; ----------------------------------------------------------------------------
; m850_init_vectors - No-op (using CIO instead of direct vectors)
; ----------------------------------------------------------------------------
.proc m850_init_vectors
        rts
.endp

; ----------------------------------------------------------------------------
; m850_open_port - Open R: device via CIO
; Output: C=0 ok, C=1 error
; ----------------------------------------------------------------------------
.proc m850_open_port
        jsr m850_close_port

        ; OPEN R: for read/write
        lda #CIO_OPEN
        sta ICCOM+IOCB2
        lda #<m850_rname
        sta ICBAL+IOCB2
        lda #>m850_rname
        sta ICBAH+IOCB2
        lda #13                ; read + write
        sta ICAX1+IOCB2
        lda #0
        sta ICAX2+IOCB2
        ldx #IOCB2
        jsr CIOV_VEC
        bmi ?err

        ; Set baud rate - XIO 36 (ignore error)
        lda #XIO_BAUD
        sta ICCOM+IOCB2
        lda m850_baudrate
        clc
        adc m850_stopbits
        sta ICAX1+IOCB2
        lda #0
        sta ICAX2+IOCB2
        ldx #IOCB2
        jsr CIOV_VEC

        ; Set no translation - XIO 38 (ignore error)
        lda #XIO_TRANSLATE
        sta ICCOM+IOCB2
        lda #32
        sta ICAX1+IOCB2
        ldx #IOCB2
        jsr CIOV_VEC

        ; Send ATS0=1 to modem (auto-answer after 1 ring)
        ; Required for Altirra modem to accept incoming TCP connections
        lda #<m_ats0
        ldx #>m_ats0
        jsr m850_send_string

        ; Flush modem command
        lda #XIO_FLUSH
        sta ICCOM+IOCB2
        lda #0
        sta ICAX1+IOCB2
        sta ICAX2+IOCB2
        ldx #IOCB2
        jsr CIOV_VEC

        ; Wait for modem to process (~1 second)
        ldx #60
?mdly   lda RTCLOK+2
?mw     cmp RTCLOK+2
        beq ?mw
        dex
        bne ?mdly

        lda #1
        sta zp_modem_online
        clc
        rts
?err
        lda #0
        sta zp_modem_online
        sec
        rts
.endp

; ----------------------------------------------------------------------------
; m850_close_port - Close R: device
; ----------------------------------------------------------------------------
.proc m850_close_port
        lda #CIO_CLOSE
        sta ICCOM+IOCB2
        ldx #IOCB2
        jsr CIOV_VEC
        lda #0
        sta zp_modem_online
        rts
.endp

; ----------------------------------------------------------------------------
; m850_putch - Send one byte via CIO PUT BYTES
; Input: A = byte to send
; ----------------------------------------------------------------------------
.proc m850_putch
        sta m850_txbyte
        lda #CIO_PUT_BYTES
        sta ICCOM+IOCB2
        lda #<m850_txbyte
        sta ICBAL+IOCB2
        lda #>m850_txbyte
        sta ICBAH+IOCB2
        lda #1
        sta ICBLL+IOCB2
        lda #0
        sta ICBLH+IOCB2
        ldx #IOCB2
        jsr CIOV_VEC
        rts
.endp

; ----------------------------------------------------------------------------
; m850_send_string - Send null-terminated string via CIO
; Input: A=lo, X=hi of string address
; ----------------------------------------------------------------------------
.proc m850_send_string
        sta zp_tmp_ptr
        stx zp_tmp_ptr+1
        ; Find string length
        ldy #0
?len    lda (zp_tmp_ptr),y
        beq ?got
        iny
        bne ?len
?got    tya
        beq ?done              ; empty string
        ; Send entire string via CIO PUT BYTES
        lda #CIO_PUT_BYTES
        sta ICCOM+IOCB2
        lda zp_tmp_ptr
        sta ICBAL+IOCB2
        lda zp_tmp_ptr+1
        sta ICBAH+IOCB2
        sty ICBLL+IOCB2
        lda #0
        sta ICBLH+IOCB2
        ldx #IOCB2
        jsr CIOV_VEC
?done   rts
.endp

; ----------------------------------------------------------------------------
; m850_open - Send URL request to proxy (called by net_open)
; Output: C=0 ok, C=1 error
; ----------------------------------------------------------------------------
.proc m850_open
        lda zp_modem_online
        bne ?ok
        sec
        rts

?ok     lda #0
        sta zp_fn_error

        ; Send "GET " command
        lda #<m_get
        ldx #>m_get
        jsr m850_send_string

        ; Send URL (skip "N:" prefix if present)
        lda url_buffer
        cmp #'N'
        bne ?no_n
        lda url_buffer+1
        cmp #':'
        bne ?no_n
        lda #<(url_buffer+2)
        ldx #>(url_buffer+2)
        jmp ?send
?no_n   lda #<url_buffer
        ldx #>url_buffer
?send   jsr m850_send_string

        ; Send CR LF
        lda #13
        jsr m850_putch
        lda #10
        jsr m850_putch

        ; Flush output buffer - XIO 32 (force short block)
        lda #XIO_FLUSH
        sta ICCOM+IOCB2
        lda #0
        sta ICAX1+IOCB2
        sta ICAX2+IOCB2
        ldx #IOCB2
        jsr CIOV_VEC

        clc
        rts

m_get   dta c'GET ',0
.endp

; ----------------------------------------------------------------------------
; m850_status - Get R: status via CIO STATUS
; Sets: zp_fn_bytes_lo/hi, zp_fn_connected, zp_fn_error
; ----------------------------------------------------------------------------
.proc m850_status
        lda #CIO_STATUS
        sta ICCOM+IOCB2
        ldx #IOCB2
        jsr CIOV_VEC

        ; DVSTAT set by STATUS call
        lda DVSTAT
        sta zp_fn_bytes_lo
        lda DVSTAT+1
        sta zp_fn_bytes_hi

        lda zp_modem_online
        sta zp_fn_connected

        clc
        rts
.endp

; ----------------------------------------------------------------------------
; m850_read - Read data from R: via CIO GET BYTES
; Output: zp_rx_len = bytes read, C=0
; ----------------------------------------------------------------------------
.proc m850_read
        lda zp_fn_bytes_hi
        bne ?max
        lda zp_fn_bytes_lo
        beq ?nothing
?max    lda #255
        sta zp_tmp1

        ; Read via CIO GET BYTES
        lda #CIO_GET_BYTES
        sta ICCOM+IOCB2
        lda #<rx_buffer
        sta ICBAL+IOCB2
        lda #>rx_buffer
        sta ICBAH+IOCB2
        lda zp_tmp1
        sta ICBLL+IOCB2
        lda #0
        sta ICBLH+IOCB2
        ldx #IOCB2
        jsr CIOV_VEC

        ; Check how many bytes were actually read
        lda ICBLL+IOCB2
        sta zp_rx_len
        beq ?nothing

        ; Scan for EOT marker in received data
        ldy #0
?scan   lda rx_buffer,y
        cmp #M850_EOT
        beq ?eof
        iny
        cpy zp_rx_len
        bne ?scan

        clc
        rts

?eof    sty zp_rx_len          ; truncate at EOT
        lda #136
        sta zp_fn_error
        clc
        rts

?nothing
        lda #0
        sta zp_rx_len
        clc
        rts
.endp

; ----------------------------------------------------------------------------
; m850_close - End of request (keeps serial connection alive)
; ----------------------------------------------------------------------------
.proc m850_close
        clc
        rts
.endp

; R: device name
m850_rname dta c'R:',0

; Modem init command (auto-answer after 1 ring)
m_ats0     dta c'ATS0=1',$0D,0
