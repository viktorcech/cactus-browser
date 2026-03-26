"""Sections 1-5: font mapping, ROM cross-check, constants, conversion, charmap."""
import re
from .atari_font import (INTERNAL_SC_TO_CHAR, gfx_name, build_vbxe_sc_to_char,
                          ascii_to_screen, parse_rom_font, rom_label_to_char)
from .asm_utils import (find_in_asm, get_proc, get_proc_numbered, fmt_asm_lines,
                         find_proc_in_listing, cpu_trace, get_const)


def check(files, ctx):
    errors = []
    warnings = []
    ok_count = 0

    listing = ctx['listing']
    rom_asm_path = ctx['rom_asm_path']

    # --- 1. Font mapping ---
    int2asc = None
    hits = find_in_asm(files, r'int2asc\s+dta\s+')
    if hits:
        m = re.search(r'dta\s+(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)', hits[0][2])
        if m:
            int2asc = [int(m.group(i+1)) for i in range(4)]
            print(f"  [OK]   FONT: int2asc={int2asc}")
            ok_count += 1
        else:
            errors.append("FONT: cannot parse int2asc")
    else:
        errors.append("FONT: int2asc not found")

    # Build the actual VBXE font mapping
    if int2asc:
        vbxe_sc_map = build_vbxe_sc_to_char(int2asc)
    else:
        vbxe_sc_map = dict(INTERNAL_SC_TO_CHAR)

    # Store in ctx for other checks
    ctx['int2asc'] = int2asc
    ctx['vbxe_sc_map'] = vbxe_sc_map

    # --- 2. ROM font cross-check ---
    print()
    print("  --- ROM FONT VERIFICATION ---")
    rom_chars = parse_rom_font(rom_asm_path)
    if rom_chars:
        print(f"  [OK]   ROM: parsed {len(rom_chars)} chars from Atari_XL_OS_Rev.2.asm")
        ok_count += 1

        # Verify our INTERNAL_SC_TO_CHAR matches the ROM
        rom_mismatches = []
        for sc, label in rom_chars.items():
            rom_ch = rom_label_to_char(label)
            our_ch = INTERNAL_SC_TO_CHAR.get(sc)
            if rom_ch is not None and our_ch != rom_ch:
                rom_mismatches.append((sc, label, rom_ch, our_ch))
            elif rom_ch is None and our_ch is not None:
                rom_mismatches.append((sc, label, None, our_ch))

        if not rom_mismatches:
            print(f"  [OK]   ROM: internal screen code table matches ROM font")
            ok_count += 1
        else:
            detail = f"{len(rom_mismatches)} mismatches between validator and ROM:\n"
            for sc, label, rom_ch, our_ch in rom_mismatches[:8]:
                detail += f"           sc ${sc:02X} ROM='{label}' -> "
                detail += f"expected '{rom_ch}' but validator has '{our_ch}'\n"
            errors.append(f"ROM: {detail}")

        # Show the VBXE font mapping after int2asc remapping
        if int2asc:
            print(f"  [INFO] ROM: VBXE font layout with int2asc={int2asc}:")
            for page in range(4):
                rom_page = int2asc[page]
                # Collect char labels from ROM for this page
                chars_in_page = []
                for i in range(32):
                    isc = rom_page * 32 + i
                    label = rom_chars.get(isc, '?')
                    chars_in_page.append(label)
                first = chars_in_page[0]
                last = chars_in_page[-1]
                vbxe_range = f"${page*32:02X}-${page*32+31:02X}"
                rom_range = f"${rom_page*32:02X}-${rom_page*32+31:02X}"
                print(f"           sc {vbxe_range} <- ROM {rom_range}: {first} ... {last}")
    else:
        warnings.append(f"ROM: source not found at {rom_asm_path}")

    # --- 3. Constants check ---
    print()
    print("  --- CONSTANTS CHECK ---")
    chbase_val = get_const(files, 'CHBASE_VAL')
    vram_font = get_const(files, 'VRAM_FONT')
    ch_space = get_const(files, 'CH_SPACE')

    if chbase_val is not None and vram_font is not None:
        expected_chbase = vram_font // 0x800
        if chbase_val == expected_chbase:
            print(f"  [OK]   CONST: CHBASE_VAL={chbase_val} matches VRAM_FONT=${vram_font:04X} / $800")
            ok_count += 1
        else:
            errors.append(f"CONST: CHBASE_VAL={chbase_val} but VRAM_FONT=${vram_font:04X} needs {expected_chbase}!")
    else:
        warnings.append("CONST: cannot verify CHBASE_VAL/VRAM_FONT")

    if ch_space is not None and int2asc:
        # With the VBXE font mapping, what screen code shows a space?
        space_sc = None
        for sc, ch in vbxe_sc_map.items():
            if ch == ' ':
                space_sc = sc
                break
        if space_sc is not None and ch_space == space_sc:
            print(f"  [OK]   CONST: CH_SPACE=${ch_space:02X} matches font space position")
            ok_count += 1
        elif space_sc is not None:
            errors.append(
                f"CONST: CH_SPACE=${ch_space:02X} but font has space at sc ${space_sc:02X}!\n"
                f"         Word wrapping and screen clearing will use wrong character!")
        else:
            warnings.append("CONST: cannot find space in VBXE font mapping")

    # Store for other checks
    ctx['ch_space'] = ch_space

    # --- 4. ascii_to_screen - parse what it does ---
    print()
    print("  --- CONVERSION CHECK ---")
    fname, line, body = get_proc(files, 'ascii_to_screen')
    has_a2s = False
    sub_value = 0x20
    if fname:
        has_a2s = True
        m_sub = re.search(r'sbc\s+#\$([0-9A-Fa-f]+)', body, re.IGNORECASE)
        if m_sub:
            sub_value = int(m_sub.group(1), 16)
            print(f"  [INFO] CONV: ascii_to_screen subtracts ${sub_value:02X} ({fname}:{line})")
        else:
            warnings.append(f"CONV: ascii_to_screen found but cannot parse subtraction ({fname}:{line})")
    else:
        sub_value = 0
        print(f"  [INFO] CONV: no ascii_to_screen - raw ASCII used as screen codes")

    ctx['has_a2s'] = has_a2s
    ctx['sub_value'] = sub_value

    # --- 5. CHARMAP CHECK: verify conversion + font mapping for ALL printable ASCII ---
    bad_chars = []
    good_chars = 0
    for a in range(0x20, 0x7F):
        ch = chr(a)
        sc = ascii_to_screen(a, sub_value) if has_a2s else a
        displayed = vbxe_sc_map.get(sc)
        if displayed == ch:
            good_chars += 1
        else:
            if int2asc:
                page = sc // 32
                offset = sc % 32
                rom_page = int2asc[page] if page < 4 else -1
                internal_sc = rom_page * 32 + offset if rom_page >= 0 else -1
            else:
                internal_sc = sc
            if displayed:
                show = f"'{displayed}'"
            else:
                show = gfx_name(internal_sc) if internal_sc >= 0 else '[unknown]'
            bad_chars.append((ch, a, sc, internal_sc, show))

    # Separate Atari font limitations (no glyph exists) from real bugs (wrong glyph)
    atari_limited = [b for b in bad_chars if b[4].startswith('[')]  # graphics = no glyph
    real_bugs = [b for b in bad_chars if not b[4].startswith('[')]  # shows wrong char

    if not bad_chars:
        print(f"  [OK]   CHARMAP: all {good_chars} printable ASCII chars map correctly")
        ok_count += 1
    elif not real_bugs:
        # Only Atari font limitations, no real bugs
        chars = ''.join(b[0] for b in atari_limited)
        print(f"  [OK]   CHARMAP: {good_chars} chars OK, {len(atari_limited)} Atari-limited: {chars}")
        ok_count += 1
        warnings.append(
            f"CHARMAP: {len(atari_limited)} ASCII chars have no Atari font glyph: {chars}\n"
            f"         These will show as graphics symbols (Atari hardware limitation)")
    else:
        detail = f"{len(real_bugs)} of {len(real_bugs)+good_chars} printable ASCII chars display WRONG:\n"
        for ch, a, sc, isc, show in real_bugs[:12]:
            detail += f"           '{ch}' ASCII=${a:02X} -> sc ${sc:02X} -> internal ${isc:02X} -> shows {show}\n"
        if len(real_bugs) > 12:
            detail += f"           ... and {len(real_bugs)-12} more\n"

        broken_upper = sum(1 for _, a, _, _, _ in real_bugs if 0x41 <= a <= 0x5A)
        broken_lower = sum(1 for _, a, _, _, _ in real_bugs if 0x61 <= a <= 0x7A)
        broken_digit = sum(1 for _, a, _, _, _ in real_bugs if 0x30 <= a <= 0x39)
        broken_space = sum(1 for _, a, _, _, _ in real_bugs if a == 0x20)
        broken_punct = len(real_bugs) - broken_upper - broken_lower - broken_digit - broken_space

        parts = []
        if broken_space: parts.append("SPACE")
        if broken_digit: parts.append(f"{broken_digit} digits")
        if broken_upper: parts.append(f"{broken_upper} uppercase")
        if broken_lower: parts.append(f"{broken_lower} lowercase")
        if broken_punct: parts.append(f"{broken_punct} punctuation")
        detail += f"           Broken: {', '.join(parts)}\n"

        if int2asc and sub_value == 0x20 and int2asc != [0, 0, 0, 0]:
            detail += (
                f"           HINT: int2asc={int2asc} rearranges font to ASCII order,\n"
                f"           but ascii_to_screen subtracts ${sub_value:02X} = double conversion!\n"
                f"           With this font layout, raw ASCII values should go to VRAM directly.\n"
                f"           FIX: Remove ascii_to_screen call from render path, or change int2asc\n"
                f"           to [0,0,0,0] (identity) if you want standard Atari screen codes."
            )

        # Show the conversion proc code + CPU trace if it exists
        if has_a2s:
            _, a2s_line, _, a2s_numbered = get_proc_numbered(files, 'ascii_to_screen')
            if a2s_numbered:
                detail += f"\n           ascii_to_screen code:\n"
                detail += fmt_asm_lines(a2s_numbered)

            a2s_insns = find_proc_in_listing(listing, 'ascii_to_screen')
            if a2s_insns:
                # Trace with 'A' (uppercase) and 'a' (lowercase)
                for test_ch, test_val in [('A', 0x41), ('a', 0x61), (' ', 0x20)]:
                    detail += f"\n           CPU trace: ascii_to_screen('{test_ch}' = ${test_val:02X}):\n"
                    detail += cpu_trace(a2s_insns,
                        regs={'A': test_val, 'X': 0, 'Y': 0, 'S': 0xEB, 'P': 0x30},
                        scenario=f"Input: '{test_ch}' (${test_val:02X})")

        # Show font mapping summary
        if int2asc:
            detail += f"\n           VBXE font page mapping (int2asc={int2asc}):\n"
            for pg in range(4):
                rp = int2asc[pg]
                sc_lo, sc_hi = pg*32, pg*32+31
                isc_lo, isc_hi = rp*32, rp*32+31
                pg_chars = [INTERNAL_SC_TO_CHAR.get(rp*32+i, '\u2666') for i in range(32)]
                sample = ''.join(pg_chars[:8]) + '..' + ''.join(pg_chars[-4:])
                detail += f"           sc ${sc_lo:02X}-${sc_hi:02X} -> ROM ${isc_lo:02X}-${isc_hi:02X}: {sample}\n"

        errors.append(f"CHARMAP: {detail}")

    return ok_count, errors, warnings
