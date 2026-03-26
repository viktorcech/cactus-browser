"""Sections 6f, 7, 8: UX flow, URL prefix, palette checks."""
import re
from .asm_utils import (get_proc, get_proc_numbered, get_const,
                         find_proc_in_listing, cpu_trace)


def check(files, ctx):
    errors = []
    warnings = []
    ok_count = 0

    listing = ctx['listing']

    # --- 6f. UX flow checks ---
    print()
    print("  --- UX FLOW CHECKS ---")
    ux_ok = 0

    # UX-1: Q during page_abort must return to welcome screen
    fname_hn, line_hn, body_hn = get_proc(files, 'http_navigate')
    if body_hn:
        has_abort_check = bool(re.search(r'page_abort', body_hn))
        has_welcome_after_abort = bool(re.search(
            r'page_abort.*show_welcome', body_hn, re.DOTALL))
        if has_welcome_after_abort:
            print(f"  [OK]   UX: Q during render returns to welcome screen")
            ux_ok += 1
        elif has_abort_check:
            warnings.append(
                f"UX: http_navigate checks page_abort but doesn't call show_welcome\n"
                f"         User expects Q = quit to menu, not just stop rendering.")
        else:
            errors.append(
                f"UX: http_navigate ignores page_abort ({fname_hn}:{line_hn})\n"
                f"         BUG: Q during '-- More --' stops rendering but stays on page.\n"
                f"         Title bar still shows page title, status shows '-- End --'.\n"
                f"         User expects Q = return to welcome/main menu.\n"
                f"         FIX: After http_render, check page_abort. If set, call\n"
                f"         fn_close + html_reset + render_reset + show_welcome.")

    # UX-2: Q in end-of-page (ui_main_loop) must return to welcome
    fname_ui, line_ui, body_ui = get_proc(files, 'ui_main_loop')
    if body_ui:
        q_to_welcome = bool(re.search(r"cmp\s+#'[qQ]'", body_ui)) and \
                        bool(re.search(r'show_welcome', body_ui))
        if q_to_welcome:
            print(f"  [OK]   UX: Q in main loop returns to welcome screen")
            ux_ok += 1
        else:
            errors.append(
                f"UX: Q in ui_main_loop does not return to welcome ({fname_ui}:{line_ui})")

    # UX-3: render_page_pause Q key must set page_abort and return C=1
    fname_rpp, line_rpp, body_rpp = get_proc(files, 'render_page_pause')
    if body_rpp:
        has_q_check = bool(re.search(r"cmp\s+#'[qQ]'", body_rpp))
        has_sec = bool(re.search(r'\bsec\b', body_rpp))
        if has_q_check and has_sec:
            print(f"  [OK]   UX: More prompt handles Q key (abort + C=1)")
            ux_ok += 1
        elif has_q_check:
            warnings.append(f"UX: render_page_pause has Q check but may not set C=1")
        else:
            errors.append(
                f"UX: render_page_pause has no Q key handler ({fname_rpp}:{line_rpp})\n"
                f"         User cannot quit during page rendering.")

    # UX-4: render_page_pause must handle H (skip to heading)
    if body_rpp:
        has_h_check = bool(re.search(r"cmp\s+#'[hH]'", body_rpp))
        has_skip_heading = bool(re.search(r'skip_to_heading', body_rpp))
        if has_h_check and has_skip_heading:
            print(f"  [OK]   UX: More prompt handles H key (skip to heading)")
            ux_ok += 1
        else:
            errors.append(
                f"UX: render_page_pause missing H key handler ({fname_rpp}:{line_rpp})\n"
                f"         Long pages need heading skip for navigation.")

    # UX-5: page_abort path must distinguish Q (quit) from link click
    if body_hn:
        has_pending_guard = bool(re.search(
            r'page_abort.*pending_link.*show_welcome', body_hn, re.DOTALL))
        if not has_pending_guard:
            has_pending_guard = bool(re.search(
                r'pending_link.*\$(FF|ff).*show_welcome', body_hn, re.DOTALL))
        if has_pending_guard:
            print(f"  [OK]   UX: page_abort path checks pending_link before welcome")
            ux_ok += 1
        else:
            errors.append(
                f"UX: http_navigate page_abort path doesn't check pending_link\n"
                f"         BUG: render_page_pause returns C=1 for both Q and link click.\n"
                f"         Both cause page_abort=1. Without checking pending_link,\n"
                f"         clicking a link during --More-- goes to welcome screen!\n"
                f"         FIX: Before show_welcome, check 'lda pending_link / cmp #$FF'.\n"
                f"         If pending_link != $FF, it's a link click -- skip show_welcome.")

    # UX-6: http_navigate must check pb_total==0 after successful download
    if body_hn:
        has_pb_check = bool(re.search(
            r'pb_total.*http_render', body_hn, re.DOTALL))
        if not has_pb_check:
            has_pb_check = bool(re.search(
                r'pb_total.*ora.*pb_total', body_hn, re.DOTALL))
        if has_pb_check:
            print(f"  [OK]   UX: http_navigate checks pb_total before rendering")
            ux_ok += 1
        else:
            errors.append(
                f"UX: http_navigate doesn't check for empty response\n"
                f"         BUG: If http_download succeeds (C=0) but pb_total=0,\n"
                f"         http_render renders empty buffer -- blank screen, no feedback.\n"
                f"         FIX: After http_download, check 'lda pb_total / ora pb_total+1 / ora pb_total+2'.\n"
                f"         If zero, show error like 'No data received' via ui_show_error.")

    # UX-7: http_apply_proxy must NOT be called before http_check_img_ext
    if body_hn:
        pos_proxy = body_hn.find('http_apply_proxy')
        pos_imgchk = body_hn.find('http_check_img_ext')
        if pos_proxy >= 0 and pos_imgchk >= 0:
            if pos_proxy < pos_imgchk:
                errors.append(
                    f"UX: http_apply_proxy called BEFORE http_check_img_ext ({fname_hn}:{line_hn})\n"
                    f"         BUG: Proxy wraps URL before image detection.\n"
                    f"         Image URL gets double-wrapped: proxy.php?url=vbxe.php?url=...\n"
                    f"         FIX: Move http_apply_proxy AFTER http_check_img_ext (into HTML branch).")
            else:
                print(f"  [OK]   UX: proxy applied after image check (no double-wrap)")
                ux_ok += 1
        elif pos_proxy >= 0:
            # proxy exists but no img check — warn
            warnings.append(
                f"UX: http_apply_proxy found but http_check_img_ext missing")
        # no proxy = nothing to check

    # UX-8: deferred image fetch — render_page_pause must defer IMG during download
    # Progressive rendering runs http_render_progress inside http_download while
    # N1: is open. img_fetch_single would close N1:, destroying the download.
    # Fix: check dl_active, set img_deferred=1, let http_download fetch after close.
    if body_rpp:
        has_dl_active_check = bool(re.search(r'lda\s+dl_active', body_rpp))
        has_img_deferred = bool(re.search(r'img_deferred', body_rpp))
        has_img_fetch = bool(re.search(r'img_fetch_single', body_rpp))
        if has_img_fetch and has_dl_active_check and has_img_deferred:
            pos_guard = body_rpp.find('dl_active')
            pos_fetch = body_rpp.find('img_fetch_single')
            if pos_guard < pos_fetch:
                print(f"  [OK]   UX: IMG deferred when dl_active (N1: conflict safe)")
                ux_ok += 1
            else:
                errors.append(
                    f"UX: dl_active checked AFTER img_fetch_single ({fname_rpp}:{line_rpp})\n"
                    f"         Guard must come before fetch to defer during download.")
        elif has_img_fetch and not has_dl_active_check:
            errors.append(
                f"UX: render_page_pause calls img_fetch without dl_active check ({fname_rpp}:{line_rpp})\n"
                f"         BUG: During progressive rendering, N1: is open for page download.\n"
                f"         img_fetch_single would close N1:, destroying download connection.\n"
                f"         FIX: Check dl_active. If active, set img_deferred=1 and defer fetch.")

    # UX-9: dl_active + img_deferred lifecycle in http_download
    fname_dl, line_dl, body_dl = get_proc(files, 'http_download')
    if body_dl:
        reset_count = len(re.findall(r'sta\s+dl_active', body_dl))
        set_count = len(re.findall(r'lda\s+#1\s*\n\s*sta\s+dl_active', body_dl))
        has_deferred_check = bool(re.search(r'img_deferred', body_dl))
        has_deferred_fetch = bool(re.search(r'img_fetch_single', body_dl))
        if set_count >= 1 and reset_count >= 3 and has_deferred_check and has_deferred_fetch:
            print(f"  [OK]   UX: dl_active lifecycle + deferred img_fetch in http_download")
            ux_ok += 1
        elif set_count >= 1 and reset_count >= 3 and has_deferred_check:
            warnings.append(
                f"UX: http_download checks img_deferred but doesn't call img_fetch_single")
        elif set_count >= 1 and reset_count >= 3:
            errors.append(
                f"UX: http_download has no img_deferred handling ({fname_dl}:{line_dl})\n"
                f"         BUG: User clicks IMG during download, img_deferred is set,\n"
                f"         but http_download never fetches the image after N1: closes.\n"
                f"         FIX: After fn_close + dl_active=0, check img_deferred and call img_fetch_single.")
        elif set_count >= 1 and reset_count >= 1:
            warnings.append(
                f"UX: dl_active reset only {reset_count} time(s) in http_download -- expected 3+")
        elif set_count >= 1:
            errors.append(
                f"UX: dl_active set but never reset in http_download ({fname_dl}:{line_dl})")

    # UX-10: Progressive render must init read pointer
    if body_dl:
        has_pb_init_read = bool(re.search(r'vbxe_pb_init_read', body_dl))
        has_render_progress = bool(re.search(r'http_render_progress', body_dl))
        if has_pb_init_read and has_render_progress:
            pos_init = body_dl.find('vbxe_pb_init_read')
            pos_render = body_dl.find('http_render_progress')
            if pos_init < pos_render:
                print(f"  [OK]   UX: pb_init_read called before progressive render")
                ux_ok += 1
            else:
                errors.append(
                    f"UX: vbxe_pb_init_read called AFTER http_render_progress ({fname_dl}:{line_dl})\n"
                    f"         BUG: Read pointer not initialized -- renders from random VRAM position.")
        elif has_render_progress and not has_pb_init_read:
            errors.append(
                f"UX: http_download uses progressive render but never inits read pointer ({fname_dl}:{line_dl})\n"
                f"         FIX: Add 'jsr vbxe_pb_init_read' before first http_render_progress call.")

    # UX-11: kbd_get_line must use cursor_back, not dec zp_cursor_col
    # Direct dec zp_cursor_col wraps to 255 at col=0 → VRAM write at wrong position
    fname_kgl, line_kgl, body_kgl = get_proc(files, 'kbd_get_line')
    if body_kgl:
        has_dec_col = bool(re.search(r'dec\s+zp_cursor_col', body_kgl))
        has_cursor_back = bool(re.search(r'jsr\s+cursor_back', body_kgl))
        if has_cursor_back and not has_dec_col:
            print(f"  [OK]   UX: kbd_get_line uses cursor_back (no col=0 wrap bug)")
            ux_ok += 1
        elif has_dec_col:
            errors.append(
                f"UX: kbd_get_line uses 'dec zp_cursor_col' directly ({fname_kgl}:{line_kgl})\n"
                f"         BUG: At col=0, dec wraps to 255 → cursor/char at wrong VRAM position.\n"
                f"         FIX: Replace 'dec zp_cursor_col' with 'jsr cursor_back' which wraps\n"
                f"         to col=SCR_COLS-1 on the previous row.")
        else:
            warnings.append(
                f"UX: kbd_get_line has no cursor movement code ({fname_kgl}:{line_kgl})")

    ok_count += ux_ok

    # --- 7. URL prefix ---
    print()
    print("  --- OTHER CHECKS ---")
    fname_url, line_url, body_url, numbered_url = \
        get_proc_numbered(files, 'http_ensure_prefix')
    if body_url:
        has_lower = bool(re.search(r"cmp\s+#'n'", body_url))
        has_upper = bool(re.search(r"cmp\s+#'N'", body_url))
        if has_upper and has_lower:
            print(f"  [OK]   URL: handles both N: and n:")
            ok_count += 1
        elif has_upper:
            diag = (
                f"URL: only checks 'N' not 'n' ({fname_url}:{line_url})\n"
                f"         BUG: When user types lowercase url, first byte is 'n' not 'N'.\n"
                f"         The cmp #'N' fails, so http_ensure_prefix adds 'N:' again = double prefix.\n"
                f"         FIX: Add lowercase check: ora #$20 before cmp, or add cmp #'n' branch.\n"
            )
            url_insns = find_proc_in_listing(listing, 'http_ensure_prefix')
            if url_insns:
                diag += f"\n         CPU trace (url_buffer[0] = 'n' = $6E):\n"
                trace_insns = url_insns[:6]
                diag += cpu_trace(trace_insns,
                    regs={'A': 0x6E, 'X': 0, 'Y': 0, 'S': 0xED, 'P': 0x30},
                    scenario="url_buffer = 'n:http://...' (lowercase)")
                diag += (
                    f"\n         CMP #'N'($4E): A=$6E vs $4E -> not equal, Z=0\n"
                    f"         BNE takes branch -> falls through to ?addFull\n"
                    f"         Result: 'N:' prepended to 'n:http://...' = 'N:n:http://...' (BROKEN)\n"
                )
            errors.append(diag)
        else:
            warnings.append("URL: cannot verify N:/n: handling")

    # --- 8. Palette restore ---
    fname_pal, line_pal, body_pal, numbered_pal = \
        get_proc_numbered(files, 'vbxe_img_hide')
    if body_pal and 'setup_palette' in body_pal:
        print(f"  [OK]   PAL: img_hide calls setup_palette")
        ok_count += 1
    elif body_pal:
        restores_xdl = 'setup_xdl' in body_pal or 'xdl' in body_pal.lower()
        restores_bcb = 'setup_bcb' in body_pal or 'bcb' in body_pal.lower()
        diag = (
            f"PAL: img_hide does NOT call setup_palette ({fname_pal}:{line_pal})\n"
            f"         BUG: Image display overwrites overlay palette 1 with image colors.\n"
            f"         After hiding image, palette still has image colors = text colors wrong.\n"
            f"         Restores XDL: {'yes' if restores_xdl else 'NO'}, "
            f"Restores BCB: {'yes' if restores_bcb else 'NO'}\n"
            f"         FIX: Add 'jsr setup_palette' before memb_off in vbxe_img_hide.\n"
        )
        hide_insns = find_proc_in_listing(listing, 'vbxe_img_hide')
        if hide_insns:
            diag += f"\n         CPU trace (vbxe_img_hide execution):\n"
            diag += cpu_trace(hide_insns,
                regs={'A': 0, 'X': 0, 'Y': 0, 'S': 0xEB, 'P': 0x30},
                scenario="After image displayed, returning to text mode")
            pal_insns = find_proc_in_listing(listing, 'setup_palette')
            if pal_insns:
                pal_addr = pal_insns[0][0]
                diag += (
                    f"\n         setup_palette is at ${pal_addr:04X}\n"
                    f"         Missing: jsr setup_palette (20 {pal_addr&0xFF:02X} {pal_addr>>8:02X})\n"
                    f"         Insert BEFORE memb_off to restore text colors while MEMAC B is active.\n"
                )
        errors.append(diag)
    else:
        warnings.append("PAL: vbxe_img_hide not found")

    return ok_count, errors, warnings
