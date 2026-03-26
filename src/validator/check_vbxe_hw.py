"""Sections 6e, 10-10d: VBXE hardware, XDL, BCB validation."""
import re
from .asm_utils import find_in_asm, get_proc, get_const, find_proc_in_listing

# VBXE spec: data bytes per XDLC flag, in mandatory order
XDLC_FLAG_BYTES = {
    0x0020: ('RPTL', 1),
    0x0040: ('OVADR', 5),   # 3 addr + 2 step
    0x0080: ('OVSCRL', 2),
    0x0100: ('CHBASE', 1),
    0x0200: ('MAPADR', 5),
    0x0400: ('MAPPAR', 4),
    0x0800: ('OVATT', 2),
}
# Forbidden flag combos per VBXE spec
XDLC_TMON_V  = 0x0001
XDLC_GMON_V  = 0x0002
XDLC_OVOFF_V = 0x0004
XDLC_HR_V    = 0x1000
XDLC_LR_V    = 0x2000
XDLC_END_V   = 0x8000


def parse_xdlc_flags(expr):
    """Parse XDLC flag expression like 'XDLC_TMON|XDLC_RPTL|...' into int."""
    val = 0
    for name in re.findall(r'XDLC_\w+', expr):
        known = {
            'XDLC_TMON': 0x0001, 'XDLC_GMON': 0x0002, 'XDLC_OVOFF': 0x0004,
            'XDLC_MAPON': 0x0008, 'XDLC_MAPOFF': 0x0010, 'XDLC_RPTL': 0x0020,
            'XDLC_OVADR': 0x0040, 'XDLC_OVSCRL': 0x0080, 'XDLC_CHBASE': 0x0100,
            'XDLC_MAPADR': 0x0200, 'XDLC_MAPPAR': 0x0400, 'XDLC_OVATT': 0x0800,
            'XDLC_HR': 0x1000, 'XDLC_LR': 0x2000, 'XDLC_END': 0x8000,
        }
        if name in known:
            val |= known[name]
    return val


def expected_data_bytes(flags):
    """Count how many data bytes follow XDLC word, per spec."""
    total = 0
    for bit, (name, nbytes) in XDLC_FLAG_BYTES.items():
        if flags & bit:
            total += nbytes
    return total


def check_forbidden_combos(flags, entry_name):
    """Check VBXE spec forbidden flag combinations. Returns list of error strings."""
    errs = []
    if (flags & XDLC_TMON_V) and (flags & XDLC_GMON_V):
        errs.append(
            f"XDL: {entry_name} has TMON+GMON set simultaneously\n"
            f"         VBXE SPEC: This is forbidden. Hardware treats it as OVOFF.\n"
            f"         FIX: Use only TMON (text) or GMON (graphics), not both.")
    if (flags & XDLC_HR_V) and (flags & XDLC_LR_V):
        errs.append(
            f"XDL: {entry_name} has HR+LR set simultaneously\n"
            f"         VBXE SPEC: This is a forbidden combination.\n"
            f"         FIX: Use only HR (hi-res) or LR (lo-res), not both.")
    if (flags & XDLC_OVOFF_V) and (flags & (XDLC_TMON_V | XDLC_GMON_V)):
        errs.append(
            f"XDL: {entry_name} has OVOFF with TMON or GMON\n"
            f"         VBXE SPEC: Setting multiple of TMON/GMON/OVOFF disables overlay.\n"
            f"         This is valid only if intentional (usually a bug).")
    if (flags & (XDLC_HR_V | XDLC_LR_V)) and not (flags & XDLC_GMON_V):
        errs.append(
            f"XDL: {entry_name} has HR/LR without GMON\n"
            f"         VBXE SPEC: HR/LR only applies to graphics overlay mode.\n"
            f"         FIX: Add XDLC_GMON, or remove HR/LR flags.")
    return errs


