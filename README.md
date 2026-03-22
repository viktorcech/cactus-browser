# VBXE Web Browser for Atari XE/XL

80-column web browser for Atari 8-bit computers with VBXE graphics expansion, FujiNet networking, and ST mouse support.

![screenshot](https://img.shields.io/badge/status-alpha-orange)

## Status

**Alpha 50** — early development, testing on real hardware. Help is welcome!

## Requirements

- Atari 800XL/130XE or compatible (64KB RAM minimum)
- [VBXE](http://lotharek.pl/productdetail.php?id=46) (VideoBoard XE) — FX core
- [FujiNet](https://fujinet.online/) — WiFi multi-peripheral with N: device HTTP support
- Atari ST mouse in joystick port 2
- Emulator: [Altirra](https://www.virtualdub.org/altirra.html) with VBXE + FujiNet-PC

## Features

- **80×29 text display** — VBXE overlay mode with 8-color palette and per-character attributes
- **GMON gradient title screen** — graphical blue gradient banner using VBXE graphics mode
- **ST mouse** — point and click on links, works during browsing and page scrolling (`--More--` prompt)
- **HTML rendering** — 34 tags including headings (h1–h3), paragraphs, links, lists (ul/ol with bullets and numbering), bold, italic, tables, blockquotes, code/pre, definition lists (dt/dd), images
- **HTML entity decoding** — `&amp;` `&lt;` `&gt;` `&nbsp;` `&quot;` and numeric `&#NNN;`
- **HTML comment support** — `<!-- -->` properly parsed and skipped
- **UTF-8 filtering** — multi-byte sequences skipped gracefully
- **Image viewing** — inline images shown as clickable `[N]IMG` links, fullscreen 256-color display (up to 320×192) via server-side converter, uses N2: device so page download continues after viewing
- **Up to 64 links per page** with palette-encoded link detection, recycled on each page scroll
- **Word wrapping** — intelligent wrapping at word boundaries with indentation support
- **Skip to heading** — press H during `--More--` prompt to jump past navigation menus to next heading
- **URL navigation** with address bar, auto-prefix (`N:http://`), and case normalization
- **Relative URL resolution** — links and images resolved against base URL
- **History** — back navigation with scroll position preservation (16 entries)
- **Streaming download** — HTML parsed while downloading, progress shown in kB
- **Optimized HTTP** — skips redundant FujiNet STATUS calls during bulk transfer
- **CRT overscan border** — 8-scanline top border ensures URL bar is visible on real TVs

## Display

The browser uses VBXE overlay text mode (TMON) for 80-column display:

- **80×29** character grid (URL bar + title row + 26 content rows + status bar)
- 8 colors: white (text), blue (links), orange/yellow (headings), green (URL bar), red (errors), gray (decorative/status)
- Link detection via palette-encoded attributes ($20–$5F = 64 link slots, all rendered as blue)
- Font from Atari ROM, remapped to ASCII layout in VBXE VRAM
- 8-scanline OVOFF border at top for CRT overscan safety
- Fullscreen image display via GMON overlay with 256-color palette
- Title screen uses mixed GMON (gradient) + TMON (text) XDL

## Controls

| Input | Action |
|-------|--------|
| **Mouse click** | Follow link / view image |
| **U** | Enter URL |
| **B** | Back (history) |
| **H** | Skip to next heading (during `--More--`) |
| **Q** | Quit / return to welcome screen |
| **Space / Return** | Scroll to next page |

## Building

Requires [MADS](https://github.com/tebe6502/Mad-Assembler) (Mad Assembler).

```bash
mads src/browser.asm -o:bin/browser.xex -l:bin/browser.lab
```

## Source Files

| File | Description |
|------|-------------|
| `browser.asm` | Main program, entry point, module includes |
| `vbxe_const.asm` | VBXE registers, XDL flags, VRAM layout, system equates, zero-page variables, macros |
| `vbxe_detect.asm` | VBXE hardware detection (FX core version check) |
| `vbxe_init.asm` | VBXE initialization: XDL, font copy, blitter BCBs, palette (8 colors + gradient + 64 link colors) |
| `vbxe_text.asm` | Text engine: putchar, print, cls, scroll, fill, VRAM read/write helpers |
| `vbxe_gfx.asm` | Graphics: image VRAM alloc, pixel streaming, GMON XDL, fullscreen display, title gradient |
| `fujinet.asm` | FujiNet N: device SIO layer (open, status, read, close), dual N1:/N2: support |
| `http.asm` | HTTP GET workflow with optimized STATUS skipping, URL utilities |
| `url.asm` | URL normalization, prefix handling, base URL extraction, relative URL resolution |
| `html_parser.asm` | Streaming byte-by-byte HTML parser (6 states: text, tag, entity, attr name/value, comment) |
| `html_tags.asm` | Tag handlers (34 tags), attribute extraction (href, src), link/image storage |
| `html_entities.asm` | Tag name lookup table, HTML entity decoding (named + numeric) |
| `renderer.asm` | Text layout: word wrapping, indentation, pagination, `--More--` prompt, skip-to-heading |
| `keyboard.asm` | Keyboard input via CIO K: device, line editing with backspace/escape |
| `ui.asm` | UI: URL bar, status bar, main event loop, link following, error display |
| `img_fetch.asm` | Image download, URL resolution, server-side converter integration |
| `history.asm` | URL history stack (16 entries with scroll position) |
| `mouse.asm` | ST mouse driver: Timer 1 IRQ (quadrature sampling) + VBI (cursor), MEMAC B safe |
| `title.asm` | Welcome screen layout and strings |
| `data.asm` | Version string, default URL, large buffer allocations ($8800+) |

## Image Support

Images on web pages appear as clickable `[N]IMG` links in blue. Clicking downloads the image through a server-side converter that resizes and converts to VBXE 256-color format (up to 320×192 pixels), then displays fullscreen. Press any key to return to the page. Image download uses FujiNet N2: device so the page connection (N1:) stays open — you can view images during page scrolling and continue browsing afterwards. Direct image URLs (.png, .jpg, .gif) are also supported.

## Architecture

- **Code**: starts at $3000, critical MEMAC B routines stay below $4000
- **VBXE VRAM**: screen buffer $0000, BCBs $1300, XDL $1400, font $2000, images/gradient $3000+
- **MEMAC B window**: $4000–$7FFF maps to VBXE VRAM bank 0 when active
- **FujiNet**: N1: for page download, N2: for image download (simultaneous connections)
- **Interrupts**: Timer 1 IRQ (mouse sampling ~985 Hz) + VBI (deferred cursor update), both with MEMAC B shadow register for safe nesting
- **Buffers**: $8800+ (URL buffer, RX buffer, history stack, link URL table, image queue)

## Credits

- [MADS](https://github.com/tebe6502/Mad-Assembler) assembler by Tomasz Biela
- VBXE graphics mode reference from [st2vbxe](https://github.com/pfusik/st2vbxe) by Piotr Fusik
- Mouse driver based on GOS (flashjazzcat) quadrature decoder
- Built with assistance from Claude AI (Anthropic)

## License

MIT
