; ============================================================================
; Data Module - Buffers, tables, text strings
; ============================================================================

; Strings (stay in code segment)
default_url    dta c'N:http://retro.hackaday.com/',0
msg_welcome    dta c'VBXE Web Browser alpha50',0
; (title screen strings moved to title.asm)
msg_author     dta c'w1k 2025-2026  github.com/viktorcech/vbxe-browser',0
msg_no_vbxe    dta c'VBXE not detected!',0

; ============================================================================
; Large buffers at $8800 (above code, below OS ROM)
; This avoids conflict with MEMAC B window ($4000-$7FFF)
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

; Image queue for multi-image support (up to 4 images per page)
IMG_QUEUE_MAX  = 4
img_queue_urls .ds IMG_QUEUE_MAX * IMG_SRC_SIZE  ; 4 * 256 = 1024 bytes
img_queue_rows .ds IMG_QUEUE_MAX                 ; 4 bytes (display row per image)
img_queue_count dta b(0)
