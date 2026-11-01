#!/usr/bin/env python3
"""Convert a 240x320 RGB565 BMP into a big-endian, top-down C array."""

import struct
import sys

WIDTH = 240
HEIGHT = 320
RGB565_MASKS = (0xF800, 0x07E0, 0x001F)


def load_pixels(path):
    with open(path, "rb") as f:
        data = f.read()

    if data[:2] != b"BM":
        sys.exit(f"{path}: not a BMP file")

    offset = struct.unpack_from("<I", data, 10)[0]
    width, height, _, bpp, compression = struct.unpack_from("<iiHHI", data, 18)
    masks = struct.unpack_from("<3I", data, 54)
    if (width, abs(height), bpp, compression, masks) != (WIDTH, HEIGHT, 16, 3, RGB565_MASKS):
        sys.exit(f"{path}: expected a {WIDTH}x{HEIGHT} RGB565 bitfields BMP")

    stride = WIDTH * 2
    rows = [data[offset + y * stride:offset + (y + 1) * stride] for y in range(HEIGHT)]
    if height > 0:
        rows.reverse()
    return b"".join(rows)


def main():
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} input.bmp output.h")

    pixels = load_pixels(sys.argv[1])
    swapped = bytearray(pixels)
    swapped[0::2], swapped[1::2] = pixels[1::2], pixels[0::2]

    with open(sys.argv[2], "w") as out:
        out.write(f"#define SPLASH_WIDTH {WIDTH}\n#define SPLASH_HEIGHT {HEIGHT}\n\n")
        out.write("static const u8 splash_image[] = {\n")
        for i in range(0, len(swapped), 16):
            out.write("\t" + ", ".join(f"0x{b:02x}" for b in swapped[i:i + 16]) + ",\n")
        out.write("};\n")


if __name__ == "__main__":
    main()
