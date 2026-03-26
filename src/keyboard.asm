; ============================================================================
; Keyboard Input Module
; Uses Atari CIO K: device for proper ATASCII translation
; ============================================================================

; CIO constants
CIOV    = $E456
ICCOM   = $0342         ; Command byte (base for IOCB#0)
ICBAL   = $0344         ; Buffer address low
ICBAH   = $0345         ; Buffer address high
ICBLL   = $0348         ; Buffer length low
ICBLH   = $0349         ; Buffer length high
ICAX1   = $034A         ; Aux 1
ICAX2   = $034B         ; Aux 2

CIO_OPEN   = $03
CIO_GET    = $07

; IOCB #1 offset (for K: device)
KIOCB   = $10

; ATASCII codes
ATASCII_EOL = $9B       ; Return/Enter
ATASCII_ESC = $1B       ; Escape
ATASCII_BS  = $7E       ; Backspace/Delete
ATASCII_SP  = $20       ; Space

; ----------------------------------------------------------------------------
; kbd_init - Open K: device on IOCB #1 for raw keyboard input
; Must be called once during init
; ----------------------------------------------------------------------------
.proc kbd_init
        ldx #KIOCB
        lda #CIO_OPEN
        sta ICCOM,x
        lda #4                 ; Read mode
        sta ICAX1,x
        lda #0
        sta ICAX2,x
        lda #<kdev_name
        sta ICBAL,x
        lda #>kdev_name
        sta ICBAH,x
        jmp CIOV

kdev_name dta c'K:',$9B
.endp

; ----------------------------------------------------------------------------
; kbd_get - Get one character from keyboard (blocking)
; Output: A = ATASCII character code
; Uses CIO K: device - proper OS translation of all keys
; ----------------------------------------------------------------------------
.proc kbd_get
        ldx #KIOCB
        lda #CIO_GET
        sta ICCOM,x
        lda #0
        sta ICBLL,x
        sta ICBLH,x
        jmp CIOV
        ; A = ATASCII character
.endp

; ----------------------------------------------------------------------------
; kbd_get_line - Read a line of text input
; Input: zp_tmp_ptr = buffer address, X = max length
; Output: Y = length entered
;         C=0 confirmed (Enter), C=1 cancelled (Esc)
; ----------------------------------------------------------------------------
.proc kbd_get_line
        stx kgl_max
        ldy #0
        sty kgl_len

?loop   ; Show cursor (putchar advances; cursor_back undoes the advance)
        lda #'_'
        jsr vbxe_putchar
        jsr cursor_back

        jsr kbd_get

        ; Enter = confirm
        cmp #ATASCII_EOL
        beq ?confirm

        ; Escape = cancel
        cmp #ATASCII_ESC
        beq ?cancel

        ; Backspace
        cmp #ATASCII_BS
        beq ?bksp

        ; Filter: only printable ASCII ($20-$7D)
        cmp #ATASCII_SP
        bcc ?loop
        cmp #$7E
        bcs ?loop

        ; Check max length
        ldy kgl_len
        cpy kgl_max
        bcs ?loop

        ; Store character and echo it
        sta (zp_tmp_ptr),y
        inc kgl_len
        jsr vbxe_putchar
        jmp ?loop

?bksp   ldy kgl_len
        beq ?loop

        dec kgl_len
        ; Erase cursor + last char
        lda #ATASCII_SP
        jsr vbxe_putchar
        jsr cursor_back
        jsr cursor_back
        lda #ATASCII_SP
        jsr vbxe_putchar
        jsr cursor_back
        jmp ?loop

?confirm
        lda #ATASCII_SP
        jsr vbxe_putchar
        ldy kgl_len
        lda #0
        sta (zp_tmp_ptr),y
        clc
        rts

?cancel
        lda #ATASCII_SP
        jsr vbxe_putchar
        sec
        rts

kgl_max dta 0
kgl_len dta 0
.endp

; ----------------------------------------------------------------------------
; cursor_back - Move cursor back one position (handles line wrap)
; When col=0, wraps to col=SCR_COLS-1 on previous row
; ----------------------------------------------------------------------------
.proc cursor_back
        lda zp_cursor_col
        bne ?dec
        lda #SCR_COLS-1
        sta zp_cursor_col
        dec zp_cursor_row
        rts
?dec    dec zp_cursor_col
        rts
.endp
