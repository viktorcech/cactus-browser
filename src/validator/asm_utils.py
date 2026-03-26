"""ASM/listing parsing, CPU trace generation, utility functions."""
import os, re


def read_asm_files(src_dir):
    """Read all .asm files, return dict of filename -> lines."""
    files = {}
    for f in os.listdir(src_dir):
        if f.endswith('.asm'):
            with open(os.path.join(src_dir, f), 'r', encoding='utf-8', errors='ignore') as fh:
                files[f] = fh.readlines()
    return files


def find_in_asm(files, pattern):
    """Search all ASM files for pattern. Returns [(file, lineno, line)]."""
    results = []
    for fname, lines in files.items():
        for i, line in enumerate(lines):
            if re.search(pattern, line, re.IGNORECASE):
                results.append((fname, i+1, line.rstrip()))
    return results


def get_proc(files, name):
    """Get body of .proc as string."""
    for fname, lines in files.items():
        for i, line in enumerate(lines):
            if re.search(rf'\.proc\s+{name}\b', line):
                body = ''
                for j in range(i, min(i+300, len(lines))):
                    body += lines[j]
                    if '.endp' in lines[j]: break
                return fname, i+1, body
    return None, None, None


def get_proc_numbered(files, name):
    """Get body of .proc with numbered lines for debug output."""
    for fname, lines in files.items():
        for i, line in enumerate(lines):
            if re.search(rf'\.proc\s+{name}\b', line):
                numbered = []
                for j in range(i, min(i+50, len(lines))):
                    numbered.append((j+1, lines[j].rstrip()))
                    if '.endp' in lines[j]: break
                body = '\n'.join(lines[j].rstrip() for j in range(i, min(i+50, len(lines)))
                                 if j < len(lines))
                return fname, i+1, body, numbered
    return None, None, None, None


def fmt_asm_lines(numbered, indent='           '):
    """Format numbered ASM lines for debug output."""
    out = ''
    for lineno, text in numbered:
        text = text.rstrip()
        if not text or '.endp' in text:
            continue
        out += f"{indent}{lineno:4d}| {text}\n"
    return out


