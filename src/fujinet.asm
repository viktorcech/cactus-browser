; ============================================================================
; FujiNet N: Device SIO Layer
; ============================================================================

FN_DEVID       = $71
FN_UNIT        = 1
FN_CMD_OPEN    = 'O'
FN_CMD_CLOSE   = 'C'
FN_CMD_READ    = 'R'
FN_CMD_WRITE   = 'W'
FN_CMD_STATUS  = 'S'
SIO_READ       = $40
SIO_WRITE      = $80
SIO_NONE       = $00
FN_HTTP_GET    = 12
FN_OPEN_READ   = 4
FN_TRANS_NONE  = 0
FN_TIMEOUT     = 30
URL_BUF_SIZE   = 256
RX_BUF_SIZE    = 256

; ----------------------------------------------------------------------------
; fn_open - Open FujiNet connection (url_buffer -> OPEN)
; Output: C=0 ok, C=1 error
; ----------------------------------------------------------------------------
.proc fn_open
        lda #FN_DEVID
        sta DDEVIC
        lda #FN_UNIT
        sta DUNIT
        lda #FN_CMD_OPEN
        sta DCOMND
        lda #SIO_WRITE
        sta DSTATS
        lda #<url_buffer
        sta DBUFLO
        lda #>url_buffer
        sta DBUFHI
        lda #FN_TIMEOUT
        sta DTIMLO
        lda #<URL_BUF_SIZE
        sta DBYTLO
        lda #>URL_BUF_SIZE
        sta DBYTHI
        lda #FN_OPEN_READ
        sta DAUX1
        lda #FN_TRANS_NONE
        sta DAUX2

        jsr SIOV
        lda DSTATS
        bmi ?err
        clc
        rts
?err    sec
        rts
.endp

; ----------------------------------------------------------------------------
; fn_status - Get FujiNet status (bytes waiting, connected, error)
; Output: zp_fn_bytes_lo/hi, zp_fn_connected, zp_fn_error, C=0/1
; ----------------------------------------------------------------------------
.proc fn_status
        lda #FN_DEVID
        sta DDEVIC
        lda #FN_UNIT
        sta DUNIT
        lda #FN_CMD_STATUS
        sta DCOMND
        lda #SIO_READ
        sta DSTATS
        lda #<DVSTAT
        sta DBUFLO
        lda #>DVSTAT
        sta DBUFHI
        lda #FN_TIMEOUT
        sta DTIMLO
        lda #4
        sta DBYTLO
        lda #0
        sta DBYTHI
        sta DAUX1
        sta DAUX2

        jsr SIOV
        lda DSTATS
        bmi ?err

        lda DVSTAT
        sta zp_fn_bytes_lo
        lda DVSTAT+1
        sta zp_fn_bytes_hi
        lda DVSTAT+2
        sta zp_fn_connected
        lda DVSTAT+3
        sta zp_fn_error

        clc
        rts
?err    sec
        rts
.endp

; ----------------------------------------------------------------------------
; fn_read - Read data from FujiNet into rx_buffer
; Uses zp_fn_bytes_lo/hi from fn_status
; Output: zp_rx_len = bytes read, C=0/1
; ----------------------------------------------------------------------------
.proc fn_read
        lda zp_fn_bytes_hi
        bne ?max
        lda zp_fn_bytes_lo
        beq ?nothing
        bne ?use_lo

?max    lda #255                       ; Max 255 bytes (fits in 8-bit rx_len)
        sta zp_rx_len
        sta DBYTLO
        lda #0
        sta DBYTHI
        jmp ?do

?use_lo sta zp_rx_len
        sta DBYTLO
        lda #0
        sta DBYTHI
        jmp ?do

?nothing
        lda #0
        sta zp_rx_len
        clc
        rts

?do     lda #FN_DEVID
        sta DDEVIC
        lda #FN_UNIT
        sta DUNIT
        lda #FN_CMD_READ
        sta DCOMND
        lda #SIO_READ
        sta DSTATS
        lda #<rx_buffer
        sta DBUFLO
        lda #>rx_buffer
        sta DBUFHI
        lda #FN_TIMEOUT
        sta DTIMLO
        lda DBYTLO
        sta DAUX1
        lda DBYTHI
        sta DAUX2

        jsr SIOV
        lda DSTATS
        bmi ?err
        clc
        rts
?err    sec
        rts
.endp

; ----------------------------------------------------------------------------
; fn_close - Close FujiNet connection
; ----------------------------------------------------------------------------
.proc fn_close
        lda #FN_DEVID
        sta DDEVIC
        lda #FN_UNIT
        sta DUNIT
        lda #FN_CMD_CLOSE
        sta DCOMND
        lda #SIO_NONE
        sta DSTATS
        lda #0
        sta DBUFLO
        sta DBUFHI
        sta DBYTLO
        sta DBYTHI
        sta DAUX1
        sta DAUX2
        lda #FN_TIMEOUT
        sta DTIMLO

        jsr SIOV
        lda DSTATS
        bmi ?err
        clc
        rts
?err    sec
        rts
.endp
