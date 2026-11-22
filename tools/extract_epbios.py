#!/usr/bin/env python3
"""Extract the ROMs of the built-in BIOS (EPBIOS) of a 1chipMSX firmware image.

The OCM-PLD packs by KdL (https://gnogni.altervista.org) ship, for every
machine, an "emsx_top.pld": the whole 512 KB EPCS of the 1chipMSX (FPGA
configuration + EPBIOS), with every byte bit-reversed (Altera .rpd order).
In OCM-PLD v3.9.2 (single_epbios_msx2plus_*) the EPBIOS is laid out as:

    0x34000  64 KB  disk ROM: MegaSD driver + MSX-DOS 2.31 kernel + Disk BASIC
    0x44000  32 KB  MSX2+ main BIOS
    0x4C000  16 KB  BASIC'n (MSX-BASIC compiler)
    0x50000  16 KB  FM-BIOS (MSX-MUSIC)
    0x54000  16 KB  MSX2+ SUB-ROM
    0x58000  32 KB  Kanji driver / Kanji BASIC
    0x60000 128 KB  kanji font

The headers of every part are checked. Output: one .rom file per part, ready
for tools/make_bios.py:

    python tools/extract_epbios.py <emsx_top.pld> <outdir>
    python tools/make_bios.py -o build/bios/OCM-BIOS.DAT --disk <outdir>/disk.rom \\
        --main <outdir>/main.rom --sub <outdir>/sub.rom --fm <outdir>/fm.rom
"""
import os
import sys

PARTS = [
    # name, offset, size, header
    ("disk",   0x34000, 0x10000, b"AB"),
    ("main",   0x44000, 0x08000, b"\xf3\xc3"),
    ("basicn", 0x4C000, 0x04000, b"AB"),
    ("fm",     0x50000, 0x04000, b"AB"),
    ("sub",    0x54000, 0x04000, b"CD"),
    ("kanjibasic", 0x58000, 0x08000, b"AB"),
    ("kanjifont",  0x60000, 0x20000, None),
]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    raw = open(sys.argv[1], "rb").read()
    if len(raw) != 0x80000:
        sys.exit("expected a 512 KB EPCS image, got %d bytes" % len(raw))
    rev = bytes(int("{:08b}".format(b)[::-1], 2) for b in range(256))
    img = raw.translate(rev)
    os.makedirs(sys.argv[2], exist_ok=True)
    for name, off, size, hdr in PARTS:
        data = img[off:off + size]
        if hdr is not None and data[:len(hdr)] != hdr:
            sys.exit("%s at 0x%05X does not start with %r (%s): not the expected layout"
                     % (name, off, hdr, data[:4].hex(" ")))
        path = os.path.join(sys.argv[2], name + ".rom")
        open(path, "wb").write(data)
        print("%-11s 0x%05X %6d bytes -> %s" % (name, off, size, path))


if __name__ == "__main__":
    main()
