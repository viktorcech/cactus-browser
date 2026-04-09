; ============================================================================
; FujiNet N: Device SIO Layer
; ============================================================================

FN_DEVID       = $71
FN_UNIT        = 1
fn_cur_unit    dta FN_UNIT     ; current N: unit (1=page, 2=image)
FN_CMD_OPEN    = 'O'
FN_CMD_CLOSE   = 'C'
FN_CMD_READ    = 'R'
FN_CMD_STATUS  = 'S'
SIO_READ       = $40
SIO_WRITE      = $80
SIO_NONE       = $00
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
        lda fn_cur_unit
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
; Reads 4-byte DVSTAT: [0]=bytes_lo, [1]=bytes_hi, [2]=connected, [3]=error
; Error codes: 0=ok, 136($88)=EOF/closed, other=fatal
; Output: zp_fn_bytes_lo/hi, zp_fn_connected, zp_fn_error, C=0/1
; ----------------------------------------------------------------------------
.proc fn_status
        lda #FN_DEVID
        sta DDEVIC
        lda fn_cur_unit
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
; Uses zp_fn_bytes_lo/hi from fn_status, caps at 255 (8-bit zp_rx_len)
; Reading 256 would set zp_rx_len=0 (overflow!) — always read max 255
; DAUX1/DAUX2 must match DBYTLO/DBYTHI (FujiNet requirement)
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
        lda fn_cur_unit
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
; fn_read_img - Read up to 2KB into img_big_buf for fast image streaming
; Standard fn_read caps at 255 bytes (8-bit zp_rx_len), requiring ~260
; SIO calls for a 66KB image. This routine reads up to 2048 bytes per
; SIO call, reducing calls to ~33 (8x fewer, much less SIO overhead).
; Uses zp_fn_bytes_lo/hi from fn_status, caps at IMG_BIG_SIZE (2048)
; Output: img_chunk_lo/hi = bytes actually requested, C=0 ok, C=1 error
; DAUX1/DAUX2 must equal DBYTLO/DBYTHI (FujiNet protocol requirement)
; ----------------------------------------------------------------------------
.proc fn_read_img
        ; Cap at IMG_BIG_SIZE ($0800)
        lda zp_fn_bytes_hi
        cmp #>IMG_BIG_SIZE     ; >= 8 pages?
        bcc ?use               ; < 8 pages, use exact
        ; >= 2048 bytes: cap
        lda #<IMG_BIG_SIZE
        sta img_chunk_lo
        lda #>IMG_BIG_SIZE
        sta img_chunk_hi
        jmp ?do
?use    sta img_chunk_hi
        lda zp_fn_bytes_lo
        sta img_chunk_lo
        ora img_chunk_hi
        beq ?nothing

?do     lda #FN_DEVID
        sta DDEVIC
        lda fn_cur_unit
        sta DUNIT
        lda #FN_CMD_READ
        sta DCOMND
        lda #SIO_READ
        sta DSTATS
        lda #<img_big_buf
        sta DBUFLO
        lda #>img_big_buf
        sta DBUFHI
        lda #FN_TIMEOUT
        sta DTIMLO
        lda img_chunk_lo
        sta DBYTLO
        sta DAUX1
        lda img_chunk_hi
        sta DBYTHI
        sta DAUX2

        jsr SIOV
        lda DSTATS
        bmi ?err
        clc
        rts
?err    sec
        rts
?nothing
        lda #0
        sta img_chunk_lo
        sta img_chunk_hi
        clc
        rts
.endp

; ----------------------------------------------------------------------------
; fn_close - Close FujiNet connection
; ----------------------------------------------------------------------------
.proc fn_close
        lda #FN_DEVID
        sta DDEVIC
        lda fn_cur_unit
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

        jmp SIOV
.endp
