"""
ASM Browser Validator
Reads ASM source, fetches real HTML, simulates what lands in VRAM,
checks if Atari will display it correctly.

Uses the Atari XL OS Rev.2 ROM font layout and accounts for the
int2asc font page remapping when building the screen code -> character map.
Can also cross-check against the actual ROM font source.
"""
import os, sys

SRC_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SRC_DIR)
# ROM source can be in project dir or parent (ata-magazin level)
_rom_candidates = [
    os.path.join(PROJECT_DIR, '_samples', 'Atari_XL_OS_Rev.2.asm'),
    os.path.join(PROJECT_DIR, '_pomocne', 'A800-OS-XL-Rev2-main', 'Atari_XL_OS_Rev.2.asm'),
    os.path.join(PROJECT_DIR, '..', '_pomocne', 'A800-OS-XL-Rev2-main', 'Atari_XL_OS_Rev.2.asm'),
]
ROM_ASM_PATH = next((p for p in _rom_candidates if os.path.exists(p)), _rom_candidates[0])

from validator.asm_utils import read_asm_files, parse_listing
from validator.check_font import check as check_font
from validator.check_code import check as check_code
from validator.check_vbxe_hw import check as check_vbxe_hw
from validator.check_sio import check as check_sio
from validator.check_memac import check as check_memac
from validator.check_layout import check as check_layout
from validator.check_ux import check as check_ux
from validator.check_images import check as check_images
from validator.check_binary import check as check_binary
from validator.check_php import check as check_php


# =============================================================================
def run():
    files = read_asm_files(SRC_DIR)

    print("=" * 70)
    print("  VBXE BROWSER ASM VALIDATOR")
    print("=" * 70)

    errors = []
    warnings = []
    ok_count = 0

    # Parse listing file for CPU trace debug
    _lab_candidates = [
        os.path.join(PROJECT_DIR, 'bin', 'browser.lab'),
        os.path.join(PROJECT_DIR, 'browser.lab'),
    ]
    lab_path = next((p for p in _lab_candidates if os.path.exists(p)), _lab_candidates[0])
    listing = parse_listing(lab_path)

    # Shared context passed to all check modules
    ctx = {
        'listing': listing,
        'rom_asm_path': ROM_ASM_PATH,
        'project_dir': PROJECT_DIR,
        # These are set by check_font and used by later checks:
        'int2asc': None,
        'vbxe_sc_map': {},
        'ch_space': None,
        'has_a2s': False,
        'sub_value': 0x20,
    }

    # Run all check modules in order
    checkers = [
        check_font,
        check_code,
        check_vbxe_hw,
        check_ux,       # 6f + 7 + 8
        check_memac,     # 9 + 10g
        check_layout,    # 10h
        check_sio,       # 10f
        check_images,    # IMG: image display validation
        check_binary,    # 11 + 12
        check_php,       # PHP: server-side scripts
    ]

    for checker in checkers:
        ok, errs, warns = checker(files, ctx)
        ok_count += ok
        errors.extend(errs)
        warnings.extend(warns)

    # --- Summary ---
    print()
    print(f"  {'=' * 66}")
    for w in warnings:
        print(f"  [WARN] {w}")
    for e in errors:
        print(f"  [ERR]  {e}")
    print()
    print(f"  {ok_count} OK, {len(warnings)} warnings, {len(errors)} errors")
    if errors:
        print(f"\n  !! BUGS FOUND - FIX BEFORE RUNNING ON ATARI !!")
    else:
        print(f"\n  ALL CHECKS PASSED")
    print(f"  {'=' * 66}")

    return len(errors) == 0


if __name__ == '__main__':
    sys.exit(0 if run() else 1)
