"""Section 10f: SIO/FujiNet protocol validation."""
import re
from .asm_utils import get_proc, get_const


def check(files, ctx):
    errors = []
    warnings = []
    ok_count = 0

    print()
    print("  --- SIO PROTOCOL VALIDATION ---")
    sio_ok = 0

    SIO_SPEC = {
        'fn_open': {
            'DSTATS': ('SIO_WRITE', '$80', 0x80, 'OPEN sends URL data to FujiNet'),
            'DBYT': ('URL_BUF_SIZE', '256', 256,
                     'Must send full 256-byte buffer (FujiNet expects exactly 256)'),
            'DAUX1': ('FN_OPEN_READ', '4', 4,
                      'HTTP GET = mode 4. Mode 12 = read+write (wrong for GET)'),
        },
        'fn_status': {
            'DSTATS': ('SIO_READ', '$40', 0x40, 'STATUS receives 4 bytes from FujiNet'),
            'DBYT': (None, '4', 4, 'STATUS always returns exactly 4 bytes'),
        },
        'fn_read': {
            'DSTATS': ('SIO_READ', '$40', 0x40, 'READ receives data from FujiNet'),
        },
        'fn_close': {
            'DSTATS': ('SIO_NONE', '$00', 0x00,
                       'CLOSE has no data transfer. $40/$80 = SIO waits for data = timeout'),
        },
    }

    for proc_name, checks in SIO_SPEC.items():
        fname_sio, line_sio, body_sio = get_proc(files, proc_name)
        if not body_sio:
            warnings.append(f"SIO: {proc_name} proc not found")
            continue

        proc_ok = True
        for field, (const_name, expected_str, expected_val, reason) in checks.items():
            if field == 'DBYT':
                lo_match = re.search(r'lda\s+(.+?)\s*\n\s*sta\s+DBYTLO', body_sio,
                                     re.IGNORECASE)
                hi_match = re.search(r'lda\s+(.+?)\s*\n\s*sta\s+DBYTHI', body_sio,
                                     re.IGNORECASE)
                if lo_match and hi_match:
                    lo_expr = lo_match.group(1).strip()
                    hi_expr = hi_match.group(1).strip()
                    lo_val = None
                    hi_val = None
                    for expr, target in [(lo_expr, 'lo'), (hi_expr, 'hi')]:
                        val = None
                        m_ref = re.match(r'#([<>])(\w+)', expr)
                        if m_ref:
                            cv = get_const(files, m_ref.group(2))
                            if cv is not None:
                                val = (cv & 0xFF) if m_ref.group(1) == '<' else (cv >> 8) & 0xFF
                        if val is None:
                            m_imm = re.match(r'#\$([0-9A-Fa-f]+)', expr)
                            if m_imm:
                                val = int(m_imm.group(1), 16)
                            else:
                                m_imm = re.match(r'#(\d+)', expr)
                                if m_imm:
                                    val = int(m_imm.group(1))
                        if target == 'lo':
                            lo_val = val
                        else:
                            hi_val = val

                    if lo_val is not None and hi_val is not None:
                        actual = lo_val + (hi_val << 8)
                        if actual != expected_val:
                            errors.append(
                                f"SIO: {proc_name} DBYT = {actual}, expected {expected_val}\n"
                                f"         FujiNet SPEC: {reason}")
                            proc_ok = False
                continue

            # Single-byte fields: DSTATS, DAUX1
            sta_pattern = rf'lda\s+(.+?)\s*\n\s*sta\s+{field}'
            m_sta = re.search(sta_pattern, body_sio, re.IGNORECASE)
            if not m_sta:
                lines_list = body_sio.split('\n')
                last_lda = None
                found = False
                for bl in lines_list:
                    sl = bl.strip().lower()
                    if sl.startswith('lda'):
                        last_lda = bl.strip()
                    elif f'sta {field.lower()}' in sl and last_lda:
                        m_sta = re.match(r'lda\s+(.+)', last_lda, re.IGNORECASE)
                        if m_sta:
                            found = True
                            break
                if not found:
                    continue

            if m_sta:
                load_expr = m_sta.group(1).strip()
                actual_val = None
                m_const = re.match(r'#(\w+)', load_expr)
                if m_const:
                    cv = get_const(files, m_const.group(1))
                    if cv is not None:
                        actual_val = cv
                    elif const_name and m_const.group(1) == const_name:
                        actual_val = expected_val
                if actual_val is None:
                    m_hex = re.match(r'#\$([0-9A-Fa-f]+)', load_expr)
                    if m_hex:
                        actual_val = int(m_hex.group(1), 16)
                if actual_val is None:
                    m_dec = re.match(r'#(\d+)', load_expr)
                    if m_dec:
                        actual_val = int(m_dec.group(1))

                if actual_val is not None and actual_val != expected_val:
                    errors.append(
                        f"SIO: {proc_name} {field} = ${actual_val:02X}, expected ${expected_val:02X}\n"
                        f"         FujiNet SPEC: {reason}")
                    proc_ok = False

        if proc_ok:
            sio_ok += 1

    # --- SIO-5: fn_read max 255 bytes check ---
    fname_fr, line_fr, body_fr = get_proc(files, 'fn_read')
    if body_fr:
        has_255_cap = bool(re.search(r'lda\s+#255|lda\s+#\$FF', body_fr, re.IGNORECASE))
        has_hi_check = bool(re.search(r'zp_fn_bytes_hi', body_fr))
        has_hi_branch_to_max = False
        if has_hi_check:
            has_hi_branch_to_max = bool(re.search(
                r'lda\s+zp_fn_bytes_hi\s*\n\s*bne\s+\?max', body_fr, re.IGNORECASE))

        if has_255_cap and has_hi_branch_to_max:
            print(f"  [OK]   SIO: fn_read caps at 255 bytes (8-bit overflow safe)")
            sio_ok += 1
        elif has_255_cap:
            print(f"  [OK]   SIO: fn_read has 255-byte cap")
            sio_ok += 1
        else:
            errors.append(
                f"SIO: fn_read has no 255-byte cap!\n"
                f"         FujiNet SPEC: Reading 256 bytes sets zp_rx_len=0 (8-bit overflow).\n"
                f"         Parser sees 0 bytes read = data loss. Max safe value is 255.\n"
                f"         FIX: If bytes_hi > 0, cap at 255: lda #255 / sta zp_rx_len")

    # --- SIO-6: fn_read DAUX == DBYT check ---
    if body_fr:
        has_daux_eq_dbyt = (
            bool(re.search(r'lda\s+DBYTLO\s*\n\s*sta\s+DAUX1', body_fr, re.IGNORECASE)) and
            bool(re.search(r'lda\s+DBYTHI\s*\n\s*sta\s+DAUX2', body_fr, re.IGNORECASE))
        )
        if has_daux_eq_dbyt:
            print(f"  [OK]   SIO: fn_read DAUX1/2 = DBYTLO/HI (FujiNet requirement)")
            sio_ok += 1
        else:
            body_lines = body_fr.split('\n')
            daux_sources = {}
            dbyt_sources = {}
            last_lda = None
            for bl in body_lines:
                sl = bl.strip()
                if re.match(r'lda\s+', sl, re.IGNORECASE):
                    last_lda = re.sub(r'^lda\s+', '', sl, flags=re.IGNORECASE).strip()
                elif last_lda:
                    sl_low = sl.lower()
                    if 'sta daux1' in sl_low:
                        daux_sources['lo'] = last_lda
                    elif 'sta daux2' in sl_low:
                        daux_sources['hi'] = last_lda
                    elif 'sta dbytlo' in sl_low:
                        dbyt_sources['lo'] = last_lda
                    elif 'sta dbythi' in sl_low:
                        dbyt_sources['hi'] = last_lda
                    if not re.match(r'sta\s+', sl, re.IGNORECASE):
                        last_lda = None

            lo_match = daux_sources.get('lo') == dbyt_sources.get('lo') if daux_sources.get('lo') else False
            hi_match = daux_sources.get('hi') == dbyt_sources.get('hi') if daux_sources.get('hi') else False
            if lo_match and hi_match:
                print(f"  [OK]   SIO: fn_read DAUX = DBYT (same source value)")
                sio_ok += 1
            elif 'DAUX1' in body_fr and 'DAUX2' in body_fr:
                warnings.append(
                    f"SIO: fn_read sets DAUX1/2 but cannot verify they match DBYT\n"
                    f"         FujiNet SPEC: DAUX1/2 must equal DBYTLO/HI for READ command.")
            else:
                errors.append(
                    f"SIO: fn_read does not set DAUX1/2!\n"
                    f"         FujiNet SPEC: READ requires DAUX1=DBYTLO, DAUX2=DBYTHI.\n"
                    f"         Missing DAUX = FujiNet ignores byte count = wrong read size.")

    # Print summary
    basic_count = len(SIO_SPEC)
    if sio_ok >= basic_count:
        print(f"  [OK]   SIO: all {basic_count} SIO procs have correct DCB field values")
    elif sio_ok > 0:
        print(f"  [INFO] SIO: {sio_ok} of {basic_count + 2} checks passed")

    ok_count += sio_ok

    return ok_count, errors, warnings
