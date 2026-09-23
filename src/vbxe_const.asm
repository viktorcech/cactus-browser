; ============================================================================
; VBXE Constants, Register Offsets, and Macros
; For Cactus - Atari XE/XL
; Assembler: MADS
; ============================================================================

; ----------------------------------------------------------------------------
; VBXE Register Offsets (from base $D640 or $D740)
; ----------------------------------------------------------------------------

VBXE_VCTL      = $40   ; VIDEO_CONTROL (R/W)
VBXE_CORE_VER  = $40   ; CORE_VERSION (R) - same offset, read = version

VBXE_XDL_ADR0  = $41   ; XDL address low byte (W)
VBXE_XDL_ADR1  = $42   ; XDL address mid byte (W) — not used (INY from ADR0), kept for HW reference
VBXE_XDL_ADR2  = $43   ; XDL address high byte (W) — not used (INY from ADR0), kept for HW reference

VBXE_CSEL      = $44   ; Color Select (index 0-255)
VBXE_PSEL      = $45   ; Palette Select (0=playfield, 1=overlay)
VBXE_CR        = $46   ; Color Red component
VBXE_CG        = $47   ; Color Green component
VBXE_CB        = $48   ; Color Blue component

VBXE_BL_ADR0   = $50   ; BCB address low
VBXE_BLITTER   = $53   ; Write $01=start, Read: non-zero=busy

VBXE_MEMAC_B   = $5D   ; MEMAC B control (window $4000-$7FFF)

; VIDEO_CONTROL bits
VC_XDL_ENABLED = $01
VC_XCOLOR      = $02

FX_CORE_VER    = $10   ; Expected CORE_VERSION for FX core

; ----------------------------------------------------------------------------
; XDL Control Word Flags
; ----------------------------------------------------------------------------
XDLC_TMON     = $0001
XDLC_GMON     = $0002
XDLC_OVOFF    = $0004
XDLC_MAPOFF   = $0010
XDLC_RPTL     = $0020
XDLC_OVADR    = $0040
XDLC_CHBASE   = $0100
XDLC_OVATT    = $0800
XDLC_END      = $8000

; ----------------------------------------------------------------------------
; VBXE VRAM Layout
; ----------------------------------------------------------------------------
VRAM_SCREEN    = $0000  ; Screen: SCR_ROWS*160 bytes (4800 for 30 rows)
VRAM_BCB       = $1300  ; BCB blocks (after screen)
VRAM_PATTERN   = $1380  ; (original) fill pattern, 2 bytes
VRAM_GRAD      = $13C0  ; title gradient colours + BCB
VRAM_XDL       = $1400  ; XDL (up to 128 bytes)
VRAM_IMG_BCB   = $1480  ; image centring BCBs (img_fetch)
 .if 1                          ; 2026-09-23 (vbxe-blitter: 4 constant-fill BCBs, 84 bytes)
VRAM_GRAD_BCB  = $14C0  ; title gradient BCBs (after the image BCBs)
VRAM_HLINE_BCB = VRAM_GRAD_BCB+4*21 ; vbxe_hline BCB pair (copied with the gradient)
MEMB_HLINE_BCB = MEMB_BASE+VRAM_HLINE_BCB
 .endif
VRAM_FONT      = $2000  ; Font: 256*8 = 2048 bytes
PAGE_BUF_BANK  = 5      ; VRAM $14000 >> 14 = 5

; CPU addresses when MEMAC B bank 0 active ($4000 + VRAM offset)
MEMB_BASE      = $4000
MEMB_SCREEN    = $4000
MEMB_BCB       = $5300
MEMB_PATTERN   = $5380  ; (original)
MEMB_XDL       = $5400
MEMB_FONT      = $6000

; Screen dimensions
SCR_COLS       = 80
SCR_ROWS       = 29
SCR_STRIDE     = 160    ; 80 chars + 80 attrs
CHBASE_VAL     = 4      ; VRAM_FONT / $800

; Content area (derived from SCR_ROWS)
CONTENT_TOP    = 2
CONTENT_BOT    = SCR_ROWS - 3
CONTENT_ROWS   = SCR_ROWS - 4
URL_ROW        = 0
TITLE_ROW      = 1
STATUS_ROW     = SCR_ROWS - 2

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
COL_CYAN       = 12   ; h4 headings
COL_PINK       = 13   ; underline
COL_LTGRAY     = 14   ; h5/h6 headings, sup/sub
COL_LIME       = 15   ; sub

; ANSI SGR color palette (indices $10-$1F)
ATTR_ANSI_BASE = $10          ; 8 standard + 8 bright ANSI colors

ATTR_NORMAL    = COL_WHITE
ATTR_LINK      = COL_BLUE     ; basic link color (for UI elements)
ATTR_LINK_BASE = $20          ; link attrs: $20+link_num (palette $20-$5F = blue)
ATTR_HEADING   = COL_ORANGE
ATTR_H1        = COL_YELLOW
ATTR_H2        = COL_ORANGE
ATTR_H3        = COL_GREEN
ATTR_H4        = COL_CYAN
ATTR_H5        = COL_LTGRAY
ATTR_H6        = COL_LTGRAY
ATTR_ERROR     = COL_RED
ATTR_DECOR     = COL_GRAY
ATTR_UNDERLINE = COL_PINK
ATTR_SUP       = COL_GRAY
ATTR_SUB       = COL_LIME

