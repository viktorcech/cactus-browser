"""IMG: Image display pipeline validation — GMON overlay, palette, parser state."""
import re
from .asm_utils import find_in_asm, get_proc, get_const


def check(files, ctx):
    errors = []
    warnings = []
    ok_count = 0

    print()
    print("  --- IMAGE DISPLAY CHECKS ---")

    # =========================================================================
    # IMG-1: GMON OVATT vs STEP consistency
    # =========================================================================
    fname, line, body = get_proc(files, 'vbxe_img_show_fullscreen')
    if body:
        # Find GMON entry section — look for XDLC_GMON flag
        gmon_match = re.search(r'XDLC_GMON', body)
        if gmon_match:
            gmon_section = body[gmon_match.start():]
            # Find STEP value (lda #<320 → $40)
            has_step_320 = bool(re.search(r'lda\s+#<320', gmon_section, re.IGNORECASE))
            # Find OVATT value — lda #$XX before sta MEMB_XDL in GMON section
            ovatt_match = re.search(r';\s*OVATT.*?\n\s*lda\s+#\$([0-9A-Fa-f]+)', gmon_section, re.IGNORECASE)
            if ovatt_match and has_step_320:
                ovatt_val = int(ovatt_match.group(1), 16)
                width_bits = ovatt_val & 0x03
                if width_bits == 0x01:  # NORMAL = correct for 320
                    print(f"  [OK]   IMG-1: GMON OVATT=${ovatt_val:02X} (NORMAL) matches STEP=320")
                    ok_count += 1
                elif width_bits == 0x00:
                    errors.append(
                        f"IMG-1: GMON OVATT=${ovatt_val:02X} (NARROW) but STEP=320 ({fname}:{line})\n"
                        f"         BUG: NARROW mode expects ≤256px width. STEP=320 with NARROW\n"
                        f"         causes 2× height display (every other scanline from wrong offset).\n"
                        f"         FIX: Change OVATT to $11 (palette 1 + NORMAL).")
                else:
                    warnings.append(f"IMG-1: GMON OVATT=${ovatt_val:02X} — unexpected width bits")
            elif not has_step_320:
                warnings.append(f"IMG-1: Cannot find STEP=320 in GMON section ({fname}:{line})")
            else:
                warnings.append(f"IMG-1: Cannot parse OVATT value in GMON section ({fname}:{line})")
        else:
            warnings.append(f"IMG-1: No XDLC_GMON found in vbxe_img_show_fullscreen")
    else:
        errors.append("IMG-1: vbxe_img_show_fullscreen proc not found!")

    # =========================================================================
    # IMG-2: Image XDL scanline arithmetic
    # =========================================================================
    if body:
        has_240_minus_24 = bool(re.search(r'lda\s+#240\s*-\s*24|lda\s+#216', body, re.IGNORECASE))
        has_sbc_height = bool(re.search(r'sbc\s+img_height', body, re.IGNORECASE))
        if has_240_minus_24 and has_sbc_height:
            print(f"  [OK]   IMG-2: XDL scanline calc: 240-24-img_height (correct)")
            ok_count += 1
        elif has_sbc_height:
            # Check for wrong base (like SCR_ROWS*8-24)
            wrong_base = re.search(r'lda\s+#SCR_ROWS\s*\*\s*8|lda\s+#232', body, re.IGNORECASE)
            if wrong_base:
                errors.append(
                    f"IMG-2: XDL scanline base uses SCR_ROWS*8 not 240 ({fname}:{line})\n"
                    f"         BUG: Total XDL must be exactly 240 scanlines regardless of SCR_ROWS.\n"
                    f"         FIX: Use lda #240-24 (=216).")
            else:
                warnings.append(f"IMG-2: img_height subtracted but base value unclear ({fname}:{line})")
        else:
            errors.append(
                f"IMG-2: Missing scanline arithmetic in vbxe_img_show_fullscreen ({fname}:{line})\n"
                f"         XDL needs: remaining = 240 - 24(border) - img_height")

    # =========================================================================
    # IMG-3: VBI wait before XDL change in img_hide
    # =========================================================================
    fname3, line3, body3 = get_proc(files, 'vbxe_img_hide')
    if body3:
        has_rtclok = bool(re.search(r'RTCLOK', body3))
        if has_rtclok:
            print(f"  [OK]   IMG-3: img_hide has VBI wait (RTCLOK sync) before XDL restore")
            ok_count += 1
        else:
            errors.append(
                f"IMG-3: vbxe_img_hide has no VBI wait ({fname3}:{line3})\n"
                f"         BUG: Modifying XDL mid-frame causes visible tearing.\n"
                f"         FIX: Add RTCLOK wait loop before memb_on/setup_xdl.")
    else:
        errors.append("IMG-3: vbxe_img_hide proc not found!")

    # =========================================================================
    # IMG-4: Palette skip first 8 colors
    # =========================================================================
    fname4, line4, body4 = get_proc(files, 'vbxe_img_setpal')
    if body4:
        has_csel_8 = bool(re.search(r'lda\s+#8.*\n.*sta\s+\(.*\),y|lda\s+#8\s*\n', body4, re.IGNORECASE))
        has_skip_24 = bool(re.search(r'adc\s+#24', body4, re.IGNORECASE))
        if has_csel_8 and has_skip_24:
            print(f"  [OK]   IMG-4: Palette starts at color 8, skips 24 source bytes")
            ok_count += 1
        else:
            parts = []
            if not has_csel_8:
                parts.append("CSEL not set to 8")
            if not has_skip_24:
                parts.append("source data not skipped by 24 bytes")
            errors.append(
                f"IMG-4: vbxe_img_setpal palette skip incomplete ({fname4}:{line4})\n"
                f"         BUG: {', '.join(parts)}.\n"
                f"         Text colors 0-7 will be overwritten → garbled text after image view.")
    else:
        errors.append("IMG-4: vbxe_img_setpal proc not found!")

    # =========================================================================
    # IMG-5: Header validation ranges
    # =========================================================================
    fname5, line5, body5 = get_proc(files, 'img_read_header')
    if body5:
        has_min_8 = bool(re.search(r'cmp\s+#8', body5, re.IGNORECASE))
        has_max_h = bool(re.search(r'cmp\s+#(193|209)', body5, re.IGNORECASE))
        has_width_hi = bool(re.search(r'img_hdr_w\+1|hdr_w\+1', body5, re.IGNORECASE))
        ok5 = has_min_8 and has_max_h and has_width_hi
        if ok5:
            print(f"  [OK]   IMG-5: Header validates width 8-320, height 8-208")
            ok_count += 1
        else:
            parts = []
            if not has_min_8:
                parts.append("no minimum size check (cmp #8)")
            if not has_max_h:
                parts.append("no max height check (cmp #193 or #209)")
            if not has_width_hi:
                parts.append("no width high byte check")
            errors.append(
                f"IMG-5: img_read_header validation incomplete ({fname5}:{line5})\n"
                f"         Missing: {', '.join(parts)}\n"
                f"         Without bounds check, oversized images corrupt VRAM.")
    else:
        errors.append("IMG-5: img_read_header proc not found!")

    # =========================================================================
    # IMG-6: Parser state save/restore completeness
    # =========================================================================
    fname6, line6, body6 = get_proc(files, 'render_page_pause')
    if body6:
        has_cpx_15 = bool(re.search(r'cpx\s+#15', body6, re.IGNORECASE))
        has_saved_cidx = bool(re.search(r'rpp_saved_cidx', body6))
        has_saved_rxlen = bool(re.search(r'rpp_saved_rxlen', body6))
        has_saved_quotes = bool(re.search(r'rpp_saved_quotes', body6))
        has_saved_closing = bool(re.search(r'rpp_saved_closing', body6))
        has_saved_attr = bool(re.search(r'rpp_saved_attr', body6))

        all_saved = all([has_cpx_15, has_saved_cidx, has_saved_rxlen,
                         has_saved_quotes, has_saved_closing, has_saved_attr])
        if all_saved:
            print(f"  [OK]   IMG-6: Parser state save/restore: 15 ZP + cidx + rxlen + quotes + closing + attr")
            ok_count += 1
        else:
            missing = []
            if not has_cpx_15:
                missing.append("ZP save loop (cpx #15)")
            if not has_saved_cidx:
                missing.append("chunk_idx")
            if not has_saved_rxlen:
                missing.append("zp_rx_len")
            if not has_saved_quotes:
                missing.append("in_quotes")
            if not has_saved_closing:
                missing.append("is_closing")
            if not has_saved_attr:
                missing.append("zp_cur_attr")
            errors.append(
                f"IMG-6: Parser state save incomplete in render_page_pause ({fname6}:{line6})\n"
                f"         Missing: {', '.join(missing)}\n"
                f"         BUG: img_fetch_single clobbers ZP via status_msg/SIO.\n"
                f"         After image view, parser sees garbage → raw HTML attributes as text.")
    else:
        errors.append("IMG-6: render_page_pause proc not found!")

    # =========================================================================
    # IMG-7: VRAM read rewind after image fetch
    # =========================================================================
    if body6:
        has_save_bank = bool(re.search(r'pb_rd_save_bank', body6))
        has_save_lo = bool(re.search(r'pb_rd_save_lo', body6))
        has_save_hi = bool(re.search(r'pb_rd_save_hi', body6))
        has_reread = bool(re.search(r'jsr\s+vbxe_pb_read_chunk', body6, re.IGNORECASE))

        if has_save_bank and has_save_lo and has_reread:
            print(f"  [OK]   IMG-7: VRAM rewind after image fetch (bank+lo+hi restore + re-read)")
            ok_count += 1
        else:
            missing = []
            if not has_save_bank:
                missing.append("pb_rd_save_bank restore")
            if not has_save_lo:
                missing.append("pb_rd_save_lo restore")
            if not has_save_hi:
                missing.append("pb_rd_save_hi restore")
            if not has_reread:
                missing.append("vbxe_pb_read_chunk call (re-read)")
            errors.append(
                f"IMG-7: VRAM rewind incomplete in render_page_pause ({fname6}:{line6})\n"
                f"         Missing: {', '.join(missing)}\n"
                f"         BUG: img_fetch destroys rx_buffer with pixel data.\n"
                f"         Without rewind, parser processes pixel garbage as HTML.")

    # =========================================================================
    # IMG-8: chunk_idx + zp_rx_len reset after image fetch
    # =========================================================================
    if body6:
        has_cidx_restore = bool(re.search(r'rpp_saved_cidx\s*\n\s*sta\s+chunk_idx|'
                                           r'sta\s+chunk_idx', body6))
        if has_cidx_restore:
            print(f"  [OK]   IMG-8: chunk_idx restored after image fetch (prevents garbage loop)")
            ok_count += 1
        else:
            errors.append(
                f"IMG-8: chunk_idx not restored after image fetch ({fname6}:{line6})\n"
                f"         BUG: zp_rx_len=0 alone doesn't stop html_process_chunk loop!\n"
                f"         Loop uses chunk_idx which stays at old value (e.g. 50).\n"
                f"         With rx_len=0, chunk_idx 50→255→0 = 200+ garbage bytes parsed.\n"
                f"         FIX: sta chunk_idx alongside zp_rx_len reset.")

    # =========================================================================
    # IMG-9: VRAM_IMG_BASE doesn't collide with font
    # =========================================================================
    vram_img = get_const(files, 'VRAM_IMG_BASE')
    vram_font = get_const(files, 'VRAM_FONT')
    vram_font_inv = get_const(files, 'VRAM_FONT_INV')
    if vram_img is not None and vram_font is not None:
        font_end = vram_font + 0x800
        font_inv_end = (vram_font_inv + 0x800) if vram_font_inv is not None else font_end
        highest_font = max(font_end, font_inv_end)
        if vram_img >= highest_font:
            print(f"  [OK]   IMG-9: VRAM_IMG_BASE=${vram_img:04X} above font end ${highest_font:04X}")
            ok_count += 1
        else:
            errors.append(
                f"IMG-9: VRAM_IMG_BASE=${vram_img:04X} overlaps font region!\n"
                f"         Font: ${vram_font:04X}-${font_end:04X}"
                + (f", inverse: ${vram_font_inv:04X}-${font_inv_end:04X}" if vram_font_inv else "")
                + f"\n         Image writes would corrupt font data → garbled text.")
    else:
        warnings.append("IMG-9: Cannot resolve VRAM_IMG_BASE or VRAM_FONT constants")

    # =========================================================================
    # IMG-10: Image MEMAC B write chunk wrapping
    # =========================================================================
    fname10, line10, body10 = get_proc(files, 'vbxe_img_write_chunk')
    if body10:
        has_80_check = bool(re.search(r'cmp\s+#\$80', body10, re.IGNORECASE))
        has_40_reset = bool(re.search(r'lda\s+#\$40', body10, re.IGNORECASE))
        has_bank_inc = bool(re.search(r'inc\s+img_wr_bank', body10, re.IGNORECASE))
        if has_80_check and has_40_reset and has_bank_inc:
            print(f"  [OK]   IMG-10: img_write_chunk has MEMAC B window wrapping ($80->$40 + inc bank)")
            ok_count += 1
        else:
            missing = []
            if not has_80_check:
                missing.append("cmp #$80 (high byte check)")
            if not has_40_reset:
                missing.append("lda #$40 (window reset)")
            if not has_bank_inc:
                missing.append("inc img_wr_bank")
            errors.append(
                f"IMG-10: vbxe_img_write_chunk missing MEMAC B wrapping ({fname10}:{line10})\n"
                f"         Missing: {', '.join(missing)}\n"
                f"         VBXE SPEC: When pointer reaches $8000, must reset to $4000\n"
                f"         and increment bank. Without this, writes go to RAM not VRAM.")
    else:
        errors.append("IMG-10: vbxe_img_write_chunk proc not found!")

    # =========================================================================
    # IMG-11: Converter URL has prefix AND suffix
    # =========================================================================
    fname11, line11, body11 = get_proc(files, 'img_resolve_and_build_url')
    if body11:
        has_prefix = bool(re.search(r'm_prefix', body11))
        has_suffix = bool(re.search(r'm_suffix', body11))
        # Also check that m_prefix and m_suffix exist globally
        prefix_hits = find_in_asm(files, r'^m_prefix\s')
        suffix_hits = find_in_asm(files, r'^m_suffix\s')
        if has_prefix and has_suffix and prefix_hits and suffix_hits:
            print(f"  [OK]   IMG-11: Converter URL uses m_prefix + img_src + m_suffix")
            ok_count += 1
        else:
            missing = []
            if not has_prefix:
                missing.append("m_prefix copy in proc")
            if not has_suffix:
                missing.append("m_suffix copy in proc")
            if not prefix_hits:
                missing.append("m_prefix global label")
            if not suffix_hits:
                missing.append("m_suffix global label")
            errors.append(
                f"IMG-11: Converter URL incomplete ({fname11}:{line11})\n"
                f"         Missing: {', '.join(missing)}\n"
                f"         Without suffix, converter doesn't know target dimensions.\n"
                f"         Without prefix, URL isn't routed through converter.")
    else:
        errors.append("IMG-11: img_resolve_and_build_url proc not found!")

    # =========================================================================
    # IMG-12: img_fetch_single — pixels before palette
    # =========================================================================
    fname12, line12, body12 = get_proc(files, 'img_fetch_single')
    if body12:
        pos_pixels = body12.find('img_read_pixels')
        pos_setpal = body12.find('vbxe_img_setpal')
        if pos_pixels >= 0 and pos_setpal >= 0:
            if pos_pixels < pos_setpal:
                print(f"  [OK]   IMG-12: img_fetch_single reads pixels BEFORE setting palette")
                ok_count += 1
            else:
                errors.append(
                    f"IMG-12: img_fetch_single sets palette BEFORE reading pixels ({fname12}:{line12})\n"
                    f"         BUG: Setting palette during pixel streaming changes link colors.\n"
                    f"         Text becomes unreadable during download.\n"
                    f"         FIX: Move vbxe_img_setpal after img_read_pixels + fn_close.")
        else:
            missing = []
            if pos_pixels < 0:
                missing.append("img_read_pixels call")
            if pos_setpal < 0:
                missing.append("vbxe_img_setpal call")
            errors.append(
                f"IMG-12: img_fetch_single missing calls ({fname12}:{line12})\n"
                f"         Missing: {', '.join(missing)}")
    else:
        errors.append("IMG-12: img_fetch_single proc not found!")

    # =========================================================================
    # IMG-13: Palette leftover pixel bytes not discarded
    # =========================================================================
    # img_read_palette may finish mid-rx_buffer (768th palette byte isn't last
    # byte in chunk). Remaining bytes are pixel data — must be preserved and
    # written to VRAM. Without this, first N pixels are lost → image shifts.
    fname13, line13, body13 = get_proc(files, 'img_read_palette')
    if body13 and body12:
        has_leftover_save = bool(re.search(r'img_pal_leftover', body13))
        # In img_fetch_single: vbxe_img_write_chunk must appear between
        # img_begin_write and img_read_pixels
        pos_begin = body12.find('img_begin_write')
        pos_write = body12.find('vbxe_img_write_chunk')
        pos_read = body12.find('img_read_pixels')
        has_leftover_flush = (pos_begin >= 0 and pos_write >= 0 and pos_read >= 0
                              and pos_begin < pos_write < pos_read)
        if has_leftover_save and has_leftover_flush:
            print(f"  [OK]   IMG-13: Palette leftover pixels saved and flushed to VRAM")
            ok_count += 1
        else:
            parts = []
            if not has_leftover_save:
                parts.append("img_read_palette doesn't save leftover bytes")
            if not has_leftover_flush:
                parts.append("img_fetch_single doesn't flush leftovers before img_read_pixels")
            errors.append(
                f"IMG-13: Palette/pixel boundary not handled ({fname13}:{line13})\n"
                f"         BUG: {'; '.join(parts)}.\n"
                f"         When 768th palette byte isn't last in rx_buffer, remaining\n"
                f"         bytes are pixel data. Without saving them, first N pixels are\n"
                f"         lost and entire image shifts horizontally.\n"
                f"         FIX: Save leftover count in img_read_palette, write to VRAM\n"
                f"         via vbxe_img_write_chunk before img_read_pixels.")
    elif not body13:
        errors.append("IMG-13: img_read_palette proc not found!")

    # =========================================================================
    # IMG-14: img_fetch_single saves/restores url_buffer
    # =========================================================================
    # img_resolve_and_build_url overwrites url_buffer with converter URL.
    # Without save/restore, URL bar shows converter URL after image view.
    if body12:
        has_save = bool(re.search(r'jsr\s+img_save_url', body12, re.IGNORECASE))
        has_restore = bool(re.search(r'jsr\s+img_restore_url', body12, re.IGNORECASE))
        if has_save and has_restore:
            print(f"  [OK]   IMG-14: img_fetch_single saves/restores url_buffer around image fetch")
            ok_count += 1
        else:
            missing = []
            if not has_save:
                missing.append("img_save_url call (save before overwrite)")
            if not has_restore:
                missing.append("img_restore_url call (restore after fetch)")
            errors.append(
                f"IMG-14: url_buffer not preserved in img_fetch_single ({fname12}:{line12})\n"
                f"         Missing: {', '.join(missing)}\n"
                f"         BUG: img_resolve_and_build_url overwrites url_buffer with\n"
                f"         converter URL (N:http://.../vbxe.php?url=...&w=320&h=184&iw=320).\n"
                f"         After image view, URL bar shows converter URL instead of page URL.\n"
                f"         FIX: Call img_save_url before img_resolve_and_build_url,\n"
                f"         img_restore_url before every exit (normal + all error paths).")

    return ok_count, errors, warnings
