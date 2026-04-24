# Cactus browser for Atari XE/XL

80-column web browser for Atari 8-bit computers with VBXE, FujiNet, and ST mouse.

![screenshot](https://img.shields.io/badge/status-beta-blue)

## Screenshots

<p align="center">
  <img src="screens/1.png" alt="Cactus browsing" width="33%">
  <img src="screens/2.png" alt="Cactus browsing" width="33%">
  <img src="screens/3.png" alt="Cactus browsing" width="33%">
</p>

## Requirements

- Atari 800XL/130XE or compatible (64KB RAM minimum)
- [VBXE](http://lotharek.pl/productdetail.php?id=46) (VideoBoard XE) — FX core
- [FujiNet](https://fujinet.online/) — WiFi multi-peripheral with N: device HTTP support
- Atari ST mouse in joystick port 2 (optional — keyboard navigation also supported)
- Emulator: [Altirra](https://www.virtualdub.org/altirra.html) with VBXE + FujiNet-PC

## Running

### From SpartaDOS X (recommended)

Recommended for real hardware: [SpartaDOS X](https://atariwiki.org/wiki/Wiki.jsp?page=SpartaDOS%20X) with FujiNet enables hi-SIO (high-speed SIO), which significantly speeds up page downloads over the N: device.

At the SDX command line, just run: `cactus.xex`

### From Altirra emulator

1. System → Devices → Add → Video Board XE (VBXE)
2. System → uncheck BASIC (important!)
3. File → Boot Image → select `cactus.xex`

## Features

- **80×29 text display** — VBXE overlay mode with 11-color palette and per-character attributes
- **GMON gradient title screen** — graphical blue gradient banner using VBXE graphics mode
- **ST mouse** — point and click on links, works during browsing and page scrolling (`--More--` prompt)
- **TAB navigation** — cycle through visible links with TAB, follow with RETURN (no mouse needed)
- **HTML rendering** — 47 tags including headings (h1–h6), paragraphs, links, lists (ul/ol with bullets and numbering), bold, italic, underline, superscript, subscript, tables, blockquotes, code/pre, definition lists (dt/dd), horizontal rules, images, HTML5 semantic tags (article, section, nav, header, footer, main, aside)
- **HTML entity decoding** — `&amp;` `&lt;` `&gt;` `&nbsp;` `&quot;` and numeric `&#NNN;`
- **HTML comment support** — `<!-- -->` properly parsed and skipped
- **ANSI colors** — `ESC[...m` sequences render as colored text
- **UTF-8 support** — accented Latin characters converted to ASCII
- **Image viewing** — inline images shown as clickable `[N]IMG` links, fullscreen centered 248-color display (up to 320×192) via server-side converter
- **Up to 64 links per page** with palette-encoded link detection, recycled on each page scroll
- **Word wrapping** — intelligent wrapping at word boundaries with indentation support
- **Skip to heading** — press H during `--More--` prompt to jump past navigation menus to next heading
- **Find in page** — Ctrl+F (or F) opens a `Find:` prompt, highlights matches in yellow, and reports visible + total counts for the whole page
- **Bookmarks** — Ctrl+B opens a 10-slot bookmark window stored on D1: for quick recall and saving of URLs
- **Built-in web search** — type any query without a dot in the URL bar to search the web via turiecfoto.sk
- **URL navigation** with address bar, auto-prefix, and case normalization
- **Relative URL resolution** — links and images resolved against base URL
- **Fragment anchors** — `#name` in URL jumps to matching spot on the page
- **History** — back navigation with scroll position preservation (16 entries)
- **Optional proxy mode** — toggle with P key, strips scripts/styles for cleaner pages
- **VRAM page buffer** — entire page downloaded to VRAM ($14000+), then rendered offline. N1: is free for image downloads during rendering
- **HTTP/HTTPS support** — FujiNet handles TLS natively
- **Optimized HTTP** — skips redundant FujiNet STATUS calls during bulk transfer
- **PAL/NTSC detection** — auto-adapts timing for both TV systems
- **CRT overscan border** — 8-scanline top border ensures URL bar is visible on real TVs
- **Build timestamps** — welcome screen shows build date and time

## Controls

| Input | Action |
|-------|--------|
| **Mouse click** | Follow link / view image |
| **TAB** | Cycle to next link on screen |
| **Return** | Follow selected link / scroll next page |
| **Space** | Scroll to next page |
| **U** | Enter URL or search query (no dot = web search via turiecfoto.sk) |
| **B** | Back (history) |
| **Ctrl+B** | Open bookmarks window (10 slots on D1:) |
| **Ctrl+F** / **F** | Find text on page |
| **H** | Skip to next heading (during `--More--`) |
| **I** | Help / info screen |
| **P** | Toggle proxy mode |
| **Q** | Quit (also stops page loading) |

## Building

Requires [MADS](https://github.com/tebe6502/Mad-Assembler) (Mad Assembler).

```bash
./build.sh
```

The build script generates a build timestamp in `build_stamp.asm` and produces `bin/cactus.xex`.

Manual build:
```bash
./mads.exe cactus.asm -o:cactus.xex
```

## Source Files

| File | Description |
|------|-------------|
| `cactus.asm` | Main program, entry point, module includes |
| `vbxe_const.asm` | VBXE registers, XDL flags, VRAM layout, system equates, zero-page variables, macros |
| `vbxe_detect.asm` | VBXE hardware detection (FX core version check) |
| `vbxe_init.asm` | VBXE initialization: XDL, font copy, blitter BCBs, palette (8 colors + gradient + 64 link colors) |
| `vbxe_text.asm` | Text engine: putchar, print, cls, scroll, fill, VRAM read/write helpers |
| `vbxe_gfx.asm` | Graphics: image VRAM alloc, pixel streaming, GMON XDL, fullscreen display, page buffer, title gradient |
| `fujinet.asm` | FujiNet N: device SIO layer (open, status, read, close) |
| `http.asm` | HTTP workflow: two-phase download (network→VRAM) + render (VRAM→parser) |
| `url.asm` | URL normalization, prefix handling, base URL extraction, relative URL resolution |
| `html_parser.asm` | Streaming byte-by-byte HTML parser (7 states: text, tag, entity, attr name/value, skip, comment) |
| `html_tags.asm` | Tag handlers (47 tags), attribute extraction (href, src), link/image storage |
| `html_entities.asm` | Tag name lookup table, HTML entity decoding (named + numeric) |
| `renderer.asm` | Text layout: word wrapping, indentation, pagination, `--More--` prompt, skip-to-heading |
| `keyboard.asm` | Keyboard input via CIO K: device, line editing with backspace/escape |
| `ui.asm` | UI: URL bar, status bar, main event loop, link following, error display |
| `img_fetch.asm` | Image download: header/palette/pixel streaming, URL resolution, converter integration |
| `history.asm` | URL history stack (16 entries with scroll position) |
| `mouse.asm` | ST mouse driver: Timer 1 IRQ (quadrature sampling) + VBI (cursor), MEMAC B safe |
| `title.asm` | Welcome screen layout and strings, help screen |
| `bookmarks.asm` | Bookmarks window (10 slots), D1: persistence |
| `find.asm` | Find-in-page: prompt, viewport highlight, full-page count |
| `data.asm` | Version string, large buffer allocations ($8800+) |
| `build_stamp.asm` | Auto-generated build timestamp (created by `build.sh`) |

## Image Support

Images on web pages appear as clickable `[N]IMG` links in blue. Clicking downloads the image through a server-side converter that resizes, centers on a black canvas, and converts to VBXE 248-color format (up to 320×192 pixels), then displays fullscreen. Press any key to return to the page.

The browser uses a two-phase architecture: the HTML page is first downloaded entirely into the VRAM page buffer, then N1: is closed. During rendering, image clicks reopen N1: for the converter — no second FujiNet connection needed. After viewing an image, the parser continues from the exact position in the buffered page.

## Architecture

- **Code**: starts at $3000, stays below $4000 (MEMAC B window starts at $4000)
- **VBXE VRAM**: screen $0000, BCBs $1300, XDL $1400, font $2000, images $3000+, page buffer $14000+
- **MEMAC B window**: $4000–$7FFF maps to VBXE VRAM banks when active
- **FujiNet**: single N1: device — page download closes before image fetch
- **Page buffer**: HTML downloaded to VRAM ($14000+, bank 5+), rendered offline from VRAM
- **Interrupts**: Timer 1 IRQ (mouse sampling ~985 Hz) + VBI (deferred cursor update), both with MEMAC B shadow register for safe nesting
- **Buffers**: $8800+ (URL buffer, RX buffer, history stack, link URL table, image palette)

## Credits

- [MADS](https://github.com/tebe6502/Mad-Assembler) assembler by Tomasz Biela
- VBXE graphics mode reference from [st2vbxe](https://github.com/pfusik/st2vbxe) by Piotr Fusik
- Mouse driver based on GOS (flashjazzcat) quadrature decoder
- Built with assistance from Claude AI (Anthropic)

## License

MIT
