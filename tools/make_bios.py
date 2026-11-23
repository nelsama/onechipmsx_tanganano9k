#!/usr/bin/env python3
"""Build the 256 KB BIOS image loaded by the IPL-ROM (src/peripheral/iplrom.vhd).

The IPL copies 256 KB into the ESE-RAM (CPU memory 0x680000-0x6BFFFF), from
the SD card (FAT16, SD <= 2 GB: the first file of a freshly formatted card,
whose first sector must start with "AB") or, failing that, from the SPI
flash at 0x000000 (TN9K; the original IPL used 0x040000). The core maps the image as (see CpuAdr in emsx_core.vhd):

    0x00000  64 KB  MegaSD disk driver ROM (slot 3-2), must start with "AB"
    0x10000  32 KB  MSX2/2+ main BIOS (slot 0-0)
    0x18000  16 KB  SUB-ROM (slot 3-1)
    0x1C000  16 KB  FM-BIOS / MSX-MUSIC (slot 0-2)
    0x20000 128 KB  kanji font, JIS level 1 (optional; the TN9K core has no
                    kanji ROM hardware by default)
         or  32 KB  Kanji BASIC (slot 3-1, pages 1-2, TN9K): every Japanese
                    MSX2+ SUB-ROM calls it at boot (7A00h of its own slot),
                    which scrolls the MSX2+ logo

Without --kbasic the SUB-ROM is patched so that it does not call the Kanji
BASIC at boot: the 11-byte routine at SUB-ROM 2CB9h (LD IY,slot / LD IX,7A00h
/ JP CALSLT), copied to F55Eh and called through the H.NMI hook by every
MSX2+ SUB-ROM, starts with RET (C9h) instead. Without the patch or the Kanji
BASIC the boot hangs.

Without --disk a 64 KB stub with an empty "AB" header (no INIT routine) is
used: the IPL accepts the image, the BIOS skips the slot, the machine boots
to BASIC without disk access.

Use a Japanese (60 Hz) BIOS: the HDMI output only handles the NTSC timing.

Example (Panasonic FS-A1WSX ROMs):
    python tools/make_bios.py -o build/bios/OCM-BIOS.DAT \\
        --main fs-a1wsx_basic-bios2p.rom --sub fs-a1wsx_msx2psub.rom \\
        --fm fs-a1wsx_fmbasic.rom --kanji fs-a1wsx_kanjifont.rom
"""
import argparse
import hashlib
import os
import sys


def load(path, size, what, header=None, allow_bigger=False):
    data = open(path, "rb").read()
    if len(data) < size or (len(data) > size and not allow_bigger):
        sys.exit("%s: %s is %d bytes, expected %d" % (what, path, len(data), size))
    data = data[:size]
    if header is not None and data[:len(header)] != header:
        sys.exit("%s: %s does not start with %r (starts with %s)"
                 % (what, path, header, data[:4].hex(" ")))
    return data


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--main", required=True, help="main BIOS, 32 KB (starts F3 C3)")
    ap.add_argument("--sub", required=True, help="SUB-ROM, 16 KB (starts 'CD')")
    ap.add_argument("--fm", required=True, help="FM-BIOS, 16 KB (starts 'AB')")
    ap.add_argument("--kanji", help="kanji font, >= 128 KB (first 128 KB used); TN9K: not used "
                                    "(the core is built with ENABLE_KANJI = false), the area is left empty")
    ap.add_argument("--disk", help="MegaSD driver ROM, <= 64 KB (starts 'AB')")
    ap.add_argument("--kbasic", help="Kanji BASIC, 32 KB (starts 'AB'): MSX2+ logo animation; "
                                     "goes to 0x20000, not together with --kanji")
    ap.add_argument("-o", "--out", required=True)
    a = ap.parse_args()

    if a.disk:
        d = open(a.disk, "rb").read()
        if len(d) > 0x10000 or d[:2] != b"AB":
            sys.exit("disk: %s must be <= 64 KB and start with 'AB'" % a.disk)
        disk = d + b"\xff" * (0x10000 - len(d))
    else:
        # empty ROM header: "AB", INIT/STATEMENT/DEVICE/TEXT = 0
        disk = b"AB" + b"\x00" * 14 + b"\xff" * (0x10000 - 16)

    if a.kbasic and a.kanji:
        sys.exit("--kbasic and --kanji share the area at 0x20000")
    if a.kbasic:
        tail = load(a.kbasic, 0x8000, "kbasic", b"AB") + bytes([0xff]) * 0x18000
    elif a.kanji:
        tail = load(a.kanji, 0x20000, "kanji", allow_bigger=True)
    else:
        tail = bytes([0xff]) * 0x20000

    sub = load(a.sub, 0x4000, "sub", b"CD")
    if not a.kbasic:
        # every MSX2+ SUB-ROM calls the Kanji BASIC at boot (see above)
        call = bytes.fromhex("FD210000DD21007AC31C00")
        if sub[0x2CB9:0x2CB9 + 11] != call:
            sys.exit("sub: the Kanji BASIC boot call is not at 2CB9h (%s); use --kbasic"
                     % sub[0x2CB9:0x2CB9 + 11].hex(" "))
        sub = sub[:0x2CB9] + b"\xc9" + sub[0x2CBA:]
        print("SUB-ROM patched: no Kanji BASIC call at boot (2CB9h = RET)")

    img = (disk
           + load(a.main, 0x8000, "main", b"\xf3\xc3")
           + sub
           + load(a.fm, 0x4000, "fm", b"AB")
           + tail)
    assert len(img) == 0x40000

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    open(a.out, "wb").write(img)
    print("%s: %d bytes, sha1 %s%s" % (a.out, len(img), hashlib.sha1(img).hexdigest(),
                                       "" if a.disk else "  (no disk driver: stub)"))


if __name__ == "__main__":
    main()
