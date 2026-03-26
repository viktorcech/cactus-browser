"""Sections 9, 10g: MEMAC B shadow + safety validation."""
import re
from .asm_utils import find_in_asm, get_proc, fmt_asm_lines, find_proc_in_listing, get_const


def check(files, ctx):
    errors = []
    warnings = []
    ok_count = 0

    listing = ctx['listing']

    # --- 9. MEMAC B shadow ---
    hits = find_in_asm(files, r'memb_on\s+\.macro')
    if hits:
        fname, line, _ = hits[0]
        macro_lines = []
        macro = ''
        for idx, l in enumerate(files[fname][line-1:line+8]):
            macro += l
            macro_lines.append((line+idx, l.rstrip()))
        sp = macro.find('zp_memb_shadow')
        rp = macro.find('VBXE_MEMAC_B')
        if sp >= 0 and rp >= 0 and sp < rp:
            print(f"  [OK]   MEMB: shadow written before register (NMI-safe)")
            ok_count += 1
        else:
            diag = (
                f"MEMB: register written before shadow ({fname}:{line})\n"
                f"         BUG: If NMI fires between STA VBXE_MEMAC_B and STA zp_memb_shadow,\n"
                f"         the NMI handler restores wrong MEMAC B state from stale shadow.\n"
                f"         FIX: Write zp_memb_shadow FIRST, then VBXE_MEMAC_B register.\n"
                f"         Macro code:\n"
            )
            diag += fmt_asm_lines(macro_lines)
            errors.append(diag)

    # --- 10g. MEMAC B safety validation ---
    print()
    print("  --- MEMAC B SAFETY ---")
    memb_ok = 0

    memb_procs = set()
    for fname_m, lines_m in files.items():
        cur_proc = None
        for lm in lines_m:
            pm = re.search(r'\.proc\s+(\w+)', lm)
            if pm:
                cur_proc = pm.group(1)
            if 'memb_on' in lm.lower() and cur_proc:
                memb_procs.add(cur_proc)
            if '.endp' in lm:
                cur_proc = None

    if memb_procs and listing:
        memb_above_4000 = []
        memb_below_4000 = []
        for pname in sorted(memb_procs):
            for addr, bytez, asm in listing:
                if f'.proc {pname}' in asm:
                    if addr >= 0x4000:
                        memb_above_4000.append((pname, addr))
                    else:
                        memb_below_4000.append((pname, addr))
                    break

        if not memb_above_4000:
            hi_addr = max(a for _, a in memb_below_4000) if memb_below_4000 else 0
            print(f"  [OK]   MEMB: all {len(memb_below_4000)} procs with memb_on are below $4000"
                  f" (highest: ${hi_addr:04X})")
            memb_ok += 1
        else:
            for pname, addr in memb_above_4000:
                errors.append(
                    f"MEMB: {pname} at ${addr:04X} uses memb_on but is in MEMAC B window!\n"
                    f"         VBXE SPEC: $4000-$7FFF maps to VRAM when MEMAC B is active.\n"
                    f"         Enabling MEMAC B from code at ${addr:04X} = CPU executes VRAM\n"
                    f"         data instead of your code = instant crash.\n"
                    f"         FIX: Move this proc below $4000 (reorganize include order).")

        if memb_below_4000:
            hi_addr = max(a for _, a in memb_below_4000)
            hi_proc = [p for p, a in memb_below_4000 if a == hi_addr][0]
            proc_insns = find_proc_in_listing(listing, hi_proc)
            if proc_insns:
                last_addr = proc_insns[-1][0]
                last_bytes = len(proc_insns[-1][1].split()) if proc_insns[-1][1] else 1
                end_addr = last_addr + last_bytes
                headroom = 0x4000 - end_addr
                if headroom < 0x100:
                    warnings.append(
                        f"MEMB: only ${headroom:X} bytes headroom below $4000!\n"
                        f"         {hi_proc} ends near ${end_addr:04X}. Adding code may push past $4000.\n"
                        f"         VBXE SPEC: All MEMAC B code must stay below $4000.")
                elif headroom < 0x400:
                    print(f"  [INFO] MEMB: ${headroom:X} bytes headroom below $4000 "
                          f"({hi_proc} ends ~${end_addr:04X})")
                else:
                    print(f"  [OK]   MEMB: ${headroom:X} bytes headroom below $4000")
                    memb_ok += 1

    elif memb_procs and not listing:
        warnings.append(
            f"MEMB: {len(memb_procs)} procs use memb_on but no listing file to verify addresses\n"
            f"         Build with: mads browser.asm -l:browser.lab to generate listing.\n"
            f"         Cannot verify MEMAC B safety without addresses.")

    # MEMAC B window wrapping check
    for pname in ['vbxe_img_write_chunk', 'vbxe_pb_write_chunk', 'vbxe_pb_read_chunk']:
        fname_wc, line_wc, body_wc = get_proc(files, pname)
        if not body_wc:
            continue
        has_80_check = bool(re.search(r'cmp\s+#\$80|cmp\s+#128', body_wc, re.IGNORECASE))
        has_40_reset = bool(re.search(r'lda\s+#\$40|lda\s+#64', body_wc, re.IGNORECASE))
        has_bank_inc = bool(re.search(r'inc\s+.*bank|inc\s+.*memb', body_wc, re.IGNORECASE))
        if has_80_check and has_40_reset:
            memb_ok += 1
        elif has_bank_inc:
            warnings.append(
                f"MEMB: {pname} increments bank but may not wrap window correctly\n"
                f"         VBXE SPEC: When MEMAC B ptr reaches $8000, must reset to $4000\n"
                f"         and increment bank number. Missing reset = write to RAM, not VRAM.")

    wrap_procs = [p for p in ['vbxe_img_write_chunk', 'vbxe_pb_write_chunk', 'vbxe_pb_read_chunk']
                  if get_proc(files, p)[2]]
    wrap_checked = sum(1 for p in wrap_procs
                       if re.search(r'cmp\s+#\$80', get_proc(files, p)[2] or '', re.IGNORECASE))
    if wrap_checked == len(wrap_procs) and wrap_procs:
        print(f"  [OK]   MEMB: all {wrap_checked} VRAM chunk procs have $80/$40 window wrapping")

    ok_count += memb_ok

    return ok_count, errors, warnings
