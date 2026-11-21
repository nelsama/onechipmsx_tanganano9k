"""Convert a tb_vdp VGA dump (one line per clk21m: RRGGBB HS VS) to an image.

    python sim/dump2img.py dump.txt out.png|out.ppm

Each VGA line is 684 clocks; one MSX pixel (256 modes) is 2 clocks wide.
Writes PNG when Pillow is available, otherwise binary PPM.
"""
import sys


def load(path):
    lines, cur, hs_d = [], [], '1'
    with open(path) as f:
        for row in f:
            rgb, sync = row.split()
            hs = sync[0]
            if hs_d == '1' and hs == '0' and cur:      # HS falling edge -> new line
                lines.append(cur)
                cur = []
            hs_d = hs
            v = int(rgb, 16)
            # 6-bit channels stored in bits 21..16, 13..8, 5..0
            r, g, b = (v >> 16) & 0x3F, (v >> 8) & 0x3F, v & 0x3F
            cur.append((r * 255 // 63, g * 255 // 63, b * 255 // 63))
    if cur:
        lines.append(cur)
    return lines


def main():
    src, dst = sys.argv[1], sys.argv[2]
    lines = load(src)
    w = max(len(l) for l in lines)
    h = len(lines)
    try:
        from PIL import Image
        img = Image.new('RGB', (w, h))
        px = img.load()
        for y, l in enumerate(lines):
            for x, c in enumerate(l):
                px[x, y] = c
        img.save(dst)
    except ImportError:
        import struct
        import zlib
        raw = bytearray()
        for l in lines:
            raw.append(0)                                  # filter: none
            for c in l + [(0, 0, 0)] * (w - len(l)):
                raw += bytes(c)

        def chunk(tag, data):
            body = tag + data
            return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xFFFFFFFF)

        with open(dst, 'wb') as f:
            f.write(b'\x89PNG\r\n\x1a\n')
            f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)))
            f.write(chunk(b'IDAT', zlib.compress(bytes(raw), 9)))
            f.write(chunk(b'IEND', b''))
    print(f'{dst}: {w}x{h}')


if __name__ == '__main__':
    main()
