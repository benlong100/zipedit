#!/usr/bin/env python3
"""Patch a built ZIPEDIT.SYSTEM to force the plain (no-MouseText) glyphs.

The editor picks its glyphs by asking the CPU whether it is a 65C02, which is
the right question on real hardware and the wrong one in an emulator that only
offers an Enhanced //e. So machine.S carries a marker followed by an override
byte, and this sets it -- letting the suite exercise the original-//e drawing
path on the machine we actually have.

    forceplain.py <in.SYSTEM> <out.SYSTEM>
"""
import pathlib, sys

MARKER = b"GLYPH"                      # asc, so high ASCII
MARKER = bytes(b | 0x80 for b in MARKER)

if len(sys.argv) != 3:
    sys.exit(__doc__)

src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
data = bytearray(src.read_bytes())

hits = [i for i in range(len(data) - len(MARKER)) if data[i:i + len(MARKER)] == MARKER]
if len(hits) != 1:
    sys.exit(f"expected exactly one {MARKER!r} marker, found {len(hits)}")

flag = hits[0] + len(MARKER)
if data[flag] != 0x00:
    sys.exit(f"override byte at {flag:#x} is {data[flag]:#04x}, expected 0x00")

data[flag] = 0x01
dst.write_bytes(bytes(data))
print(f"{dst}: forced plain glyphs (override byte at {flag:#x}, load address ${0x2000 + flag:04X})")
