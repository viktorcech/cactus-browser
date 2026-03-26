"""Atari font/charset maps, gfx_name, ROM font parsing."""

# ---------------------------------------------------------------------------
# Atari XL OS Rev.2 INTERNAL screen code -> character mapping
# This is the native ROM font order (DCSORG at $E000).
# 4 pages of 32 chars each (128 chars total, 8 bytes per glyph).
# ---------------------------------------------------------------------------
INTERNAL_SC_TO_CHAR = {}

# Page 0: sc $00-$1F  (space, punctuation, digits)
INTERNAL_SC_TO_CHAR[0x00] = ' '
for i, c in enumerate('!"#$%&\'()*+,-./'): INTERNAL_SC_TO_CHAR[0x01+i] = c
for i in range(10): INTERNAL_SC_TO_CHAR[0x10+i] = chr(48+i)  # 0-9
for i, c in enumerate(':;<=>?'): INTERNAL_SC_TO_CHAR[0x1A+i] = c

# Page 1: sc $20-$3F  (@, A-Z, [\]^_)
INTERNAL_SC_TO_CHAR[0x20] = '@'
for i in range(26): INTERNAL_SC_TO_CHAR[0x21+i] = chr(65+i)  # A-Z
for i, c in enumerate('[\\]^_'): INTERNAL_SC_TO_CHAR[0x3B+i] = c

# Page 2: sc $40-$5F  (graphics: heart, lines, arrows, clubs...)
# These have no printable ASCII equivalent -> not in the dict

# Page 3: sc $60-$7F  (diamond, lowercase a-z, spade, |, ...)
# $60 = diamond (graphics), $7B = spade (graphics), $7D-$7F = graphics
for i in range(26): INTERNAL_SC_TO_CHAR[0x61+i] = chr(97+i)  # a-z
INTERNAL_SC_TO_CHAR[0x7C] = '|'  # pipe has a real glyph in XL font

# Graphics character names (for error messages)
_GFX_NAMES = {
    0x40: 'heart', 0x41: 'box-left', 0x42: 'box-right', 0x43: 'corner-lr',
    0x44: 'tee-right', 0x45: 'corner-ur', 0x46: 'slant-r', 0x47: 'slant-l',
    0x48: 'tri-r', 0x49: 'block-lr', 0x4A: 'tri-l', 0x4B: 'block-ur',
    0x4C: 'block-ul', 0x4D: 'bar-top', 0x4E: 'bar-bot', 0x4F: 'block-ll',
    0x50: 'club', 0x51: 'corner-ul', 0x52: 'bar-mid', 0x53: 'cross',
    0x54: 'circle', 0x55: 'block-bot', 0x56: 'box-left', 0x57: 'tee-up',
    0x58: 'tee-down', 0x59: 'block-left', 0x5A: 'corner-ll',
    0x5B: 'esc-gfx', 0x5C: 'arrow-up', 0x5D: 'arrow-down',
    0x5E: 'arrow-left', 0x5F: 'arrow-right',
    0x60: 'diamond',
    0x7B: 'spade', 0x7C: 'pipe', 0x7D: 'clr-gfx', 0x7E: 'bs-gfx', 0x7F: 'tab-gfx',
}


def gfx_name(internal_sc):
    """Return human-readable name for an internal screen code."""
    name = _GFX_NAMES.get(internal_sc)
    return f'[{name}]' if name else f'[gfx ${internal_sc:02X}]'


def build_vbxe_sc_to_char(int2asc):
    """Build VBXE screen code -> displayed character map, accounting for
    the int2asc font page remapping done by copy_font.

    copy_font copies ROM page int2asc[X] into VBXE font page X.
    So VBXE screen code (page*32 + offset) shows the glyph from
    ROM internal screen code (int2asc[page]*32 + offset).
    """
    result = {}
    for page in range(4):
        rom_page = int2asc[page]
        for i in range(32):
            vbxe_sc = page * 32 + i
            internal_sc = rom_page * 32 + i
            ch = INTERNAL_SC_TO_CHAR.get(internal_sc)
            if ch is not None:
                result[vbxe_sc] = ch
    return result


def ascii_to_screen(a, sub_value=0x20):
    """Simulate the ASM ascii_to_screen conversion."""
    if a >= 0x20:
        return (a - sub_value) & 0x7F
    return a


# ---------------------------------------------------------------------------
# ROM font verification
# ---------------------------------------------------------------------------
def parse_rom_font(rom_path):
    """Parse the Atari ROM ASM source to extract font character labels.
    Returns dict of internal_screen_code -> label string.
    """
    import os, re
    if not os.path.exists(rom_path):
        return None

    rom_chars = {}
    in_font = False
    with open(rom_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            # Detect start: ORG DCSORG marks the domestic character set data
            stripped = line.strip()
            if not in_font:
                # Look for "ORG DCSORG" directive (not DCSORG EQU ...)
                if re.match(r'ORG\s+DCSORG', stripped):
                    in_font = True
                continue
            # Stop at next ORG or SUBTTL (end of font data)
            if re.match(r'ORG\s', stripped) or (';SUBTTL' in stripped and len(rom_chars) > 10):
                break

            # Parse: .byte $XX,...  ;$HH - name
            m = re.search(r';\$([0-9A-Fa-f]{2})\s*-\s*(.+)', line)
            if m:
                sc = int(m.group(1), 16)
                name = m.group(2).strip()
                rom_chars[sc] = name

    return rom_chars if rom_chars else None


def rom_label_to_char(label):
    """Convert ROM font label to expected ASCII character (or None for graphics)."""
    raw = label.strip()
    lower = raw.lower()
    if lower == 'space':
        return ' '
    if len(raw) == 1 and raw.isalpha():
        return raw  # preserve case: 'A' -> 'A', 'a' -> 'a'
    if len(raw) == 1:
        return raw
    # Named characters
    names = {
        'asterisk': '*', 'plus': '+', 'comma': ',', 'minus': '-',
        'period': '.', 'colon': ':', 'semicolon': ';', 'underline': '_',
    }
    if lower in names:
        return names[lower]
    # Graphics - no ASCII equivalent
    gfx_keywords = ['heart', 'club', 'diamond', 'spade', 'window', 'box',
                     'solid', 'slant', 'arrow', 'bar', 'block', 'corner',
                     'display', 'card', 'mid', 'tee', 'cross', 'circle']
    if any(kw in lower for kw in gfx_keywords):
        return None
    return None
