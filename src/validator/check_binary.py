"""Sections 11-12: XEX binary check, real render test."""
import os, re, urllib.request
from .atari_font import ascii_to_screen
from .asm_utils import strip_html


def check(files, ctx):
    errors = []
    warnings = []
    ok_count = 0

    int2asc = ctx['int2asc']
    vbxe_sc_map = ctx['vbxe_sc_map']
    ch_space = ctx['ch_space']
    has_a2s = ctx['has_a2s']
    sub_value = ctx['sub_value']
    project_dir = ctx['project_dir']

    # --- 11. XEX binary check ---
    _xex_candidates = [
        os.path.join(project_dir, 'bin', 'browser.xex'),
        os.path.join(project_dir, 'browser.xex'),
    ]
    xex_path = next((p for p in _xex_candidates if os.path.exists(p)), _xex_candidates[0])
    if os.path.exists(xex_path):
        xex_size = os.path.getsize(xex_path)
        print(f"  [OK]   BUILD: browser.xex exists ({xex_size} bytes)")
        ok_count += 1

        if int2asc:
            with open(xex_path, 'rb') as f:
                xex_data = f.read()
            needle = bytes(int2asc)
            if needle in xex_data:
                pos = xex_data.index(needle)
                print(f"  [OK]   BUILD: int2asc {int2asc} found in XEX at offset ${pos:04X}")
                ok_count += 1
            else:
                errors.append(f"BUILD: int2asc {int2asc} NOT found in XEX binary!")

            if ch_space is not None:
                fill = bytes([ch_space, 0x00])
                if fill in xex_data:
                    print(f"  [OK]   BUILD: fill pattern ${ch_space:02X},00 found in XEX")
                    ok_count += 1
    else:
        warnings.append(f"BUILD: browser.xex not found - run: mads browser.asm -o:browser.xex")

    # --- 12. REAL RENDER TEST ---
    print()
    print("  --- REAL RENDER TEST ---")
    try:
        html = None
        html_source = None
        try:
            html = urllib.request.urlopen('http://127.0.0.1:8080/index.html', timeout=3).read().decode('utf-8')
            html_source = 'http://127.0.0.1:8080/index.html'
        except Exception:
            _test_html_candidates = [
                os.path.join(project_dir, 'tools', 'numen.html'),
                os.path.join(project_dir, 'tools', 't.html'),
            ]
            for hp in _test_html_candidates:
                if os.path.exists(hp):
                    with open(hp, 'r', encoding='utf-8', errors='ignore') as hf:
                        html = hf.read()
                    html_source = hp
                    break
        if not html:
            raise FileNotFoundError("No test HTML found (no server, no tools/*.html)")
        print(f"  [OK]   NET: loaded test HTML from {html_source} ({len(html)} bytes)")
        ok_count += 1

        text = strip_html(html)

        bad = []
        good = 0
        for ch in text:
            a = ord(ch)
            if a < 0x20 or a > 0x7E:
                continue

            sc = ascii_to_screen(a, sub_value) if has_a2s else a
            displayed = vbxe_sc_map.get(sc)
            if displayed == ch:
                good += 1
            else:
                if int2asc:
                    page = sc // 32
                    isc = int2asc[page] * 32 + (sc % 32) if page < 4 else -1
                else:
                    isc = sc
                from .atari_font import gfx_name
                if displayed:
                    show = f"'{displayed}'"
                else:
                    show = gfx_name(isc) if isc >= 0 else '[unknown]'
                bad.append((ch, a, sc, show))

        if not bad:
            print(f"  [OK]   RENDER: {good} chars checked, all display correctly")
            ok_count += 1
            preview = ''
            for ch in text[:200]:
                a = ord(ch)
                if a < 0x20 or a > 0x7E:
                    preview += '?'
                else:
                    sc = ascii_to_screen(a, sub_value) if has_a2s else a
                    preview += vbxe_sc_map.get(sc, '?')
            print(f"  [OK]   PREVIEW: \"{preview[:80]}\"")
            ok_count += 1
        else:
            detail = f"{len(bad)} of {len(bad)+good} rendered chars will show WRONG on Atari:\n"
            for ch, a, sc, show in bad[:8]:
                detail += f"           '{ch}' ASCII=${a:02X} -> sc ${sc:02X} -> Atari shows: {show}\n"
            if len(bad) > 8:
                detail += f"           ... and {len(bad)-8} more"
            errors.append(f"RENDER: {detail}")

            preview = ''
            for ch in text[:200]:
                a = ord(ch)
                if a < 0x20 or a > 0x7E:
                    preview += '?'
                else:
                    sc = ascii_to_screen(a, sub_value) if has_a2s else a
                    preview += vbxe_sc_map.get(sc, '\u2666')
            warnings.append(f"PREVIEW (garbled): \"{preview[:80]}\"")

    except Exception as e:
        warnings.append(f"NET: cannot test render - {e}")

    return ok_count, errors, warnings
