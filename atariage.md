**VBXE Web Browser beta 01** — a real web browser for the Atari 8-bit!

**Requirements:** Atari XL/XE + VBXE + FujiNet

**Display**
- 80x29 text mode via VBXE overlay (text + attribute per character)
- 11 color attributes — headings, links, bold, italic, code, etc.
- Gradient GMON title screen
- PAL/NTSC auto-detection

**HTML Support**
- H1-H6 headings (color-coded by level)
- Paragraphs, line breaks, horizontal rules
- Bold, italic, underline, superscript, subscript, code
- Ordered and unordered lists (nested)
- Blockquotes with indentation
- Tables (with | cell separators)
- Preformatted text (`<pre>`)
- HTML5 semantic tags (article, section, nav, header, footer, main, aside)
- HTML comments, entity decoding (&amp; &lt; &nbsp; etc.)
- Script/style/form tags filtered out
- `<title>` displayed in title bar
- UTF-8 multi-byte sequences filtered (no UTF-8 font on Atari)

**Images**
- PNG, JPG support via server-side converter
- Full-screen 320x192 display, 256 colors
- Click image links during browsing — fetched inline
- Deferred image fetch during active page download

**Navigation**
- **Mouse**: Atari ST mouse (port 2), click links, red inverted cursor
- **Keyboard**: U=URL, B=Back, Q=Quit, P=Proxy, Space=Next page, H=Skip to heading
- **TAB navigation**: cycle through visible links, RETURN to follow
- Up to 64 clickable links per screen
- 16-level browser history with scroll position restore
- Built-in search engine (type query without '.' in URL bar)

**Networking**
- FujiNet N: device, SIO protocol
- HTTP and HTTPS support
- Two-phase download: page buffered to VRAM, then rendered offline
- Download progress indicator (kB counter)
- Optional proxy mode (P to toggle)

**UI**
- URL bar (top), page title bar, content area, status bar
- Paginated output with --More-- prompt
- Word wrapping at 80 columns
- Proxy URL hidden in URL bar (shows real page URL)
