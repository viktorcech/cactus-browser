"""Section 10h: constants, ZP, screen layout validation."""
import re
from .asm_utils import find_in_asm, get_const


def check(files, ctx):
    errors = []
    warnings = []
    ok_count = 0

    print()
    print("  --- CONSTANTS & LAYOUT ---")
    layout_ok = 0

    # F-1: Zero-page overlap detection
    zp_vars = []
    for fname_z, lines_z in files.items():
        for li, lz in enumerate(lines_z):
            m_zp = re.match(r'(zp_\w+)\s*=\s*\$([0-9A-Fa-f]+)', lz.strip())
            if m_zp:
                name = m_zp.group(1)
                addr = int(m_zp.group(2), 16)
                size = 1
                comment = lz.split(';')[-1] if ';' in lz else ''
                m_sz = re.search(r'(\d+)\s*[bB](?:yte)?', comment)
                if m_sz:
                    size = int(m_sz.group(1))
                if name.endswith('_ptr') and size == 1 and not m_sz:
                    size = 2
                if name == 'zp_vbxe_base':
                    size = 2
                zp_vars.append((name, addr, size, fname_z, li + 1))

    if zp_vars:
        zp_vars.sort(key=lambda x: x[1])
        zp_collisions = []
        for i in range(len(zp_vars)):
            n1, a1, s1, f1, l1 = zp_vars[i]
            for j in range(i + 1, len(zp_vars)):
                n2, a2, s2, f2, l2 = zp_vars[j]
                if a2 >= a1 + s1:
                    break
                zp_collisions.append((n1, a1, s1, f1, l1, n2, a2, s2, f2, l2))

        if not zp_collisions:
            lo = zp_vars[0][1]
            hi = max(a + s - 1 for _, a, s, _, _ in zp_vars)
            print(f"  [OK]   ZP: {len(zp_vars)} vars, no overlaps (${lo:02X}-${hi:02X})")
            layout_ok += 1
        else:
            for n1, a1, s1, f1, l1, n2, a2, s2, f2, l2 in zp_collisions:
                errors.append(
                    f"ZP: {n1} (${a1:02X}, {s1}B) overlaps {n2} (${a2:02X}, {s2}B)\n"
                    f"         {f1}:{l1} vs {f2}:{l2}\n"
                    f"         Zero-page collision = both vars share same memory.\n"
                    f"         Writes to one silently corrupt the other.")

    # F-2: MEMB_* = MEMB_BASE + VRAM_* cross-check
    memb_base_v = get_const(files, 'MEMB_BASE')
    memb_pairs = [
        ('MEMB_SCREEN', 'VRAM_SCREEN'),
        ('MEMB_BCB', 'VRAM_BCB'),
        ('MEMB_PATTERN', 'VRAM_PATTERN'),
        ('MEMB_XDL', 'VRAM_XDL'),
        ('MEMB_FONT', 'VRAM_FONT'),
    ]
    memb_cross_ok = True
    if memb_base_v is not None:
        for memb_name, vram_name in memb_pairs:
            memb_v = get_const(files, memb_name)
            vram_v = get_const(files, vram_name)
            if memb_v is not None and vram_v is not None:
                expected = memb_base_v + vram_v
                if memb_v != expected:
                    errors.append(
                        f"LAYOUT: {memb_name}=${memb_v:04X} but MEMB_BASE+{vram_name}"
                        f" = ${memb_base_v:04X}+${vram_v:04X} = ${expected:04X}\n"
                        f"         CPU writes to wrong VRAM address via MEMAC B window.")
                    memb_cross_ok = False

        if memb_cross_ok:
            print(f"  [OK]   LAYOUT: all MEMB_* = MEMB_BASE + VRAM_* ({len(memb_pairs)} pairs)")
            layout_ok += 1
    else:
        warnings.append("LAYOUT: MEMB_BASE not found, cannot cross-check MEMB_*/VRAM_*")

    # F-3: row_addr table size must equal SCR_ROWS
    scr_rows_v = get_const(files, 'SCR_ROWS')
    for tbl_name in ['row_addr_lo', 'row_addr_hi']:
        hits_rt = find_in_asm(files, rf'{tbl_name}\s*$|{tbl_name}\s*;')
        if not hits_rt:
            continue
        for fname_rt, line_rt, _ in hits_rt:
            if line_rt < len(files[fname_rt]):
                next_line = files[fname_rt][line_rt].strip()
                m_rep = re.match(r':(\d+)\s+dta\s+', next_line)
                if m_rep:
                    table_size = int(m_rep.group(1))
                    if scr_rows_v and table_size == scr_rows_v:
                        pass
                    elif scr_rows_v:
                        errors.append(
                            f"LAYOUT: {tbl_name} has {table_size} entries but SCR_ROWS={scr_rows_v}\n"
                            f"         {fname_rt}:{line_rt+1}\n"
                            f"         Accessing row >= {table_size} reads garbage address → corrupt VRAM write.")
                        break

    row_tbl_ok = True
    for tbl_name in ['row_addr_lo', 'row_addr_hi']:
        for fname_rt, line_rt, _ in find_in_asm(files, rf'{tbl_name}\s*$|{tbl_name}\s*;'):
            if line_rt < len(files[fname_rt]):
                next_line = files[fname_rt][line_rt].strip()
                m_rep = re.match(r':(\d+)\s+dta\s+', next_line)
                if m_rep and scr_rows_v and int(m_rep.group(1)) != scr_rows_v:
                    row_tbl_ok = False
    if row_tbl_ok and scr_rows_v:
        print(f"  [OK]   LAYOUT: row_addr tables match SCR_ROWS={scr_rows_v}")
        layout_ok += 1

    # F-4: Screen layout consistency
    content_top_v = get_const(files, 'CONTENT_TOP')
    content_rows_v = get_const(files, 'CONTENT_ROWS')
    content_bot_v = get_const(files, 'CONTENT_BOT')
    status_row_v = get_const(files, 'STATUS_ROW')

    if all(v is not None for v in [scr_rows_v, content_top_v, content_bot_v,
                                    content_rows_v, status_row_v]):
        layout_errs = []
        expected_bot = content_top_v + content_rows_v - 1
        if content_bot_v != expected_bot:
            layout_errs.append(
                f"CONTENT_BOT={content_bot_v} but CONTENT_TOP+CONTENT_ROWS-1"
                f"={content_top_v}+{content_rows_v}-1={expected_bot}")
        if status_row_v != scr_rows_v - 2:
            layout_errs.append(
                f"STATUS_ROW={status_row_v} but SCR_ROWS-2={scr_rows_v - 2}")
        if content_bot_v != status_row_v - 1:
            layout_errs.append(
                f"CONTENT_BOT={content_bot_v} but STATUS_ROW-1={status_row_v - 1}")

        if not layout_errs:
            print(f"  [OK]   LAYOUT: screen layout consistent "
                  f"(top={content_top_v}, bot={content_bot_v}, "
                  f"status={status_row_v}, rows={scr_rows_v})")
            layout_ok += 1
        else:
            for le in layout_errs:
                errors.append(
                    f"LAYOUT: {le}\n"
                    f"         Screen layout constants are inconsistent.\n"
                    f"         Scroll/clear operations will affect wrong rows.")

    # F-5: VRAM regions must not exceed bank 0
    vram_font = get_const(files, 'VRAM_FONT')
    vram_font_inv = get_const(files, 'VRAM_FONT_INV')
    vram_xdl = get_const(files, 'VRAM_XDL')
    vram_bcb = get_const(files, 'VRAM_BCB')
    vram_end = {}
    if vram_font is not None:
        vram_end['VRAM_FONT'] = vram_font + 0x800
    if vram_font_inv is not None:
        vram_end['VRAM_FONT_INV'] = vram_font_inv + 0x800
    if vram_xdl is not None:
        vram_end['VRAM_XDL'] = vram_xdl + 0x100
    if vram_bcb is not None:
        vram_end['VRAM_BCB'] = vram_bcb + 21 * 5
    bank0_overflow = [(name, end) for name, end in vram_end.items() if end > 0x4000]
    if not bank0_overflow:
        print(f"  [OK]   LAYOUT: all VRAM regions fit in MEMAC B bank 0 (<$4000)")
        layout_ok += 1
    else:
        for name, end in bank0_overflow:
            errors.append(
                f"LAYOUT: {name} extends to ${end:05X}, past MEMAC B bank 0 ($4000)\n"
                f"         Bank 0 maps VRAM $0000-$3FFF. Regions past $4000 need bank 1+.")

    ok_count += layout_ok

    return ok_count, errors, warnings
