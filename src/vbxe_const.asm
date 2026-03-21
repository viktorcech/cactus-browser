; ============================================================================
; VBXE Constants, Register Offsets, and Macros
; For VBXE Web Browser - Atari XE/XL
; Assembler: MADS
; ============================================================================

; ----------------------------------------------------------------------------
; VBXE Register Offsets (from base $D640 or $D740)
; ----------------------------------------------------------------------------

VBXE_VCTL      = $40   ; VIDEO_CONTROL (R/W)
VBXE_CORE_VER  = $40   ; CORE_VERSION (R) - same offset, read = version
VBXE_MINOR_VER = $41   ; MINOR_REVISION (R)

VBXE_XDL_ADR0  = $41   ; XDL address low byte (W)
VBXE_XDL_ADR1  = $42   ; XDL address mid byte (W)
VBXE_XDL_ADR2  = $43   ; XDL address high byte (W)

VBXE_CSEL      = $44   ; Color Select (index 0-255)
VBXE_PSEL      = $45   ; Palette Select (0=playfield, 1=overlay)
VBXE_CR        = $46   ; Color Red component
VBXE_CG        = $47   ; Color Green component
VBXE_CB        = $48   ; Color Blue component

VBXE_BL_ADR0   = $50   ; BCB address low
VBXE_BL_ADR1   = $51   ; BCB address mid
VBXE_BL_ADR2   = $52   ; BCB address high
VBXE_BLITTER   = $53   ; Write $01=start, Read: non-zero=busy

VBXE_MEMAC_B   = $5D   ; MEMAC B control (window $4000-$7FFF)
VBXE_MEMAC_A   = $5E   ; MEMAC A control
VBXE_MEMAC_AS  = $5F   ; MEMAC A bank select

; VIDEO_CONTROL bits
VC_XDL_ENABLED = $01
VC_XCOLOR      = $02
VC_NO_TRANS    = $04

; MEMAC B values
MEMB_BANK0_ON  = $80   ; Bank 0, CPU access enabled
MEMB_BANK1_ON  = $81
MEMB_BANK2_ON  = $82
MEMB_DISABLED  = $00

FX_CORE_VER    = $10   ; Expected CORE_VERSION for FX core

; ----------------------------------------------------------------------------
; XDL Control Word Flags
; ----------------------------------------------------------------------------
XDLC_TMON     = $0001
XDLC_GMON     = $0002
XDLC_OVOFF    = $0004
XDLC_MAPON    = $0008
XDLC_MAPOFF   = $0010
XDLC_RPTL     = $0020
XDLC_OVADR    = $0040
XDLC_OVSCRL   = $0080
XDLC_CHBASE   = $0100
XDLC_MAPADR   = $0200
XDLC_MAPPAR   = $0400
XDLC_OVATT    = $0800
XDLC_HR       = $1000
XDLC_LR       = $2000
XDLC_END      = $8000

; ----------------------------------------------------------------------------
; VBXE VRAM Layout
; ----------------------------------------------------------------------------
VRAM_SCREEN    = $0000  ; Screen: 24*160 = 3840 bytes
VRAM_SCREEN_SZ = 3840
VRAM_BCB       = $1000  ; BCB blocks
VRAM_XDL       = $1100  ; XDL
VRAM_FONT      = $2000  ; Font: 256*8 = 2048 bytes
VRAM_FONT_INV  = $2800  ; Inverse font
VRAM_PATTERN   = $1080  ; Fill pattern (2 bytes)

; CPU addresses when MEMAC B bank 0 active ($4000 + VRAM offset)
MEMB_BASE      = $4000
MEMB_SCREEN    = $4000
MEMB_BCB       = $5000
MEMB_XDL       = $5100
MEMB_FONT      = $6000
MEMB_PATTERN   = $5080

; Screen dimensions
SCR_COLS       = 80
SCR_ROWS       = 24
SCR_STRIDE     = 160    ; 80 chars + 80 attrs
CHBASE_VAL     = 4      ; VRAM_FONT / $800

; Content area
CONTENT_TOP    = 2
CONTENT_BOT    = 22
CONTENT_ROWS   = 21
URL_ROW        = 0
TITLE_ROW      = 1
STATUS_ROW     = 23

; ----------------------------------------------------------------------------
; Color Palette Indices (overlay palette 1)
; ----------------------------------------------------------------------------
COL_BLACK      = 0
COL_WHITE      = 1
COL_BLUE       = 2
COL_ORANGE     = 3
COL_GREEN      = 4
COL_RED        = 5
COL_GRAY       = 6
COL_YELLOW     = 7

ATTR_NORMAL    = COL_WHITE
ATTR_LINK      = COL_BLUE
ATTR_HEADING   = COL_ORANGE
ATTR_H1        = COL_YELLOW
ATTR_H2        = COL_ORANGE
ATTR_H3        = COL_GREEN
ATTR_URL       = COL_GREEN
ATTR_ERROR     = COL_RED
ATTR_DECOR     = COL_GRAY
ATTR_HILINK    = COL_YELLOW
ATTR_BOLD      = COL_WHITE

