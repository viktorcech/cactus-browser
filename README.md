# VBXE Web Browser for Atari XE/XL

80-column web browser for Atari 8-bit computers with VBXE graphics expansion and ST mouse support.

![screenshot](https://img.shields.io/badge/status-alpha-orange)

## Status

**Alpha 37** - early development, testing on real hardware. Help is welcome!

## Requirements

- Atari 800XL/130XE or compatible (64KB RAM minimum)
- [VBXE](http://lotharek.pl/productdetail.php?id=46) (VideoBoard XE) - FX core v1.2x
- [FujiNet](https://fujinet.online/) - WiFi multi-peripheral with HTTP support
- Atari ST mouse (joystick port 2)
- Emulator: [Altirra](https://www.virtualdub.org/altirra.html) with VBXE + FujiNet-PC

## Features

- **VBXE 80-column text** using overlay mode with color attributes
- **ST mouse support** - point and click on links, works in all screens including --More-- prompt
- **HTML parser**: headings (h1-h3), paragraphs, links, lists (ul/ol), bold, italic, tables, blockquotes, code/pre, entities
- **Image viewing** - images shown as clickable `[N]IMG` links, click to view fullscreen via vbxe.php converter (256-color, up to 320x184)
- **URL navigation** with address bar input
- **History** with back navigation
- **Link following** - click with mouse or press link number
- **FujiNet networking** - HTTP via N: device SIO

## VBXE Display

The browser uses VBXE overlay in text mode (TMON) for 80-column display:

- 80x24 character grid with per-character color attributes
- 7 colors: white (text), blue (links), orange (headings), green (URL bar), red (errors), gray (decorative), yellow (status/highlighted links)
- Font stored in VBXE VRAM ($2000)
- Fullscreen image display via GMON overlay with 256-color palette

## Controls

| Input | Action |
|-------|--------|
| **Mouse click** | Follow link / view image |
| **U** | Enter URL |
| **B** | Back (history) |
| **Q** | Quit / return to welcome |
| **Space/Return** | Next page (at --More-- prompt) |

## Building

Requires [MADS](https://github.com/tebe6502/Mad-Assembler) (Mad Assembler).

```bash
mads src/browser.asm -o:bin/browser.xex -l:bin/browser.lab
```

## Source Files

| File | Description |
|------|-------------|
| `browser.asm` | Main program, entry point |
| `vbxe_const.asm` | VBXE registers, system equates, ZP variables, macros |
| `vbxe_detect.asm` | VBXE hardware detection |
| `vbxe_init.asm` | VBXE initialization (XDL, palette, font, blitter) |
| `vbxe_text.asm` | 80-column text rendering engine |
| `vbxe_gfx.asm` | Graphics mode for image display (GMON, palette, pixel streaming) |
| `img_fetch.asm` | Image download, URL resolve, vbxe.php converter integration |
| `fujinet.asm` | FujiNet N: device SIO layer |
| `network.asm` | Network abstraction layer |
| `http.asm` | HTTP GET workflow, URL handling, relative URL resolution |
| `html_parser.asm` | Streaming HTML tag/entity parser (32 tags) |
| `renderer.asm` | Text layout, word wrapping, pagination |
| `keyboard.asm` | Keyboard input via CIO K: device |
| `ui.asm` | UI: URL bar, status bar, navigation, main loop |
| `mouse.asm` | ST mouse driver (Timer IRQ + VBI, quadrature decoding) |
| `history.asm` | URL history stack (16 entries) |
| `data.asm` | Buffers and string data |

## Image Support

Images on web pages are shown as clickable `[N]IMG` links with blue color. Clicking downloads the image through a server-side converter (`vbxe.php`) that resizes and converts to VBXE 256-color format, then displays fullscreen.

## Credits

- [MADS](https://github.com/tebe6502/Mad-Assembler) assembler by Tomasz Biela
- 850 handler approach based on [Ice-T XE](https://github.com/ivop/Ice-T-XE) by Itay Chamiel
- VBXE graphics mode reference from [st2vbxe](https://github.com/pfusik/st2vbxe) by Piotr Fusik
- Mouse driver based on GOS (flashjazzcat) quadrature decoder

## License

MIT
