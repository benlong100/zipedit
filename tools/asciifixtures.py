#!/usr/bin/env python3
"""Write text files in every line-ending and ASCII convention onto an image.

These are generated rather than committed on purpose. A file whose whole point
is that it ends its lines with CRLF, or that its bytes are high ASCII, is
exactly the file a checkout can quietly normalise -- and then the test passes
because the fixture stopped being what it was testing.

    asciifixtures.py <image.po>
"""
import pathlib, subprocess, sys, tempfile

if len(sys.argv) != 2:
    sys.exit(__doc__)
image = sys.argv[1]
ac = str(pathlib.Path(__file__).resolve().parent / "ac")

BODY = "Line one of the file.{eol}Line two of the file.{eol}"

files = {
    # a .txt from a Mac or anything Unix: low ASCII, LF endings
    "LFONLY.TXT":  BODY.format(eol="\n").encode("ascii"),
    # from a PC: low ASCII, CRLF. The LF must not add a second break.
    "CRLFTXT.TXT": BODY.format(eol="\r\n").encode("ascii"),
    # the Apple II convention this editor writes: high ASCII, CR
    "HIGHCR.TXT":  bytes((ord(c) | 0x80) & 0xFF
                         for c in BODY.format(eol="\r")),
    # tabs and control bytes that would otherwise read as line breaks
    "TABS.TXT":    b"Tabs:\there\tand\there.\n\x00\x0cAfter the junk.\n",
    # A paragraph longer than 255 characters, unwrapped, exactly as a Mac
    # Markdown file has them. CCOL is one byte, so walking back over a line
    # this long used to wrap the count and make WRAPALL break the line at its
    # FIRST character.
    "LONGLINE.TXT": (b"**Bold** " + b"alpha bravo charlie delta echo foxtrot "
                     * 9 + b"\nsecond line.\n"),
}

for name, data in files.items():
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(data); tmp = f.name
    subprocess.run([ac, "-d", image, name], capture_output=True)
    with open(tmp, "rb") as fh:
        subprocess.run([ac, "-p", image, name, "TXT"], stdin=fh, check=True)
    pathlib.Path(tmp).unlink()
print(f"ascii fixtures written to {image}")
