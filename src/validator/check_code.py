"""Sections 6-6d: render calls, clobber, mouse, buffer checks."""
import re
from .asm_utils import (find_in_asm, get_proc, get_proc_numbered, fmt_asm_lines,
                         find_proc_in_listing, cpu_trace, get_const)


def check(files, ctx):
    errors = []
    warnings = []
    ok_count = 0

    listing = ctx['listing']
    has_a2s = ctx['has_a2s']

    # --- 6. Where is ascii_to_screen called? ---
    callers = find_in_asm(files, r'jsr\s+ascii_to_screen')
    if callers:
        locations = [f"{f}:{l}" for f, l, _ in callers]
        in_renderer = any('renderer.asm' in f for f, _, _ in callers)
        in_parser = any('html_parser.asm' in f for f, _, _ in callers)

        if in_renderer:
            print(f"  [INFO] FLOW: ascii_to_screen in renderer.asm ({', '.join(locations)})")
            fname2, _, body2 = get_proc(files, 'render_out_char')
            if body2 and 'ascii_to_screen' in body2:
                print(f"  [INFO] FLOW: called in render_out_char (word wrap safe)")
            else:
                warnings.append("FLOW: ascii_to_screen in renderer.asm but NOT in render_out_char")
        elif in_parser:
            errors.append(
                f"FLOW: ascii_to_screen in html_emit_char ({', '.join(locations)})\n"
                "         render_char compares space with CH_SPACE=$20 but converted space=$00\n"
                "         -> word wrapping BROKEN! Move to render_out_char instead.")
        else:
            warnings.append(f"FLOW: ascii_to_screen called from {', '.join(locations)} - verify correctness")
    elif has_a2s:
        warnings.append("FLOW: ascii_to_screen exists but is NEVER CALLED")

    # --- 6b. Register clobber check: scan ALL procs that call render_out_char ---
    clobber_bugs = []
    render_callers = find_in_asm(files, r'jsr\s+render_out_char')
    checked_procs = set()
    for caller_file, caller_line, _ in render_callers:
        for fname_p, lines_p in files.items():
            if fname_p != caller_file:
                continue
            for i_p, l_p in enumerate(lines_p):
                if re.search(r'\.proc\s+\w+', l_p):
                    proc_start = i_p
                    proc_name_m = re.search(r'\.proc\s+(\w+)', l_p)
                    if not proc_name_m:
                        continue
                    pname = proc_name_m.group(1)
                    proc_end = proc_start
                    for j_p in range(proc_start, min(proc_start+200, len(lines_p))):
                        if '.endp' in lines_p[j_p]:
                            proc_end = j_p
                            break
                    if proc_start < caller_line-1 <= proc_end and pname not in checked_procs:
                        checked_procs.add(pname)
                        a_source = None
                        a_clobbered = False
                        clobber_insn = None
                        for k in range(proc_start, proc_end+1):
                            sl = lines_p[k].strip().lower()
                            if re.search(r'lda\s+#', sl) or re.search(r'lda\s+\w+\s*,\s*[xy]', sl):
                                a_source = lines_p[k].strip()
                                a_clobbered = False
                                clobber_insn = None
                            elif a_source and not a_clobbered:
                                if 'jsr' in sl and 'render_out_char' in sl:
                                    a_source = None
                                elif re.match(r'\b(txa|tya)\b', sl):
                                    next_sl = ''
                                    for nk in range(k+1, min(k+3, proc_end+1)):
                                        ns = lines_p[nk].strip().lower()
                                        if ns and not ns.startswith(';'):
                                            next_sl = ns
                                            break
                                    if re.search(r'\b(adc|ora)\s+#', next_sl):
                                        a_source = None
                                    else:
                                        a_clobbered = True
                                        clobber_insn = lines_p[k].strip()
                                elif re.match(r'\b(lda|pla)\b', sl):
                                    a_clobbered = True
                                    clobber_insn = lines_p[k].strip()
                            elif a_clobbered:
                                if 'jsr' in sl and 'render_out_char' in sl:
                                    clobber_bugs.append((pname, caller_file,
                                        proc_start+1, a_source, clobber_insn))
                                    a_source = None
                                    a_clobbered = False

    if not clobber_bugs:
        print(f"  [OK]   RENDER: all render_out_char callers preserve char in A")
        ok_count += 1
    else:
        for pname, cfile, cline, a_src, clobber in clobber_bugs:
            diag = (
                f"RENDER: {pname} clobbers char in A before render_out_char "
                f"({cfile}:{cline})\n"
                f"         BUG: After '{a_src}', the instruction '{clobber}'\n"
                f"         overwrites the character in register A.\n"
                f"         render_out_char receives wrong value -> VRAM gets garbage.\n"
                f"         FIX: Save X/Y to zp (stx zp_tmp3) before jsr render_out_char,\n"
                f"         restore after (ldx zp_tmp3). Do NOT use txa/tya before the jsr.\n"
            )
            proc_insns = find_proc_in_listing(listing, pname)
            if proc_insns:
                relevant = []
                capture = False
                for addr, bytez, asm in proc_insns:
                    if a_src and any(kw in asm for kw in a_src.split()[:2]):
                        capture = True
                    if capture:
                        relevant.append((addr, bytez, asm))
                    if capture and 'bne' in asm.lower():
                        break
                if relevant:
                    diag += f"\n         CPU trace ({pname}):\n"
                    diag += cpu_trace(relevant[:8],
                        regs={'A': 0x20, 'X': 2, 'Y': 0, 'S': 0xEB, 'P': 0x30},
                        scenario=f"A loaded with char, X=counter")
            errors.append(diag)

    # --- 6c. Mouse cursor artifact check ---
    mouse_bugs = []

    fname_mi, line_mi, body_mi = get_proc(files, 'mouse_init')
    if body_mi:
        sets_prev_ff = bool(re.search(
            r'lda\s+#\$FF.*\n\s*sta\s+zp_mouse_prev_x', body_mi, re.IGNORECASE))
        sets_prev_coord = bool(re.search(
            r'sta\s+zp_mouse_prev_x', body_mi)) and not sets_prev_ff
        if sets_prev_ff:
            pass
        elif sets_prev_coord:
            mouse_bugs.append((
                f"MOUSE: mouse_init sets prev_x to a valid coordinate ({fname_mi}:{line_mi})\n"
                f"         BUG: mouse_saved_char/attr are initialized to 0 (dta 0) but prev_x\n"
                f"         is a valid screen position. First mouse_show_cursor will restore\n"
                f"         position (prev_y, prev_x) with saved_char=0 -> NUL char on screen.\n"
                f"         FIX: Set prev_x to $FF so first show skips restore."
            ))
        elif not re.search(r'zp_mouse_prev_x', body_mi):
            mouse_bugs.append((
                f"MOUSE: mouse_init does not initialize prev_x ({fname_mi}:{line_mi})\n"
                f"         BUG: Uninitialized prev_x may cause restore to random screen position."
            ))

    fname_mh, line_mh, body_mh = get_proc(files, 'mouse_hide_cursor')
    if body_mh:
        checks_ff = bool(re.search(r'cmp\s+#\$FF', body_mh, re.IGNORECASE))
        sets_ff_after = bool(re.search(
            r'jsr\s+mouse_restore_char.*?lda\s+#\$FF.*?sta\s+zp_mouse_prev_x',
            body_mh, re.IGNORECASE | re.DOTALL))

        if not checks_ff:
            mouse_bugs.append((
                f"MOUSE: mouse_hide_cursor doesn't check prev_x=$FF ({fname_mh}:{line_mh})\n"
                f"         BUG: If prev_x=$FF (no cursor on screen), hide_cursor will call\n"
                f"         mouse_restore_char with row=$FF, col=$FF -> writes to random VRAM\n"
                f"         address (row_addr table only has {get_const(files, 'SCR_ROWS') or 29} entries).\n"
                f"         FIX: Add 'lda zp_mouse_prev_x / cmp #$FF / beq ?done' guard."
            ))
        if not sets_ff_after:
            mouse_bugs.append((
                f"MOUSE: mouse_hide_cursor doesn't set prev_x=$FF after restore ({fname_mh}:{line_mh})\n"
                f"         BUG: After hide_cursor restores the character, screen may be updated\n"
                f"         (scroll, clear). Then mouse_show_cursor does a SECOND restore with\n"
                f"         stale saved_char -> overwrites new screen content with old character.\n"
                f"         Visible as: ghost characters left behind after cursor moves.\n"
                f"         FIX: Set prev_x=$FF after mouse_restore_char to prevent double restore."
            ))

    fname_ms, line_ms, body_ms = get_proc(files, 'mouse_show_cursor')
    if body_ms:
        show_checks_ff = bool(re.search(r'cmp\s+#\$FF', body_ms, re.IGNORECASE))
        if not show_checks_ff:
            mouse_bugs.append((
                f"MOUSE: mouse_show_cursor doesn't check prev_x=$FF ({fname_ms}:{line_ms})\n"
                f"         BUG: Will try to restore invalid position when no cursor is on screen."
            ))

    # Check: ui_main_loop must NOT call mouse_invert_char directly
    # (mouse_show_cursor handles first draw when prev_x=$FF -- calling
    # mouse_invert_char before the loop causes double inversion: saved_char
    # gets the already-inverted value + COL_RED attr -> red ghost artifact)
    fname_ul, line_ul, body_ul = get_proc(files, 'ui_main_loop')
    if body_ul:
        has_direct_invert = bool(re.search(
            r'jsr\s+mouse_invert_char', body_ul, re.IGNORECASE))
        if has_direct_invert:
            mouse_bugs.append((
                f"MOUSE: ui_main_loop calls mouse_invert_char directly ({fname_ul}:{line_ul})\n"
                f"         BUG: mouse_show_cursor in the loop will invert the same position\n"
                f"         again (prev_x=$FF -> skip restore -> invert). Double inversion saves\n"
                f"         already-inverted char + COL_RED as 'original' -> red ghost when cursor moves.\n"
                f"         FIX: Remove direct mouse_invert_char call. mouse_show_cursor handles\n"
                f"         first cursor draw correctly when prev_x=$FF."
            ))

    if not mouse_bugs:
        if fname_mi:
            print(f"  [OK]   MOUSE: cursor init/show/hide guards are correct")
            ok_count += 1
    else:
        for diag in mouse_bugs:
            hide_insns = find_proc_in_listing(listing, 'mouse_hide_cursor')
            if hide_insns and 'hide_cursor' in diag:
                diag += f"\n         CPU trace (mouse_hide_cursor with prev_x=$FF):\n"
                diag += cpu_trace(hide_insns,
                    regs={'A': 0xFF, 'X': 0xFF, 'Y': 0, 'S': 0xEB, 'P': 0x30},
                    scenario="prev_x=$FF, no cursor on screen")
            errors.append(diag)

    # --- 6d. Buffer overread checks ---
    # Try http_render_progress first (progressive rendering), fallback to http_render
    fname_hr, line_hr, body_hr = get_proc(files, 'http_render_progress')
    if not body_hr:
        fname_hr, line_hr, body_hr = get_proc(files, 'http_render')
    if body_hr:
        has_proper_sub = bool(re.search(
            r'pb_total\s*\n.*sbc\s+pb_read\s*\n.*pb_total\+1\s*\n.*sbc\s+pb_read\+1',
            body_hr, re.IGNORECASE | re.DOTALL))

        has_buggy_cmp = bool(re.search(
            r'cmp\s+pb_read\+[12].*\n\s*bne\s+\?full',
            body_hr, re.IGNORECASE | re.DOTALL))

        if has_proper_sub:
            print(f"  [OK]   BUFFER: http_render chunk size uses proper 24-bit subtraction")
            ok_count += 1
        elif has_buggy_cmp:
            examples = []
            for page_name, page_size in [('1KB', 1024), ('4KB', 4096), ('10KB', 10399), ('50KB', 51200)]:
                remaining = page_size % 255
                if remaining == 0:
                    continue
                read_before_last = page_size - remaining
                if (page_size >> 8) & 0xFF != (read_before_last >> 8) & 0xFF:
                    overread = 255 - remaining
                    examples.append(
                        f"           {page_name} page ({page_size}B): last chunk has {remaining}B "
                        f"but reads 255 -> {overread}B VRAM garbage")

            diag = (
                f"BUFFER: http_render chunk size uses byte comparison, not subtraction "
                f"({fname_hr}:{line_hr})\n"
                f"         BUG: 'cmp pb_read+1 / bne ?full' assumes that if middle bytes\n"
                f"         differ, >255 bytes remain. This is WRONG.\n"
                f"         Example: pb_total=$0100, pb_read=$00FF -> remaining=1 byte\n"
                f"         But total+1=$01 != read+1=$00 -> reads 255 -> 254B overread!\n"
            )
            if examples:
                diag += f"         Impact on real pages:\n"
                for ex in examples:
                    diag += ex + "\n"
            diag += (
                f"         Visible as: garbage/random characters at end of page.\n"
                f"         FIX: Do full 24-bit subtraction (pb_total - pb_read), then check\n"
                f"         if high/middle bytes of result are 0. If so, low byte = exact count.\n"
                f"         If not, cap at 255."
            )

            hr_insns = find_proc_in_listing(listing, 'http_render_progress')
            if not hr_insns:
                hr_insns = find_proc_in_listing(listing, 'http_render')
            if hr_insns:
                chunk_insns = []
                capture = False
                for addr, bytez, asm in hr_insns:
                    if 'pb_total+2' in asm and not capture:
                        capture = True
                    if capture:
                        chunk_insns.append((addr, bytez, asm))
                    if capture and ('lda #' in asm.lower() and '255' in asm):
                        break
                if chunk_insns:
                    diag += f"\n         CPU trace (pb_total=$289F=10399, pb_read=$27D8=10200, remaining=199):\n"
                    diag += cpu_trace(chunk_insns[:10],
                        regs={'A': 0x00, 'X': 0, 'Y': 0, 'S': 0xEB, 'P': 0x30},
                        scenario="Last chunk: 199 bytes remain but code reads 255")

            errors.append(diag)
        else:
            warnings.append(
                f"BUFFER: cannot verify http_render chunk size calculation ({fname_hr}:{line_hr})")

    # General check: scan for multi-byte counter patterns
    for fname_f, lines_f in files.items():
        for i_f, l_f in enumerate(lines_f):
            sl = l_f.strip().lower()
            if re.match(r'cmp\s+\w+\+[12]', sl):
                next_lines = ''.join(lines_f[i_f+1:i_f+4]).lower()
                if 'bne' in next_lines and 'lda #255' in ''.join(lines_f[i_f:i_f+15]).lower():
                    context = ''.join(lines_f[max(0,i_f-10):i_f+15]).lower()
                    if 'sbc' not in context:
                        loc = f"{fname_f}:{i_f+1}"
                        already = any(loc in str(e) for e in errors)
                        if not already:
                            warnings.append(
                                f"BUFFER: suspicious byte-compare chunk pattern at {loc}\n"
                                f"         '{l_f.strip()}' followed by bne + lda #255\n"
                                f"         May overread if remaining < 256 but high bytes differ.\n"
                                f"         Consider using proper multi-byte subtraction.")

    return ok_count, errors, warnings
