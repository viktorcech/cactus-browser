; ============================================================================
; Data Module - Buffers, tables, text strings
; ============================================================================

; Strings (stay in code segment)
        icl 'build_stamp.asm'          ; msg_welcome with build date/time
; (title screen strings moved to title.asm)
msg_author     dta c'w1k 2026  github.com/viktorcech/cactus-browser',0
msg_no_vbxe    dta c'VBXE not detected!',0

; ============================================================================
; $8000-$87FF: page-aligned tables and buffers the hot loops index
; (outside the MEMAC B window, so they stay readable while it is open)
; ============================================================================
; MEMAC B register stores to move to $D7xx (memac_patch), 2 bytes each:
; the address of each store's operand high byte (memb_set, vbxe_const.asm)
MEMAC_COUNT = .get[0]
memac_sites
        .sav [2] MEMAC_COUNT*2
        ert MEMAC_COUNT*2 > 254

        ert *>$8000                    ; code must end below the tables
        org $8000

; char_class: 0 = plain text byte the parser's word loop may copy as is;
; non-zero = '<', '&', <= $20 (space/controls), >= $C0 (UTF-8 lead)
char_class
        dta 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1   ; $00
        dta 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1   ; $10
        dta 1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0   ; $20
        dta 0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0   ; $30
        dta 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0   ; $40
        dta 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0   ; $50
        dta 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0   ; $60
        dta 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0   ; $70
        dta 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0   ; $80
        dta 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0   ; $90
        dta 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0   ; $A0
        dta 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0   ; $B0
        dta 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1   ; $C0
        dta 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1   ; $D0
        dta 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1   ; $E0
        dta 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1   ; $F0

rx_buffer      .ds RX_BUF_SIZE          ; $8100, page-aligned; [rx_len] = parser sentinel
print_buf      .ds 128                  ; vbxe_print / vbxe_fill_char staging
; Word-wrap buffer (size WORD_BUF_SZ defined in renderer.asm)
; Must be above $7FFF: vbxe_put_word reads it with MEMAC B window active
word_buf       .ds WORD_BUF_SZ

; Mouse timer IRQ (page 6 stub) tables, index = new_nibble<<4 | old_nibble
        .align $100
mouse_tab                              ; bit0 X+1, bit1 X-1, bit2 Y+1, bit3 Y-1
        dta 0,1,2,0,4,5,6,4,8,9,10,8,0,1,2,0
        dta 2,0,0,1,6,4,4,5,10,8,8,9,2,0,0,1
        dta 1,0,0,2,5,4,4,6,9,8,8,10,1,0,0,2
        dta 0,2,1,0,4,6,5,4,8,10,9,8,0,2,1,0
        dta 8,9,10,8,0,1,2,0,0,1,2,0,4,5,6,4
        dta 10,8,8,9,2,0,0,1,2,0,0,1,6,4,4,5
        dta 9,8,8,10,1,0,0,2,1,0,0,2,5,4,4,6
        dta 8,10,9,8,0,2,1,0,0,2,1,0,4,6,5,4
        dta 4,5,6,4,0,1,2,0,0,1,2,0,8,9,10,8
        dta 6,4,4,5,2,0,0,1,2,0,0,1,10,8,8,9
        dta 5,4,4,6,1,0,0,2,1,0,0,2,9,8,8,10
        dta 4,6,5,4,0,2,1,0,0,2,1,0,8,10,9,8
        dta 0,1,2,0,8,9,10,8,4,5,6,4,0,1,2,0
        dta 2,0,0,1,10,8,8,9,6,4,4,5,2,0,0,1
        dta 1,0,0,2,9,8,8,10,5,4,4,6,1,0,0,2
        dta 0,2,1,0,8,10,9,8,4,6,5,4,0,2,1,0
mouse_nib                              ; next old_nibble = index >> 4
        :256 dta #/16
        ert *>$8800

; ============================================================================
; Large buffers at $8800
; Memory map: code $2000-$2B00, MEMAC B window $4000-$7FFF (VRAM access),
; buffers $8800+, OS ROM $C000+. Buffers here are safe from MEMAC B corruption.
; ============================================================================
        org $8800

; Large image transfer buffer for fast SIO reads (2KB)
; fn_read_img reads up to 2048 bytes per SIO call into this buffer,
; then vbxe_img_write_big copies it to VRAM. This reduces SIO overhead
; ~8x vs the standard 255-byte rx_buffer path.
; Page-aligned (the copy loops read it with abs,y); above $7FFF so it's accessible even when MEMAC B is active.
IMG_BIG_SIZE   = $0800         ; 2048 bytes
img_big_buf    .ds IMG_BIG_SIZE
img_chunk_lo   dta 0           ; 16-bit byte count (lo)
img_chunk_hi   dta 0           ; 16-bit byte count (hi)

url_buffer     .ds URL_BUF_SIZE         ; 256 bytes
url_length     dta a(0)

; History data area (16 * 130 = 2080 bytes)
HIST_DATA_SZ   = HIST_MAX * HIST_ENTRY_SZ
history_data   .ds HIST_DATA_SZ

; Link URL storage (32 * 128 = 4096 bytes)
LINK_URLS_SZ   = MAX_LINKS * LINK_URL_SIZE
link_urls      .ds LINK_URLS_SZ

; Base URL for relative link resolution (up to last '/')
base_url       .ds URL_BUF_SIZE

; URL backup for image fetch (url_buffer gets overwritten by converter URL)
url_save_buf   .ds URL_BUF_SIZE
url_save_len   dta a(0)

; Image palette buffer (768 bytes = 256 colors * 3 bytes RGB)
img_pal_buf    .ds 768


; Current page URL (clean, pre-proxy, no N: prefix) — snapshot taken in
; http_navigate; used by bookmarks 'A' (add current page). Sized to fit
; a bookmark slot. [0]=0 means no page loaded (init in main).
cur_page_url   .ds BK_SLOT_SZ
        ert *>$C000
