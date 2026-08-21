#!/usr/bin/env python3
"""Print the 40-column screen of the front Virtual ][ machine.

vii.sh's own reader composites main and aux for an 80-column //e display, so
on a 40-column screen it interleaves live text with whatever stale bytes are
sitting in the aux half. This reads main memory only, and decodes screen codes
rather than masking them -- the status row is inverse video, which lives at
$00-$3F, and masking turns all of it into blanks.
"""
import subprocess, pathlib, sys

BASES = [0x400,0x480,0x500,0x580,0x600,0x680,0x700,0x780,
         0x428,0x4A8,0x528,0x5A8,0x628,0x6A8,0x728,0x7A8,
         0x450,0x4D0,0x550,0x5D0,0x650,0x6D0,0x750,0x7D0]

def decode(x):
    if x >= 0xA0:  return chr(x - 0x80)      # normal
    if x < 0x20:   return chr(x + 0x40)      # inverse @A-Z[\]^_
    if x < 0x40:   return chr(x)             # inverse space and punctuation
    return chr(x if x >= 0x60 else x)        # flashing

vii = str(pathlib.Path(__file__).resolve().parent / "vii.sh")
print("     +" + "-" * 40 + "+")
for r, base in enumerate(BASES):
    subprocess.run([vii, "dump", hex(base), "40", "0", "/tmp/.show40"], capture_output=True)
    b = pathlib.Path("/tmp/.show40").read_bytes()
    line = "".join(decode(x) for x in b)
    line = "".join(c if 0x20 <= ord(c) < 0x7f else " " for c in line)
    print(f"  {r:2d} |{line}|")
print("     +" + "-" * 40 + "+")
