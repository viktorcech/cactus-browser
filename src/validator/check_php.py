"""PHP server-side scripts validation — proxy.php, vbxe.php."""
import os
import re


def check(files, ctx):
    errors = []
    warnings = []
    ok_count = 0

    project_dir = ctx['project_dir']
    tools_dir = os.path.join(project_dir, 'tools')

    if not os.path.isdir(tools_dir):
        warnings.append("PHP: tools/ directory not found, skipping PHP checks")
        return ok_count, errors, warnings

    print("\n  --- PHP SERVER CHECKS ---")

    php_files = {}
    for fname in os.listdir(tools_dir):
        if fname.endswith('.php'):
            path = os.path.join(tools_dir, fname)
            with open(path, 'r', encoding='utf-8', errors='replace') as f:
                php_files[fname] = f.read()

    if not php_files:
        warnings.append("PHP: no .php files found in tools/")
        return ok_count, errors, warnings

    # -----------------------------------------------------------------------
    # CHECK: proxy.php
    # -----------------------------------------------------------------------
    if 'proxy.php' in php_files:
        src = php_files['proxy.php']

        # PHP-1: Regex delimiter collision
        # Using # as delimiter with literal # inside pattern causes silent failure
        regex_matches = re.findall(r"preg_match\s*\(\s*(['\"])(.)(.*?)\2[gimsux]*\1", src)
        # Simpler: find all preg_match/preg_replace calls and check for # delimiter issues
        for m in re.finditer(r'preg_match\s*\(\s*[\'"](.)[\'"]?\s*,', src):
            pass  # complex to parse PHP regex from Python

        # Direct check: look for # delimiter with unescaped # inside
        hash_regexes = re.findall(r"preg_match\s*\(\s*'(#[^']+)'", src)
        hash_regexes += re.findall(r'preg_match\s*\(\s*"(#[^"]+)"', src)
        for rx in hash_regexes:
            # Count # occurrences — should be exactly 2 (open + close delimiter)
            hashes = [i for i, c in enumerate(rx) if c == '#']
            if len(hashes) > 2:
                errors.append(
                    f"PHP-1: proxy.php regex delimiter collision: {rx[:60]}...\n"
                    f"         '#' used as delimiter AND as literal inside pattern.\n"
                    f"         Absolute URLs won't be detected -> double-wrapping.\n"
                    f"         FIX: use '/' delimiter or escape \\#")
            elif len(hashes) == 2:
                # Check if pattern between delimiters contains what looks like an incomplete group
                inner = rx[hashes[0]+1:hashes[1]]
                if inner.count('(') != inner.count(')'):
                    errors.append(
                        f"PHP-1: proxy.php regex has unbalanced parens: {rx[:60]}...\n"
                        f"         Pattern between # delimiters: {inner[:50]}\n"
                        f"         Likely # inside pattern treated as closing delimiter.")

        if not any('PHP-1' in e for e in errors):
            # Verify absolute URL detection exists and looks correct
            if re.search(r'https?\s*:', src) and re.search(r'preg_match.*https', src):
                print(f"  [OK]   PHP-1: proxy.php absolute URL detection regex OK")
                ok_count += 1
            else:
                warnings.append("PHP-1: proxy.php may not detect absolute URLs")

        # PHP-2: Content-Length header (FujiNet can't handle chunked)
        if 'Content-Length' in src:
            print(f"  [OK]   PHP-2: proxy.php sends Content-Length (no chunked transfer)")
            ok_count += 1
        else:
            errors.append(
                "PHP-2: proxy.php missing Content-Length header\n"
                "         FujiNet cannot handle chunked Transfer-Encoding.\n"
                "         FIX: add header('Content-Length: ' . strlen($html));")

        # PHP-3: URL scheme preserved (relative URL conversion)
        if re.search(r'base_origin.*base_dir', src) or re.search(r'base_scheme.*base_host', src):
            print(f"  [OK]   PHP-3: proxy.php preserves URL scheme in relative->absolute conversion")
            ok_count += 1
        else:
            warnings.append("PHP-3: proxy.php URL conversion may not preserve scheme")

        # PHP-4: Redirect handling (follow_location or Location header)
        if 'follow_location' in src or 'CURLOPT_FOLLOWLOCATION' in src:
            if 'Location:' in src or 'EFFECTIVE_URL' in src:
                print(f"  [OK]   PHP-4: proxy.php follows redirects and updates base URL")
                ok_count += 1
            else:
                warnings.append("PHP-4: proxy.php follows redirects but may not update base URL")
        else:
            warnings.append("PHP-4: proxy.php may not follow redirects")

        # PHP-5: Dangerous attribute stripping — must NOT strip src, href, alt
        strip_match = re.search(r'(?:class\|style\|.*?)=', src)
        if strip_match:
            strip_line = strip_match.group(0)
            for keep_attr in ['src', 'href', 'alt']:
                if re.search(r'\b' + keep_attr + r'\b', strip_line):
                    errors.append(
                        f"PHP-5: proxy.php strips '{keep_attr}' attribute!\n"
                        f"         This attribute is needed by the browser.\n"
                        f"         FIX: remove '{keep_attr}' from the strip regex")
            if not any('PHP-5' in e for e in errors):
                print(f"  [OK]   PHP-5: proxy.php preserves src, href, alt attributes")
                ok_count += 1

    # -----------------------------------------------------------------------
    # CHECK: vbxe.php
    # -----------------------------------------------------------------------
    if 'vbxe.php' in php_files:
        src = php_files['vbxe.php']

        # PHP-6: Content-Length header
        if 'Content-Length' in src:
            print(f"  [OK]   PHP-6: vbxe.php sends Content-Length (no chunked transfer)")
            ok_count += 1
        else:
            errors.append(
                "PHP-6: vbxe.php missing Content-Length header\n"
                "         FujiNet cannot handle chunked Transfer-Encoding.")

        # PHP-7: Binary format — header must be 2B width + 1B height + 768B palette
        if re.search(r"pack\s*\(\s*'v'", src) and '768' in src or '248' in src:
            print(f"  [OK]   PHP-7: vbxe.php outputs correct binary format (width LE + height + palette)")
            ok_count += 1
        else:
            warnings.append("PHP-7: vbxe.php binary format may not match browser expectations")

        # PHP-8: Color index offset (+8 for reserved palette entries)
        if re.search(r'\+\s*8\b', src):
            print(f"  [OK]   PHP-8: vbxe.php pixel values offset by +8 (reserved palette entries)")
            ok_count += 1
        else:
            errors.append(
                "PHP-8: vbxe.php missing +8 pixel offset\n"
                "         Browser reserves palette 0-7 for text colors.\n"
                "         Image pixels must use indices 8-255.")

        # PHP-9: Color depth — must halve RGB for VBXE (7-bit per channel)
        if re.search(r'>>\s*1', src):
            print(f"  [OK]   PHP-9: vbxe.php halves RGB values (VBXE 7-bit per channel)")
            ok_count += 1
        else:
            errors.append(
                "PHP-9: vbxe.php not halving RGB values\n"
                "         VBXE palette uses 7-bit color (0-127 per channel).\n"
                "         FIX: $rgb['red'] >> 1, etc.")

        # PHP-10: Image size limits
        if re.search(r'320', src) and re.search(r'192', src):
            print(f"  [OK]   PHP-10: vbxe.php enforces 320x192 max image size")
            ok_count += 1
        else:
            warnings.append("PHP-10: vbxe.php max image size limits not found")

        # PHP-11: SSL verification disabled (many Atari-era sites have bad certs)
        if ('verify_peer' in src or 'SSL_VERIFYPEER' in src) and 'false' in src:
            print(f"  [OK]   PHP-11: vbxe.php disables SSL verify (compatibility)")
            ok_count += 1
        else:
            warnings.append("PHP-11: vbxe.php may reject sites with invalid SSL certs")

        # PHP-12: Converter URL in ASM must match PHP endpoint
        asm_prefix = None
        for fname, lines in files.items():
            content = ''.join(lines)
            m = re.search(r"m_prefix\s+dta\s+c'([^']+)'", content)
            if m:
                asm_prefix = m.group(1)
                break
        if asm_prefix:
            # Extract expected PHP params from m_suffix
            asm_suffix = None
            for fname, lines in files.items():
                content = ''.join(lines)
                m = re.search(r"m_suffix\s+dta\s+c'([^']+)'", content)
                if m:
                    asm_suffix = m.group(1)
                    break
            if 'vbxe.php' in asm_prefix:
                # Check that PHP reads the expected GET params
                params_ok = True
                if asm_suffix:
                    for param in re.findall(r'(\w+)=', asm_suffix):
                        if f"$_GET['{param}']" not in src and f'$_GET["{param}"]' not in src:
                            errors.append(
                                f"PHP-12: vbxe.php doesn't read GET param '{param}'\n"
                                f"         ASM sends: {asm_suffix}\n"
                                f"         FIX: add ${param} = $_GET['{param}'] in vbxe.php")
                            params_ok = False
                if params_ok:
                    print(f"  [OK]   PHP-12: vbxe.php GET params match ASM m_suffix")
                    ok_count += 1
            else:
                warnings.append(f"PHP-12: ASM m_prefix doesn't point to vbxe.php: {asm_prefix}")

    return ok_count, errors, warnings