def parse_static_xdl(files, proc_name, data_label):
    """Parse a static XDL (dta-based) and return list of (flags, rptl_value, entry_name, expected, actual)."""
    fname, line, body = get_proc(files, proc_name)
    if not body:
        return None, None, None
    entries = []
    lines = body.split('\n')
    i = 0
    while i < len(lines) and data_label not in lines[i]:
        i += 1
    i += 1
    entry_num = 0
    while i < len(lines):
        sl = lines[i].strip()
        if '.endp' in sl or (not sl and i > 0 and '.endp' in lines[min(i+1, len(lines)-1)]):
            break
        m = re.match(r'dta\s+a\(([^)]+)\)', sl, re.IGNORECASE)
        if m:
            entry_num += 1
            flags = parse_xdlc_flags(m.group(1))
            actual_bytes = 0
            rptl_val = None
            j = i + 1
            while j < len(lines):
                dl = lines[j].strip()
                if not dl or dl.startswith(';'):
                    j += 1
                    continue
                if re.match(r'dta\s+a\(XDLC', dl, re.IGNORECASE):
                    break
                if '.endp' in dl or '= *' in dl:
                    break
                if re.match(r'dta\s+a\(', dl, re.IGNORECASE):
                    actual_bytes += 2
                    j += 1
                    continue
                if re.match(r'dta\s+<', dl, re.IGNORECASE):
                    parts = dl.split(',')
                    actual_bytes += len(parts)
                    j += 1
                    continue
                parts = re.split(r',\s*', re.sub(r'dta\s+', '', dl.split(';')[0], flags=re.I).strip())
                actual_bytes += len(parts)
                if rptl_val is None and (flags & 0x0020):
                    expr = parts[0].strip()
                    try:
                        e = expr
                        scr_rows_v = get_const(files, 'SCR_ROWS')
                        if scr_rows_v and 'SCR_ROWS' in e:
                            e = e.replace('SCR_ROWS', str(scr_rows_v))
                        grad_h = get_const(files, 'GRAD_BAND_H')
                        if grad_h and 'GRAD_BAND_H' in e:
                            e = e.replace('GRAD_BAND_H', str(grad_h))
                        title_rows = get_const(files, 'TITLE_TEXT_ROWS')
                        if title_rows and 'TITLE_TEXT_ROWS' in e:
                            e = e.replace('TITLE_TEXT_ROWS', str(title_rows))
                        rptl_val = eval(e)
                    except Exception:
                        rptl_val = -1
                j += 1
            expected = expected_data_bytes(flags)
            entries.append((flags, rptl_val, f"{proc_name} entry {entry_num}",
                            expected, actual_bytes))
            i = j
            continue
        i += 1
    return fname, line, entries