# ---------------------------------------------------------------------------
# Listing file parser + CPU trace generator
# ---------------------------------------------------------------------------
def parse_listing(lab_path):
    """Parse MADS listing file. Returns list of (addr, bytes_hex, asm_text)."""
    if not os.path.exists(lab_path):
        return None
    instructions = []
    with open(lab_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            # Lines with bytes: "    10 3B46 AD 00 88		lda url_buffer"
            m = re.match(
                r'\s*\d+\s+([0-9A-F]{4})\s+((?:[0-9A-F]{2}\s)+)\s*(.+)',
                line)
            if m:
                addr = int(m.group(1), 16)
                bytez = m.group(2).strip()
                asm = m.group(3).strip()
                instructions.append((addr, bytez, asm))
                continue
            # Lines with address only (labels, .proc): "     8 3B46			.proc name"
            m = re.match(
                r'\s*\d+\s+([0-9A-F]{4})\s*\t+\s*(.+)',
                line)
            if m:
                addr = int(m.group(1), 16)
                asm = m.group(2).strip()
                instructions.append((addr, '', asm))
    return instructions


def find_proc_in_listing(listing, proc_name):
    """Find a proc's instructions in the listing by looking for the .proc label."""
    if not listing:
        return []
    # Find proc start address
    start_addr = None
    for addr, bytez, asm in listing:
        if f'.proc {proc_name}' in asm:
            start_addr = addr
            break
    if start_addr is None:
        return []

    # Collect instructions until .endp or RTS
    proc_insns = []
    collecting = False
    for addr, bytez, asm in listing:
        if addr == start_addr:
            collecting = True
        if not collecting:
            continue
        if '.endp' in asm:
            break
        if bytez:  # only actual instructions (with bytes)
            proc_insns.append((addr, bytez, asm))
        if 'rts' in asm.lower() and collecting and len(proc_insns) > 1:
            break
    return proc_insns


def cpu_trace(insns, regs=None, scenario='', indent='           '):
    """Generate Altirra-style CPU trace from listing instructions.
    regs = dict with initial A, X, Y, S, P values.
    Returns formatted trace string.
    """
    if not insns:
        return ''
    if regs is None:
        regs = {'A': 0, 'X': 0, 'Y': 0, 'S': 0xED, 'P': 0x32}

    out = ''
    if scenario:
        out += f"{indent}Scenario: {scenario}\n"
    out += f"{indent}{'Addr':>4s}  {'Bytes':<12s} {'ASM':<32s}  Regs\n"
    out += f"{indent}{'-'*70}\n"

    a, x, y = regs['A'], regs['X'], regs['Y']
    s, p = regs.get('S', 0xED), regs.get('P', 0x32)

    for addr, bytez, asm in insns:
        # Format flags
        flags = ''
        flags += 'N' if p & 0x80 else ' '
        flags += 'V' if p & 0x40 else ' '
        flags += '  '  # bit 5 always set, bit 4 (B) only on stack
        flags += 'D' if p & 0x08 else ' '
        flags += 'I' if p & 0x04 else ' '
        flags += 'Z' if p & 0x02 else ' '
        flags += 'C' if p & 0x01 else ' '

        out += (f"{indent}{addr:04X}: {bytez:<12s} {asm:<32s}  "
                f"A={a:02X} X={x:02X} Y={y:02X} S={s:02X} P={p:02X} ({flags})\n")

        # Simplified CPU emulation for common instructions
        low_asm = asm.lower().strip()
        if low_asm.startswith('lda #'):
            m = re.search(r'#\$([0-9A-Fa-f]+)', asm)
            if m:
                a = int(m.group(1), 16) & 0xFF
            elif re.search(r"#'(.)'", asm):
                a = ord(re.search(r"#'(.)'", asm).group(1))
            p = (p & ~0x82) | (0x80 if a & 0x80 else 0) | (0x02 if a == 0 else 0)
        elif low_asm.startswith('ldx #'):
            m = re.search(r'#\$([0-9A-Fa-f]+)', asm)
            if m: x = int(m.group(1), 16) & 0xFF
            p = (p & ~0x82) | (0x80 if x & 0x80 else 0) | (0x02 if x == 0 else 0)
        elif low_asm.startswith('ldy #'):
            m = re.search(r'#\$([0-9A-Fa-f]+)', asm)
            if m: y = int(m.group(1), 16) & 0xFF
            p = (p & ~0x82) | (0x80 if y & 0x80 else 0) | (0x02 if y == 0 else 0)
        elif low_asm.startswith('cmp #'):
            m = re.search(r'#\$([0-9A-Fa-f]+)', asm)
            val = 0
            if m:
                val = int(m.group(1), 16)
            elif re.search(r"#'(.)'", asm):
                val = ord(re.search(r"#'(.)'", asm).group(1))
            result = (a - val) & 0xFF
            p = (p & ~0x83) | (0x80 if result & 0x80 else 0) | \
                (0x02 if result == 0 else 0) | (0x01 if a >= val else 0)
        elif low_asm.startswith('cpx #'):
            m = re.search(r'#\$([0-9A-Fa-f]+)', asm)
            val = int(m.group(1), 16) if m else 0
            result = (x - val) & 0xFF
            p = (p & ~0x83) | (0x80 if result & 0x80 else 0) | \
                (0x02 if result == 0 else 0) | (0x01 if x >= val else 0)
        elif 'sec' in low_asm:
            p |= 0x01
        elif 'clc' in low_asm:
            p &= ~0x01
        elif low_asm.startswith('sbc #'):
            m = re.search(r'#\$([0-9A-Fa-f]+)', asm)
            if m:
                val = int(m.group(1), 16)
                result = a - val - (0 if p & 0x01 else 1)
                p = (p & ~0x83) | (0x01 if result >= 0 else 0)
                a = result & 0xFF
                p |= (0x80 if a & 0x80 else 0) | (0x02 if a == 0 else 0)
        elif low_asm.startswith('adc #'):
            m = re.search(r'#\$([0-9A-Fa-f]+)', asm)
            if m:
                val = int(m.group(1), 16)
                result = a + val + (1 if p & 0x01 else 0)
                p = (p & ~0x83) | (0x01 if result > 0xFF else 0)
                a = result & 0xFF
                p |= (0x80 if a & 0x80 else 0) | (0x02 if a == 0 else 0)
        elif 'tax' in low_asm:
            x = a
            p = (p & ~0x82) | (0x80 if x & 0x80 else 0) | (0x02 if x == 0 else 0)
        elif 'tay' in low_asm:
            y = a
            p = (p & ~0x82) | (0x80 if y & 0x80 else 0) | (0x02 if y == 0 else 0)
        elif 'txa' in low_asm:
            a = x
            p = (p & ~0x82) | (0x80 if a & 0x80 else 0) | (0x02 if a == 0 else 0)
        elif 'tya' in low_asm:
            a = y
            p = (p & ~0x82) | (0x80 if a & 0x80 else 0) | (0x02 if a == 0 else 0)
        elif 'inx' in low_asm:
            x = (x + 1) & 0xFF
            p = (p & ~0x82) | (0x80 if x & 0x80 else 0) | (0x02 if x == 0 else 0)
        elif 'iny' in low_asm:
            y = (y + 1) & 0xFF
            p = (p & ~0x82) | (0x80 if y & 0x80 else 0) | (0x02 if y == 0 else 0)
        elif 'dex' in low_asm:
            x = (x - 1) & 0xFF
            p = (p & ~0x82) | (0x80 if x & 0x80 else 0) | (0x02 if x == 0 else 0)
        elif 'dey' in low_asm:
            y = (y - 1) & 0xFF
            p = (p & ~0x82) | (0x80 if y & 0x80 else 0) | (0x02 if y == 0 else 0)
        elif low_asm.startswith('ora #'):
            m = re.search(r'#\$([0-9A-Fa-f]+)', asm)
            if m:
                a = (a | int(m.group(1), 16)) & 0xFF
                p = (p & ~0x82) | (0x80 if a & 0x80 else 0) | (0x02 if a == 0 else 0)

    return out


def get_const(files, name, _depth=0):
    """Get constant value from ASM: NAME = $XX or NAME = NN or expression."""
    if _depth > 8:
        return None
    for fname, lines in files.items():
        for line in lines:
            m = re.match(rf'{name}\s*=\s*(.+?)(?:;.*)?$', line.strip())
            if not m:
                continue
            expr = m.group(1).strip()
            # Simple hex
            mh = re.fullmatch(r'\$([0-9A-Fa-f]+)', expr)
            if mh:
                return int(mh.group(1), 16)
            # Simple decimal
            md = re.fullmatch(r'(\d+)', expr)
            if md:
                return int(md.group(1))
            # Expression: replace known constants and evaluate
            e = expr
            # Replace $hex with 0x notation
            e = re.sub(r'\$([0-9A-Fa-f]+)', r'0x\1', e)
            # Replace referenced constants
            for ref_name in re.findall(r'[A-Za-z_]\w*', e):
                ref_val = get_const(files, ref_name, _depth + 1)
                if ref_val is not None:
                    e = re.sub(rf'\b{ref_name}\b', str(ref_val), e)
            try:
                val = int(eval(e))
                return val
            except Exception:
                pass
    return None


def strip_html(html):
    """Simple HTML to plain text (like our ASM parser does)."""
    t = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.S|re.I)
    t = re.sub(r'<style[^>]*>.*?</style>', '', t, flags=re.S|re.I)
    t = re.sub(r'<!--.*?-->', '', t, flags=re.S)
    t = re.sub(r'<head>.*?</head>', '', t, flags=re.S|re.I)
    t = re.sub(r'<[^>]+>', ' ', t)
    t = t.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
    t = t.replace('&nbsp;', ' ').replace('&quot;', '"')
    t = re.sub(r'\s+', ' ', t).strip()
    return t
