#!/usr/bin/env python3
"""Build the 256 KB BIOS image loaded by the IPL-ROM (src/peripheral/iplrom.vhd).

The IPL copies 256 KB into the ESE-RAM (CPU memory 0x680000-0x6BFFFF), from
the SD card (FAT16, SD <= 2 GB: the first file of a freshly formatted card,
whose first sector must start with "AB") or, failing that, from the SPI
flash at 0x000000 (TN9K; the original IPL used 0x040000). The core maps the image as (see CpuAdr in emsx_core.vhd):

    0x00000  64 KB  MegaSD disk driver ROM (slot 3-2), must start with "AB";
                    TN9K: with --kbasic only 32 KB, the upper half holds:
    0x08000  32 KB  Kanji BASIC (slot 3-1, pages 1-2): every Japanese MSX2+
                    SUB-ROM calls into it at boot (7A00h of its own slot)
    0x10000  32 KB  MSX2/2+ main BIOS (slot 0-0)
    0x18000  16 KB  SUB-ROM (slot 3-1)
    0x1C000  16 KB  FM-BIOS / MSX-MUSIC (slot 0-2)
    0x20000 128 KB  kanji font, JIS level 1

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
    ap.add_argument("--kanji", required=True, help="kanji font, >= 128 KB (first 128 KB used)")
    ap.add_argument("--disk", help="MegaSD driver ROM, <= 64 KB (<= 32 KB with --kbasic) (starts 'AB')")
    ap.add_argument("--kbasic", help="Kanji BASIC, 32 KB (starts 'AB'), needed by MSX2+ BIOSes")
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

    if a.kbasic:
        if disk[0x8000:] != bytes([0xff]) * 0x8000:
            sys.exit("disk: with --kbasic the disk driver must fit in 32 KB")
        disk = disk[:0x8000] + load(a.kbasic, 0x8000, "kbasic", b"AB")

    img = (disk
           + load(a.main, 0x8000, "main", b"\xf3\xc3")
           + load(a.sub, 0x4000, "sub", b"CD")
           + load(a.fm, 0x4000, "fm", b"AB")
           + load(a.kanji, 0x20000, "kanji", allow_bigger=True))
    assert len(img) == 0x40000

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    open(a.out, "wb").write(img)
    print("%s: %d bytes, sha1 %s%s" % (a.out, len(img), hashlib.sha1(img).hexdigest(),
                                       "" if a.disk else "  (no disk driver: stub)"))


if __name__ == "__main__":
    main()