; ----------------------------------------------------------------------------
; Atari System Equates
; ----------------------------------------------------------------------------
RTCLOK     = $0012
SDMCTL     = $022F
CHBAS      = $02F4
CH         = $02FC
PORTA      = $D300
SIOV       = $E459
COLDSV     = $E477
PAL        = $D014         ; PAL/NTSC flag ($01=PAL, other=NTSC)

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
KEY_SPACE  = $21
KEY_NONE   = $FF
ATASCII_TAB = $7F              ; TAB key via CIO K: (ATASCII)
ATASCII_RET = 155              ; Return via CIO K: (ATASCII)

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
; Hot parser vars in ZP (save 1-3 cycles per page byte / text char vs
; their old absolute-memory locations; defined here, used in html_parser)
chunk_idx      = $99   ; parser position in rx_buffer (2 accesses per byte!)
emit_skip      = $9A   ; combined skip flag (tested per text char)
utf8_skip      = $9B   ; UTF-8 continuation bytes left (tested per text char)
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
ansi_state     = $A7   ; ANSI escape state (tested per emitted char)
in_pre         = $A8   ; inside <pre> (tested per emitted char)
zp_hist_ptr    = $A9   ; 1 byte - history stack index (0-7)
in_quotes      = $AA   ; quote char inside attr value (tested per attr byte)
zp_img_ptr     = $AB   ; 2 bytes - image write pointer (MEMAC B window)
zp_memb_shadow = $AD   ; MEMAC B shadow for NMI-safe restore
zp_tirq_saved  = $AE   ; Timer IRQ: saved shadow value
zp_vbi_saved   = $AF   ; VBI: saved shadow value

; Page buffer pointers ($B8-$BB, after mouse $B0-$B7)
zp_pb_wr_ptr   = $B8   ; 2B write pointer (MEMAC B window $4000-$7FFF)
zp_pb_rd_ptr   = $BA   ; 2B read pointer

; TAB navigation ($BC)
zp_tab_link    = $BC   ; currently selected link via TAB ($FF = none)

; Renderer/parser flags tested per character ($BD-$BF)
skip_hf        = $BD   ; skip_to_heading OR skip_to_frag (update_emit_skip)
emit_slow      = $BE   ; emit_skip OR ansi_state OR in_pre OR in_title: 0 = plain text
last_was_sp    = $BF   ; last output was a space (only read while zp_word_len = 0)

; Tables and buffers outside the MEMAC B window (data.asm, $8000+)
; char_class, print_buf -- readable while the window is open

; ----------------------------------------------------------------------------
; Macros
; ----------------------------------------------------------------------------

; MEMAC B macros with shadow variable for interrupt-safe restore.
; IMPORTANT: Code using these macros MUST be below $4000!
; When MEMAC B is active, $4000-$7FFF reads VRAM, not RAM.
; Interrupt handlers use stubs at page 6 to disable/restore MEMAC B.
;
; The register is written absolute (4 cycles, Y untouched) at the page the
; code is assembled for ($D6xx). Every such store records the address of
; its operand's high byte in the MADS .PUT array: element 0 counts them
; (labels set inside a macro stay local to it, the array is global),
; elements 2.. hold the addresses. data.asm emits the list (.SAV) and
; memac_patch moves them all to $D7xx when VBXE answers there.
 .if 1                          ; 2026-09-23 (6502-cycles-layout / vbxe: MEMAC B written absolute, patched
                                ; to the detected page at start; -4 cycles a switch, Y kept).
                                ; Pairs with memac_patch (vbxe_detect) and memac_sites (data)
VBXE_REGS = $D600
        .put [0] = 0

; memb_set: A = MEMAC B value (store the shadow first: NMI-safe ordering)
memb_set .macro
        sta VBXE_REGS+VBXE_MEMAC_B
        .put [2+.get[0]*2] = <(*-1)
        .put [3+.get[0]*2] = >(*-1)
        .put [0] = .get[0]+1
        .endm

memb_on .macro
        lda #$80+:1
        sta zp_memb_shadow     ; shadow FIRST (NMI-safe ordering)
        memb_set
        .endm

memb_off .macro
        lda #0
        sta zp_memb_shadow     ; shadow FIRST (NMI-safe ordering)
        memb_set
        .endm
 .else
VBXE_REGS = $D600
        .put [0] = 0

memb_set .macro
        ldy #VBXE_MEMAC_B
        sta (zp_vbxe_base),y
        .endm

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
 .endif

; Show message on status bar: :1=color, :2=message address
; Expands to subroutine call (9 bytes) instead of inline (31 bytes)
status_msg .macro
        ldy #:1
        lda #<:2
        ldx #>:2
        jsr status_msg_sub
        .endm

; Wait N frames (RTCLOK-based delay): :1=frame count
; Expands to subroutine call (5 bytes) instead of inline (13 bytes)
wait_frames .macro
        ldx #:1
        jsr wait_frames_sub
        .endm

; page_fit off, len: pad (placed after an unconditional exit) so that the
; loop starting `off` bytes after the pad and the instruction after its
; back branch (`len` bytes on) share one page: the branch stays 3 cycles.
; off/len are label differences inside the next proc, so they do not move.
page_fit .macro
 .if 1                          ; 2026-09-23 (6502-cycles-layout: hot loops kept in one page)
?pf_s   = * + :1
        .if >?pf_s <> >(?pf_s + :2)
        :($100 - <?pf_s) dta 0
        .endif
 .else
        ; (no pad)
 .endif
        .endm

; Original blitter macros and fill pattern, kept for the .else paths
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

; Run the BCB list at VRAM :1 (bank 0) and wait for it (blit_run)
blit .macro
        lda #<(:1)
        ldx #>(:1)
        jsr blit_run
        .endm