; ----------------------------------------------------------------------------
; Atari System Equates
; ----------------------------------------------------------------------------
RTCLOK     = $0012
VDSLST     = $0200
SDMCTL     = $022F
SDLSTL     = $0230
CHBAS      = $02F4
CRSINH     = $02F0
CH         = $02FC
CONSOL     = $D01F
PORTA      = $D300
PORTB      = $D301
NMIEN      = $D40E
WSYNC      = $D40A
SIOV       = $E459
COLDSV     = $E477

; SIO DCB
DDEVIC     = $0300
DUNIT      = $0301
DCOMND     = $0302
DSTATS     = $0303
DBUFLO     = $0304
DBUFHI     = $0305
DTIMLO     = $0306
DBYTLO     = $0308
DBYTHI     = $0309
DAUX1      = $030A
DAUX2      = $030B

DVSTAT     = $02EA

; Keyboard codes
KEY_RETURN = $0C
KEY_ESC    = $1C
KEY_TAB    = $2C
KEY_SPACE  = $21
KEY_DELETE = $34
KEY_NONE   = $FF

CH_SPACE   = $20

; ----------------------------------------------------------------------------
; Zero-Page Variables ($80-$AF)
; ----------------------------------------------------------------------------
zp_vbxe_base  = $80   ; 2 bytes
zp_cursor_row = $82
zp_cursor_col = $83
zp_cur_attr   = $84
zp_scr_ptr    = $85   ; 2 bytes
zp_tmp_ptr    = $87   ; 2 bytes
zp_tmp_ptr2   = $89   ; 2 bytes
zp_tmp1       = $8B
zp_tmp2       = $8C
zp_tmp3       = $8D

zp_parse_state = $8E
zp_tag_idx     = $8F
zp_attr_idx    = $90
zp_val_idx     = $91
zp_entity_idx  = $92

zp_render_col  = $93
zp_render_row  = $94
zp_word_len    = $95
zp_indent      = $96
zp_in_link     = $97
zp_link_num    = $98
zp_in_heading  = $99
zp_in_list     = $9A
zp_in_bold     = $9B
zp_in_skip     = $9C
zp_list_type   = $9D
zp_list_item   = $9E

zp_fn_connected = $9F
zp_fn_error    = $A0
zp_fn_bytes_lo = $A1
zp_fn_bytes_hi = $A2
zp_rx_len      = $A3

zp_cur_link    = $A4
zp_scroll_pos  = $A5   ; 2 bytes
zp_page_lines  = $A7   ; 2 bytes
zp_hist_ptr    = $A9
zp_fn_got_data = $AA
zp_img_ptr     = $AB   ; 2 bytes - image write pointer (MEMAC B window)
zp_memb_shadow = $AD   ; MEMAC B shadow for NMI-safe restore
zp_tirq_saved  = $AE   ; Timer IRQ: saved shadow value
zp_vbi_saved   = $AF   ; VBI: saved shadow value

; ----------------------------------------------------------------------------
; Macros
; ----------------------------------------------------------------------------

; MEMAC B macros with shadow variable for interrupt-safe restore.
; IMPORTANT: Code using these macros MUST be below $4000!
; When MEMAC B is active, $4000-$7FFF reads VRAM, not RAM.
; Interrupt handlers use stubs at page 6 to disable/restore MEMAC B.
memb_on .macro
        lda #$80+:1
        sta zp_memb_shadow     ; shadow FIRST (NMI-safe ordering)
        ldy #VBXE_MEMAC_B
        sta (zp_vbxe_base),y
        .endm

memb_off .macro
        lda #0
        sta zp_memb_shadow     ; shadow FIRST (NMI-safe ordering)
        ldy #VBXE_MEMAC_B
        sta (zp_vbxe_base),y
        .endm

; Show message on status bar: :1=color, :2=message address
status_msg .macro
        lda #STATUS_ROW
        ldx #:1
        jsr vbxe_fill_row
        lda #STATUS_ROW
        ldx #0
        jsr vbxe_setpos
        lda #:1
        jsr vbxe_setattr
        lda #<:2
        ldx #>:2
        jsr vbxe_print
        lda #ATTR_NORMAL
        jsr vbxe_setattr
        .endm

; Wait N frames (RTCLOK-based delay): :1=frame count
wait_frames .macro
        ldx #:1
?wfdly  lda RTCLOK+2
?wfdw   cmp RTCLOK+2
        beq ?wfdw
        dex
        bne ?wfdly
        .endm

blit_start .macro
        ldy #VBXE_BL_ADR0
        lda #<:1
        sta (zp_vbxe_base),y
        iny
        lda #>:1
        sta (zp_vbxe_base),y
        iny
        lda #0
        sta (zp_vbxe_base),y
        iny
        lda #1
        sta (zp_vbxe_base),y
        .endm

blit_wait .macro
        ldy #VBXE_BLITTER
?bw     lda (zp_vbxe_base),y
        bne ?bw
        .endm
