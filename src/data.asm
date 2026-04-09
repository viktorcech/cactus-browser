; ============================================================================
; Data Module - Buffers, tables, text strings
; ============================================================================

; Strings (stay in code segment)
        icl 'build_stamp.asm'          ; msg_welcome with build date/time
; (title screen strings moved to title.asm)
msg_author     dta c'w1k 2026  github.com/viktorcech/cactus-browser',0
msg_no_vbxe    dta c'VBXE not detected!',0

; ============================================================================
; Large buffers at $8800
; Memory map: code $2000-$2B00, MEMAC B window $4000-$7FFF (VRAM access),
; buffers $8800+, OS ROM $C000+. Buffers here are safe from MEMAC B corruption.
; ============================================================================
        org $8800

url_buffer     .ds URL_BUF_SIZE         ; 256 bytes
url_length     dta a(0)

rx_buffer      .ds RX_BUF_SIZE          ; 256 bytes

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

; Large image transfer buffer for fast SIO reads (2KB)
; fn_read_img reads up to 2048 bytes per SIO call into this buffer,
; then vbxe_img_write_big copies it to VRAM. This reduces SIO overhead
; ~8x vs the standard 255-byte rx_buffer path.
; Located above $7FFF so it's accessible even when MEMAC B is active.
IMG_BIG_SIZE   = $0800         ; 2048 bytes
img_big_buf    .ds IMG_BIG_SIZE
img_chunk_lo   dta 0           ; 16-bit byte count (lo)
img_chunk_hi   dta 0           ; 16-bit byte count (hi)