def check(files, ctx):
    errors = []
    warnings = []
    ok_count = 0

    listing = ctx['listing']

    # --- 6e. VBXE hardware checks ---
    print()
    print("  --- VBXE HARDWARE CHECKS ---")
    vbxe_ok = 0

    # VBXE-1: VRAM layout collision detection
    vram_regions = {}
    vram_font = get_const(files, 'VRAM_FONT')
    vram_font_inv = get_const(files, 'VRAM_FONT_INV')
    vram_screen = get_const(files, 'VRAM_SCREEN')
    vram_bcb = get_const(files, 'VRAM_BCB')
    vram_xdl = get_const(files, 'VRAM_XDL')
    vram_pattern = get_const(files, 'VRAM_PATTERN')
    vram_page_buf = get_const(files, 'VRAM_PAGE_BUF')
    scr_rows = get_const(files, 'SCR_ROWS') or 29
    scr_stride = get_const(files, 'SCR_STRIDE') or 160

    if vram_screen is not None:
        vram_regions['SCREEN'] = (vram_screen, vram_screen + scr_rows * scr_stride)
    if vram_bcb is not None:
        vram_regions['BCB'] = (vram_bcb, vram_bcb + 0x80)
    if vram_xdl is not None:
        vram_regions['XDL'] = (vram_xdl, vram_xdl + 0x40)
    if vram_pattern is not None:
        vram_regions['PATTERN'] = (vram_pattern, vram_pattern + 2)
    if vram_font is not None:
        vram_regions['FONT'] = (vram_font, vram_font + 0x800)
    if vram_font_inv is not None:
        vram_regions['FONT_INV'] = (vram_font_inv, vram_font_inv + 0x800)

    collisions = []
    region_names = list(vram_regions.keys())
    for i in range(len(region_names)):
        for j in range(i+1, len(region_names)):
            n1, n2 = region_names[i], region_names[j]
            s1, e1 = vram_regions[n1]
            s2, e2 = vram_regions[n2]
            if s1 < e2 and s2 < e1:
                collisions.append((n1, s1, e1, n2, s2, e2))

    if not collisions:
        print(f"  [OK]   VRAM: no region collisions ({len(vram_regions)} regions checked)")
        vbxe_ok += 1
    else:
        for n1, s1, e1, n2, s2, e2 in collisions:
            errors.append(
                f"VRAM: {n1} (${s1:05X}-${e1:05X}) overlaps {n2} (${s2:05X}-${e2:05X})\n"
                f"         Blitter/DMA operations may corrupt {n2} data!")

    # VBXE-2: Font CHBASE alignment
    if vram_font is not None:
        if vram_font % 0x800 == 0:
            print(f"  [OK]   VRAM: VRAM_FONT=${vram_font:05X} is $800-aligned")
            vbxe_ok += 1
        else:
            errors.append(
                f"VRAM: VRAM_FONT=${vram_font:05X} is NOT $800-aligned!\n"
                f"         CHBASE register requires font at $800 boundary.\n"
                f"         VBXE will read wrong font data.")

    # VBXE-3: XDL stride vs calc_scr_ptr consistency
    scr_cols = get_const(files, 'SCR_COLS') or 80
    expected_stride = scr_cols * 2
    if scr_stride == expected_stride:
        print(f"  [OK]   VRAM: SCR_STRIDE={scr_stride} matches SCR_COLS={scr_cols} * 2")
        vbxe_ok += 1
    else:
        errors.append(
            f"VRAM: SCR_STRIDE={scr_stride} but SCR_COLS={scr_cols} * 2 = {expected_stride}\n"
            f"         XDL row step won't match screen pointer calculation.\n"
            f"         Text will appear at wrong positions or wrap incorrectly.")

    # VBXE-4: Palette bank consistency
    fname_sp, _, body_sp = get_proc(files, 'setup_palette')
    if body_sp:
        m_psel = re.search(r'lda\s+#(\d+).*\n.*sta\s+\(zp_vbxe_base\)', body_sp, re.DOTALL)
        pal_setup = int(m_psel.group(1)) if m_psel else None
        ovatt_pal = 1
        if pal_setup is not None and pal_setup == ovatt_pal:
            print(f"  [OK]   VRAM: setup_palette uses palette {pal_setup} = XDL OVATT palette")
            vbxe_ok += 1
        elif pal_setup is not None:
            errors.append(
                f"VRAM: setup_palette uses palette {pal_setup} but XDL OVATT = palette {ovatt_pal}\n"
                f"         Text colors will use wrong palette -> wrong colors on screen.")

    # VBXE-5: MEMAC B data buffer conflict detection
    if listing:
        memb_buffers = []
        for addr, bytez, asm in listing:
            if 0x4000 <= addr < 0x8000 and '.ds' in asm:
                m_ds = re.search(r'(\w+)\s+\.ds\s+', asm)
                if m_ds:
                    memb_buffers.append((m_ds.group(1), addr))
        if memb_buffers:
            buf_list = ', '.join(f"{name}=${addr:04X}" for name, addr in memb_buffers[:6])
            extra = f" (+{len(memb_buffers)-6} more)" if len(memb_buffers) > 6 else ""
            warnings.append(
                f"VRAM: {len(memb_buffers)} data buffers in MEMAC B window ($4000-$7FFF):\n"
                f"         {buf_list}{extra}\n"
                f"         These are invisible to CPU when MEMAC B is active (reads VRAM instead).\n"
                f"         Ensure all access happens with MEMAC B disabled.")

    # VBXE-6: Interrupt handler safety
    stub_base = get_const(files, 'STUB_BASE')
    if stub_base is not None and stub_base < 0x4000:
        print(f"  [OK]   VRAM: interrupt stubs at ${stub_base:04X} (below $4000, MEMAC B safe)")
        vbxe_ok += 1
    elif stub_base is not None:
        errors.append(
            f"VRAM: STUB_BASE=${stub_base:04X} is in MEMAC B window!\n"
            f"         Interrupt handlers will execute VRAM data when MEMAC B is active.")

    # VBXE-7: XDL has TMON with CHBASE set
    fname_sx, _, body_sx = get_proc(files, 'setup_xdl')
    if body_sx:
        xdl_entries = re.findall(r'dta\s+a\(([^)]+)\)', body_sx)
        chbase_set = False
        tmon_without_chbase = False
        for entry_flags in xdl_entries:
            if 'XDLC_CHBASE' in entry_flags:
                chbase_set = True
            if 'XDLC_TMON' in entry_flags:
                if not chbase_set and 'XDLC_CHBASE' not in entry_flags:
                    tmon_without_chbase = True

        if not tmon_without_chbase:
            print(f"  [OK]   VRAM: XDL CHBASE set before TMON entry")
            vbxe_ok += 1
        else:
            warnings.append(
                f"VRAM: XDL has TMON entry without CHBASE set in same or prior entry\n"
                f"         CHBASE may default to 0 -> font reads from VRAM $0000 (screen buffer).\n"
                f"         Some VBXE cores may not persist CHBASE across OVOFF entries.")

    ok_count += vbxe_ok

    # --- 10a. Validate static XDL: setup_xdl ---
    print()
    print("  --- XDL STRUCTURAL VALIDATION ---")
    xdl_ok = 0

    fname_xdl, line_xdl, xdl_entries = parse_static_xdl(files, 'setup_xdl', 'xdl_data')
    if xdl_entries:
        total_scanlines = 0
        end_count = 0
        has_xdl_error = False

        for flags, rptl, name, expected_bytes, actual_bytes in xdl_entries:
            for err in check_forbidden_combos(flags, name):
                errors.append(err)
                has_xdl_error = True

            if actual_bytes != expected_bytes:
                errors.append(
                    f"XDL: {name} has {actual_bytes} data bytes but flags need {expected_bytes}\n"
                    f"         VBXE SPEC: Data bytes must exactly match XDLC flags.\n"
                    f"         Wrong count = VBXE reads garbage, display is corrupted.")
                has_xdl_error = True

            if rptl is not None and rptl >= 0:
                total_scanlines += rptl + 1

            if flags & XDLC_END_V:
                end_count += 1

        if total_scanlines == 240:
            print(f"  [OK]   XDL: setup_xdl total scanlines = {total_scanlines}")
            xdl_ok += 1
        elif total_scanlines > 0:
            errors.append(
                f"XDL: setup_xdl total scanlines = {total_scanlines}, expected 240\n"
                f"         VBXE SPEC: Overlay has exactly 240 scanlines per frame.\n"
                f"         {'>240 = bottom entries ignored' if total_scanlines > 240 else '<240 = black band at bottom'}.")
            has_xdl_error = True

        if end_count == 1:
            print(f"  [OK]   XDL: setup_xdl has exactly 1 XDLC_END (on last entry)")
            xdl_ok += 1
        elif end_count == 0:
            errors.append(
                f"XDL: setup_xdl has no XDLC_END!\n"
                f"         VBXE SPEC: Without END flag, XDL controller reads past data = garbage display.")
            has_xdl_error = True
        else:
            errors.append(
                f"XDL: setup_xdl has {end_count} XDLC_END flags, expected exactly 1\n"
                f"         VBXE SPEC: Only the last entry should have XDLC_END.")
            has_xdl_error = True

        if not has_xdl_error:
            print(f"  [OK]   XDL: setup_xdl no forbidden flag combinations ({len(xdl_entries)} entries)")
            xdl_ok += 1

    # --- 10b. Validate static XDL: title_gfx_init ---
    fname_txdl, line_txdl, title_entries = parse_static_xdl(files, 'title_gfx_init', 'title_xdl_data')
    if title_entries:
        total_scanlines = 0
        end_count = 0
        has_title_error = False

        for flags, rptl, name, expected_bytes, actual_bytes in title_entries:
            for err in check_forbidden_combos(flags, name):
                errors.append(err)
                has_title_error = True

            if actual_bytes != expected_bytes:
                errors.append(
                    f"XDL: {name} has {actual_bytes} data bytes but flags need {expected_bytes}\n"
                    f"         VBXE SPEC: Data bytes must exactly match XDLC flags.")
                has_title_error = True

            if rptl is not None and rptl >= 0:
                total_scanlines += rptl + 1

            if flags & XDLC_END_V:
                end_count += 1

        if total_scanlines == 240:
            print(f"  [OK]   XDL: title_xdl total scanlines = {total_scanlines}")
            xdl_ok += 1
        elif total_scanlines > 0:
            errors.append(
                f"XDL: title_xdl total scanlines = {total_scanlines}, expected 240\n"
                f"         VBXE SPEC: Overlay has exactly 240 scanlines per frame.")
            has_title_error = True

        if end_count == 1:
            print(f"  [OK]   XDL: title_xdl has exactly 1 XDLC_END")
            xdl_ok += 1
        elif end_count == 0:
            errors.append(f"XDL: title_xdl has no XDLC_END!")
            has_title_error = True
        else:
            errors.append(f"XDL: title_xdl has {end_count} XDLC_END flags, expected 1")
            has_title_error = True

        if not has_title_error:
            print(f"  [OK]   XDL: title_xdl no forbidden flag combinations ({len(title_entries)} entries)")
            xdl_ok += 1

    # --- 10c. Validate dynamic XDL: vbxe_img_show_fullscreen ---
    fname_img, line_img, body_img = get_proc(files, 'vbxe_img_show_fullscreen')
    if body_img:
        img_xdl_flags = re.findall(r'lda\s+#<\((XDLC_[^)]+)\)', body_img)
        img_entry_num = 0
        img_end_count = 0
        has_img_error = False

        for expr in img_xdl_flags:
            img_entry_num += 1
            flags = parse_xdlc_flags(expr)

            for err in check_forbidden_combos(flags, f"img_show entry {img_entry_num}"):
                errors.append(err)
                has_img_error = True

            if flags & XDLC_END_V:
                img_end_count += 1

        if img_end_count >= 1:
            print(f"  [OK]   XDL: img_show has XDLC_END ({img_end_count} path(s))")
            xdl_ok += 1
        else:
            errors.append(
                f"XDL: vbxe_img_show_fullscreen has no XDLC_END in any code path!\n"
                f"         VBXE SPEC: Every XDL must terminate with XDLC_END.")
            has_img_error = True

        if '240 - 24' in body_img or '240-24' in body_img:
            print(f"  [OK]   XDL: img_show uses 240-24-height scanline calc")
            xdl_ok += 1
        else:
            warnings.append(
                f"XDL: vbxe_img_show_fullscreen may not sum to 240 scanlines\n"
                f"         Cannot verify dynamic scanline calculation.")

        if not has_img_error:
            print(f"  [OK]   XDL: img_show no forbidden flag combinations ({img_entry_num} entries)")
            xdl_ok += 1

    # --- 10d. XDL data byte ORDER check ---
    xdl_order_ok = True
    for proc_name, data_label in [('setup_xdl', 'xdl_data'), ('title_gfx_init', 'title_xdl_data')]:
        fname_o, line_o, body_o = get_proc(files, proc_name)
        if not body_o:
            continue
        body_lines = body_o.split('\n')
        in_entry = False
        last_field_order = -1
        entry_num = 0
        field_order = {
            'RPTL': 0, 'scanline': 0, 'blank': 0, 'repeat': 0,
            'OVADR': 1, 'VRAM_SCREEN': 1, 'VRAM_GRADIENT': 1, 'STRIDE': 1, 'step': 1,
            'OVSCRL': 2, 'scroll': 2,
            'CHBASE': 3, 'CHBASE_VAL': 3,
            'MAPADR': 4,
            'MAPPAR': 5,
            'OVATT': 6, 'palette': 6, 'priority': 6, '%0001': 6,
        }
        for bl in body_lines:
            sl = bl.strip()
            if re.match(r'dta\s+a\(XDLC', sl, re.IGNORECASE):
                in_entry = True
                last_field_order = -1
                entry_num += 1
                continue
            if not in_entry:
                continue
            if '.endp' in sl or '= *' in sl:
                break
            if not sl or sl.startswith(';'):
                continue
            if re.match(r'dta\s+a\(XDLC', sl, re.IGNORECASE):
                in_entry = True
                last_field_order = -1
                entry_num += 1
                continue
            combined = sl + ' ' + bl
            current_order = -1
            for marker, order in field_order.items():
                if marker.lower() in combined.lower():
                    current_order = max(current_order, order)
            if current_order >= 0:
                if current_order < last_field_order:
                    errors.append(
                        f"XDL: {proc_name} entry {entry_num} has data in wrong order\n"
                        f"         VBXE SPEC: Data must follow flag bit order:\n"
                        f"         RPTL -> OVADR+STEP -> OVSCRL -> CHBASE -> MAPADR -> MAPPAR -> OVATT\n"
                        f"         Line: {sl}")
                    xdl_order_ok = False
                last_field_order = current_order

    if xdl_order_ok:
        print(f"  [OK]   XDL: data byte order follows VBXE spec sequence")
        xdl_ok += 1

    ok_count += xdl_ok

    # --- 10e. BCB structural validation ---
    print()
    print("  --- BCB STRUCTURAL VALIDATION ---")
    bcb_ok = 0

    fname_bcb, line_bcb, body_bcb = get_proc(files, 'setup_bcb')
    if body_bcb:
        bcb_lines = body_bcb.split('\n')
        data_start = None
        for bi, bl in enumerate(bcb_lines):
            if 'bcb_data' in bl and not bl.strip().startswith(';'):
                data_start = bi + 1
                break

        if data_start is not None:
            bcb_list = []
            cur_name = None
            cur_bytes = 0
            cur_fields = {}
            field_idx = 0
            BCB_FIELD_MAP = {
                0: 'src_addr', 3: 'src_step_y', 5: 'src_step_x',
                6: 'dst_addr', 9: 'dst_step_y', 11: 'dst_step_x',
                12: 'width', 14: 'height', 15: 'and_mask', 16: 'xor_mask',
                17: 'collision', 18: 'zoom', 19: 'pattern', 20: 'control',
            }

            def count_dta_bytes(line_text):
                sl = line_text.strip().split(';')[0].strip()
                if not re.match(r'dta\s+', sl, re.IGNORECASE):
                    return 0
                after = re.sub(r'^dta\s+', '', sl, flags=re.IGNORECASE).strip()
                depth = 0
                parts = []
                cur_p = ''
                for ch in after:
                    if ch == '(':
                        depth += 1
                    elif ch == ')':
                        depth -= 1
                    elif ch == ',' and depth == 0:
                        parts.append(cur_p.strip())
                        cur_p = ''
                        continue
                    cur_p += ch
                if cur_p.strip():
                    parts.append(cur_p.strip())
                count = 0
                for p in parts:
                    if p.startswith('a(') or p.startswith('A('):
                        count += 2
                    else:
                        count += 1
                return count

            for bi in range(data_start, len(bcb_lines)):
                bl = bcb_lines[bi].strip()
                if '.endp' in bl or '= *' in bl:
                    break

                m_hdr = re.match(r';\s*BCB\s+(\d+):\s*(.+)', bl)
                if m_hdr:
                    if cur_name is not None:
                        bcb_list.append((cur_name, cur_bytes, cur_fields))
                    cur_name = f"BCB {m_hdr.group(1)}: {m_hdr.group(2).strip()}"
                    cur_bytes = 0
                    cur_fields = {}
                    field_idx = 0
                    continue

                if bl.startswith(';') or not bl:
                    continue

                nb = count_dta_bytes(bl)
                if nb > 0 and cur_name is not None:
                    if field_idx in BCB_FIELD_MAP:
                        expr = re.sub(r'^dta\s+', '', bl.split(';')[0].strip(),
                                      flags=re.IGNORECASE).strip()
                        cur_fields[BCB_FIELD_MAP[field_idx]] = expr
                    cur_bytes += nb
                    field_idx += nb

            if cur_name is not None:
                bcb_list.append((cur_name, cur_bytes, cur_fields))

            # Check 1: Each BCB must be exactly 21 bytes
            all_21 = True
            for name, nbytes, _ in bcb_list:
                if nbytes != 21:
                    errors.append(
                        f"BCB: {name} is {nbytes} bytes, expected 21\n"
                        f"         VBXE SPEC: Each BCB is exactly 21 bytes.\n"
                        f"         Wrong size = blitter reads shifted data = corrupted operations.")
                    all_21 = False
            if all_21 and bcb_list:
                print(f"  [OK]   BCB: all {len(bcb_list)} BCBs are exactly 21 bytes")
                bcb_ok += 1

            # Check 2: Width-1 must equal SCR_STRIDE-1
            scr_stride_v = get_const(files, 'SCR_STRIDE')
            width_ok = True
            for name, _, fields in bcb_list:
                w_expr = fields.get('width', '')
                if not w_expr:
                    continue
                m_w = re.search(r'a\(([^)]+)\)', w_expr, re.IGNORECASE)
                if m_w:
                    inner = m_w.group(1).strip()
                    e = inner
                    if scr_stride_v and 'SCR_STRIDE' in e:
                        e = e.replace('SCR_STRIDE', str(scr_stride_v))
                    try:
                        val = int(eval(e))
                        if scr_stride_v and val != scr_stride_v - 1:
                            errors.append(
                                f"BCB: {name} width-1 = {val}, expected SCR_STRIDE-1 = {scr_stride_v - 1}\n"
                                f"         VBXE SPEC: Blitter copies width+1 bytes per line.\n"
                                f"         Wrong width = partial row copy or overrun into next row.")
                            width_ok = False
                    except Exception:
                        pass
            if width_ok and bcb_list:
                print(f"  [OK]   BCB: all width fields match SCR_STRIDE-1 = {scr_stride_v - 1 if scr_stride_v else '?'}")
                bcb_ok += 1

            # Check 3: Height-1 consistency
            scr_rows_v = get_const(files, 'SCR_ROWS')
            content_top_v = get_const(files, 'CONTENT_TOP')
            content_bot_v = get_const(files, 'CONTENT_BOT')
            height_ok = True
            expected_heights = {}
            if scr_rows_v:
                expected_heights['BCB 0'] = scr_rows_v - 1
                expected_heights['BCB 1'] = scr_rows_v - 2
                expected_heights['BCB 2'] = 0
            if content_top_v is not None and content_bot_v is not None:
                expected_heights['BCB 3'] = content_bot_v - content_top_v - 1
                expected_heights['BCB 4'] = 0

            for name, _, fields in bcb_list:
                h_expr = fields.get('height', '')
                if not h_expr:
                    continue
                e = h_expr
                for cname in ['SCR_ROWS', 'CONTENT_BOT', 'CONTENT_TOP']:
                    cv = get_const(files, cname)
                    if cv is not None and cname in e:
                        e = e.replace(cname, str(cv))
                try:
                    h_val = int(eval(e))
                except Exception:
                    continue
                m_num = re.match(r'BCB\s+(\d+)', name)
                if m_num:
                    bcb_key = f"BCB {m_num.group(1)}"
                    if bcb_key in expected_heights:
                        exp = expected_heights[bcb_key]
                        if h_val != exp:
                            errors.append(
                                f"BCB: {name} height-1 = {h_val}, expected {exp}\n"
                                f"         Blitter copies height+1 rows. Wrong height =\n"
                                f"         scroll overwrites URL bar, status bar, or misses rows.")
                            height_ok = False

            if height_ok and expected_heights:
                print(f"  [OK]   BCB: all height fields match expected values")
                bcb_ok += 1

            # Check 4: Fill pattern = CH_SPACE + $00
            ch_space_v = get_const(files, 'CH_SPACE')
            pattern_hits = find_in_asm(files, r'VRAM_PATTERN|MEMB_PATTERN')
            pattern_ok = False
            for ph_file, ph_line, ph_text in pattern_hits:
                if 'dta' in ph_text.lower() and ('CH_SPACE' in ph_text or
                    (ch_space_v is not None and f'${ch_space_v:02X}' in ph_text.upper())):
                    pattern_ok = True
                    break
            pattern_writes = find_in_asm(files, r'sta\s+MEMB_PATTERN')
            if not pattern_ok and pattern_writes:
                for pw_file, pw_line, pw_text in pattern_writes:
                    lines_before = files[pw_file][max(0, pw_line-4):pw_line-1]
                    for lb in lines_before:
                        if 'CH_SPACE' in lb or 'lda #$20' in lb.lower():
                            pattern_ok = True
                            break

            if pattern_ok:
                print(f"  [OK]   BCB: fill pattern uses CH_SPACE (${ch_space_v:02X})")
                bcb_ok += 1
            else:
                warnings.append(
                    f"BCB: cannot verify fill pattern at VRAM_PATTERN\n"
                    f"         Expected: CH_SPACE (${ch_space_v:02X}) + $00 (black attr).\n"
                    f"         If wrong, cleared screen shows garbage instead of spaces.")

            # Check 5: Chain consistency
            chain_ok = True
            for i, (name, nbytes, fields) in enumerate(bcb_list):
                ctrl = fields.get('control', '')
                is_chain = '$08' in ctrl or ctrl.strip() == '8'
                if is_chain:
                    if nbytes != 21:
                        errors.append(
                            f"BCB: {name} chains (NEXT=1) but is {nbytes} bytes, not 21\n"
                            f"         VBXE SPEC: Chained BCB must be exactly 21 bytes apart.\n"
                            f"         Blitter reads next BCB at offset+21 = wrong data.")
                        chain_ok = False
                    elif i + 1 >= len(bcb_list):
                        errors.append(
                            f"BCB: {name} chains (NEXT=1) but is the last BCB!\n"
                            f"         VBXE SPEC: NEXT=1 means load next 21 bytes as BCB.\n"
                            f"         No next BCB = blitter executes garbage data.")
                        chain_ok = False

            if chain_ok and bcb_list:
                chain_count = sum(1 for _, _, f in bcb_list if '$08' in f.get('control', ''))
                print(f"  [OK]   BCB: {chain_count} chained BCB(s), all have valid successors")
                bcb_ok += 1

            # Check 6: Blitter mode check
            mode_ok = True
            for name, _, fields in bcb_list:
                ctrl = fields.get('control', '').strip()
                try:
                    if ctrl.startswith('$'):
                        ctrl_val = int(ctrl[1:], 16)
                    elif ctrl.isdigit():
                        ctrl_val = int(ctrl)
                    else:
                        continue
                    mode = ctrl_val & 0x07
                    if mode == 7:
                        errors.append(
                            f"BCB: {name} uses blitter mode 7 (RESERVED)\n"
                            f"         VBXE SPEC: Mode 7 is undefined. Behavior unpredictable.")
                        mode_ok = False
                except Exception:
                    pass
            if mode_ok and bcb_list:
                print(f"  [OK]   BCB: no reserved blitter modes used")
                bcb_ok += 1

        else:
            warnings.append("BCB: bcb_data label not found in setup_bcb")
    else:
        warnings.append("BCB: setup_bcb proc not found")

    ok_count += bcb_ok

    return ok_count, errors, warnings
