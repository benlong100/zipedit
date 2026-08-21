#!/usr/bin/env python3
"""genhelp.py -- generate the help screen rows in src/help.S.

The help box is raw //e screen codes, because MouseText cannot come out of
`asc`. Hand-encoding 42 rows of hex is how the one-page version ended up with a
description butted against the border and two columns touching, so the layout
lives here as text and the hex is generated from it.

    tools/genhelp.py --preview    look at the pages
    tools/genhelp.py              emit the tables for src/help.S

Column stops are enforced: a description that would overrun the border is an
assertion failure here rather than a mangled row on the machine.
"""
W = 62            # interior width, between the two verticals
LH, LK, LD = 1, 3, 16     # left header / key / description columns
RH, RK, RD = 32, 34, 43   # right header / key / description columns

def row(cells, width=None):
    """cells: list of (col, text) placed into a blank interior line.

    Two things can go wrong with a cell and only one of them used to be
    caught. Running past the border was an assertion; running into the NEXT
    COLUMN was not -- the slice simply overwrote whatever was there, and since
    page() lays the left column down before the right, an over-long left
    description was silently truncated by the right column landing on top of
    it. Nothing failed, and the mangled row only showed up on the machine.

    English descriptions never grew long enough to reach column 32. Italian
    ones do, which is how this surfaced -- reported from a translation, not
    from the layout it was written for.

    So check what actually matters: no two cells may overlap. That covers a
    description reaching the next column, a key reaching its own description,
    and any column stop added later.
    """
    W_ = W if width is None else width
    buf = [" "] * W_
    placed = []                       # (start, end, text) already laid down
    for col, text in cells:
        end = col + len(text)
        assert end <= W_, (
            f"overflows the border: {text!r} at column {col} would reach {end}, "
            f"and the interior is {W_} wide")
        for start, stop, other in placed:
            if col < stop and start < end:
                raise AssertionError(
                    f"columns collide: {text!r} at {col}-{end} runs into "
                    f"{other!r} at {start}-{stop}")
        placed.append((col, end, text))
        buf[col:end] = list(text)
    return "".join(buf)

def entry(key, desc, side):
    k, d = (LK, LD) if side == "L" else (RK, RD)
    return [(k, key), (d, desc)]

def header(text, side):
    return [((LH if side == "L" else RH), text)]

# Each page is a list of interior lines, laid out so section headers on the
# two columns land on the same rows.
def page(left, right):
    lines = []
    for i in range(max(len(left), len(right))):
        cells = []
        if i < len(left) and left[i]:   cells += left[i]
        if i < len(right) and right[i]: cells += right[i]
        lines.append(row(cells))
    return lines

P1L = [header("MOVING", "L"),
       entry("arrows",   "char / line",     "L"),
       entry("@-arrows", "word / page",     "L"),
       entry("Ctrl-A",   "line start",      "L"),
       entry("Ctrl-E",   "line end",        "L"),
       entry("@-<  @->", "doc start/end",   "L"),
       None,
       header("SELECTING", "L"),
       entry("@-space",  "start selecting", "L"),
       entry("arrows",   "paint",           "L"),
       entry("Esc",      "cancel",          "L")]
P1R = [header("EDITING", "R"),
       entry("Delete", "delete left",        "R"),
       entry("Ctrl-D", "delete right",       "R"),
       entry("Ctrl-Y", "delete to line end", "R"),
       entry("Tab",    "indent two spaces",  "R"),
       entry("@-R",      "reflow paragraph", "R"),
       entry("@-Delete", "delete word left", "R")]

P2L = [header("MARKDOWN", "L"),
       entry("Ctrl-B", "**bold** word", "L"),
       entry("Ctrl-I", "*italic* word", "L"),
       None,
       None,                        # SEARCH gained a row; keep the headers level
       header("CLIPBOARD", "L"),
       entry("@-C", "copy",  "L"),
       entry("@-X", "cut",   "L"),
       entry("@-V", "paste", "L")]
P2R = [header("SEARCH", "R"),
       entry("@-F @-G",  "find / again", "R"),
       entry("@-L",      "go to line",   "R"),
       entry("@-W",      "word count",   "R"),
       None,
       header("FILES", "R"),
       entry("@-N", "new",  "R"),
       entry("@-O", "open", "R"),
       entry("@-S", "save",    "R"),
       entry("@-A", "save as", "R"),
       entry("@-Q", "quit", "R"),
       None,
       header("SCREEN", "R"),
       entry("@-/", "cheat sheet", "R"),
       entry("@-?", "this help",   "R")]

TITLE  = "MARKDOWN EDITOR FOR THE APPLE //e  --  KEYBOARD COMMANDS"
FOOT1  = "press any key for more   --   page 1 of 2"
FOOT2  = "press any key to return   --   page 2 of 2"

def centre(t):
    return row([((W - len(t)) // 2, t)])

def build(content, foot):
    # Every rule is $4C. $5C is NOT a second rule at a different height -- it
    # draws TWO strokes, one at the top of its cell and one at the bottom, so a
    # row of it renders as a double line. That is what put a stray line across
    # the top of the screen and, once that row was removed, two lines under the
    # title. $4C draws a single stroke at the TOP of its cell, so a rule row
    # sits hard against the row above it and the verticals descend from it.
    #
    # The bottom rule is 63 cells, not 64: $5F draws its vertical at the LEFT
    # edge of its cell, so a 64-cell rule runs a whole cell past the corner.
    # The top edge keeps a vertical in its corner cell so the left border runs
    # unbroken from the very top; the rule beside it stops one cell short, and
    # nothing in MouseText closes that notch -- $58 is a literal bracket whose
    # strokes are inset, so it joins nothing. The rule UNDER the title does
    # start at the corner cell, because the title row above already carries the
    # vertical there and the rule then meets it squarely.
    #
    # A rule row otherwise starts at the CORNER cell, not one in from it. $5F draws its
    # vertical at the left edge of its cell, so a rule beginning one cell in
    # starts a whole cell to the right of the vertical and never reaches it --
    # the same reason the bottom rule already starts there and reads correctly.
    # The right-hand end is the mirror case: the vertical occupies the corner
    # cell and the rule stops against its left edge.
    out  = ["|" + "=" * 62 + "|"]           # 0  top edge
    out += ["|" + centre(TITLE) + "|"]      # 1  title
    out += ["=" * 63 + "|"]                 # 2  rule under the title
    body = [""] + content                   # 3  blank, then the content rows
    body += [""] * (16 - len(body))         # pad out to row 18
    out += ["|" + row([(0, b)]) + "|" for b in body]
    out += ["|" + centre(foot) + "|"]       # 19 footer
    out += ["=" * 63]                       # 20 bottom edge
    assert len(out) == 21, (
        f"a page is 21 rows: title, a blank, up to 18 of content, and a footer. "
        f"This one came to {len(out)}.")
    return out

def encode(line):
    m = {"|": 0x5F, "~": 0x5C, "=": 0x4C, "@": 0x41}
    return bytes(m.get(c, ord(c) + 0x80) for c in line)

pages = [build(page(P1L, P1R), FOOT1), build(page(P2L, P2R), FOOT2)]

def tables():
    out = []
    for pi, p in enumerate(pages, 1):
        out.append(f"HELPTBL{pi}")
        out += [f"             da    H{pi}{i:02d}" for i in range(21)]
        out.append("")
    for pi, p in enumerate(pages, 1):
        for i, line in enumerate(p):
            b = encode(line)
            assert len(b) in (63, 64), (pi, i, len(b))
            out.append(f"H{pi}{i:02d}")
            out.append("             hex   " + b[:32].hex().upper())
            out.append("             hex   " + b[32:].hex().upper())
            out.append("             dfb   $00")
    return "\n".join(out) + "\n"


#--------------------------------------------------------------------------
# The 40 column help, for the Apple ][+
#
# Not the 80 column screen made narrower. Three things force a different
# document rather than a different width:
#
#   no box      the border is MouseText, which a ][+ does not have. Folded to
#               the nearest thing it can draw, it comes out as rows of letters
#   one column  two columns of key-and-description do not fit in 40
#   other keys  this machine has no Open-Apple, so every command behind it is
#               named differently. A help screen describing keys the reader
#               does not have is worse than no help screen
#
# Capitals throughout because the character generator has nothing else, and
# writing them here keeps the source honest about the machine.
#--------------------------------------------------------------------------
W40 = 40
K40, D40 = 2, 14          # key column, description column

def e40(key, desc):
    return [(K40, key), (D40, desc)]

def h40(text):
    return [(0, text)]

P1_40 = [
    h40("MOVING"),
    e40("arrows", "char left/right"),
    e40("ctrl-j k", "line up/down"),
    e40("ctrl-a e", "line start/end"),
    e40("esc + key", "word or page"),
    e40("esc < >", "top/end of doc"),
    None,
    h40("EDITING"),
    e40("ctrl-z", "delete left"),
    e40("ctrl-d", "delete right"),
    e40("ctrl-y", "to end of line"),
    e40("esc z", "delete word"),
    e40("ctrl-b i", "bold / italic"),
    e40("tab", "indent"),
    e40("ctrl-r", "reflow para"),
    h40("SELECTING"),
    e40("ctrl-t", "start, arrows paint"),
    e40("esc", "cancel"),
]

P2_40 = [
    h40("CLIPBOARD"),
    e40("ctrl-c", "copy"),
    e40("ctrl-x", "cut"),
    e40("ctrl-v", "paste"),
    None,
    h40("FILES"),
    e40("ctrl-s", "save"),
    e40("esc a", "save as"),
    e40("ctrl-o", "open"),
    e40("ctrl-n", "new"),
    e40("ctrl-q", "quit"),
    None,
    h40("SEARCH"),
    e40("ctrl-f", "find"),
    e40("ctrl-g", "find again"),
    e40("ctrl-l", "go to line"),
    e40("ctrl-w", "word count"),
    e40("ctrl-p", "this help, or esc ?"),
]

TITLE40 = "zipedit -- commands"
F1_40   = "any key for more    1 of 2"
F2_40   = "any key to return   2 of 2"

def centre40(t):
    return row([((W40 - len(t)) // 2, t)], W40)

def build40(content, foot):
    out = [centre40(TITLE40), row([], W40)]
    for line in content:
        out.append(row(line or [], W40))
    while len(out) < 20:
        out.append(row([], W40))
    out.append(centre40(foot))
    assert len(out) == 21, (
        f"a page is 21 rows: title, a blank, up to 18 of content, and a footer. "
        f"This one came to {len(out)}.")
    return out

def encode40(line):
    return bytes(ord(c) + 0x80 for c in line)

def tables40():
    pages = [build40(P1_40, F1_40), build40(P2_40, F2_40)]
    out = []
    for pi, _ in enumerate(pages, 1):
        out.append(f"HELPTBL{pi}")
        out += [f"             da    H{pi}{i:02d}" for i in range(21)]
        out.append("")
    for pi, p in enumerate(pages, 1):
        for i, line in enumerate(p):
            b = encode40(line)
            assert len(b) == 40, (pi, i, len(b))
            out.append(f"H{pi}{i:02d}")
            out.append("             hex   " + b[:20].hex().upper())
            out.append("             hex   " + b[20:].hex().upper())
            out.append("             dfb   $00")
    return "\n".join(out) + "\n"

import sys, pathlib

# --check <file>: is the generated table in that file the one this layout
# produces? src/help.S is generated but committed, so it can fall behind the
# layout silently -- which is exactly what happened to the OA-Delete row: it
# was added here, help.S was never regenerated, and every build after that
# shipped a help screen with a blank line where the command should have been.
if "--check" in sys.argv:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        sys.exit("usage: genhelp.py --check [--40] <file>")
    target = pathlib.Path(args[0])
    want = tables40() if "--40" in sys.argv else tables()
    text = target.read_text()
    marker = "*--- generated below this line: tools/genhelp.py\n"
    if marker not in text:
        sys.exit(f"{target}: no generated-content marker")
    have = text.split(marker, 1)[1]
    if [l.rstrip() for l in have.splitlines()] == [l.rstrip() for l in want.splitlines()]:
        print(f"{target} matches the layout")
        sys.exit(0)
    sys.exit(f"{target} is out of date -- regenerate it with:\n"
             f"    python3 tools/genhelp.py {'--40 ' if '--40' in sys.argv else ''}")

if "--40" in sys.argv:
    print(tables40(), end="")
    sys.exit(0)

if "--preview" in sys.argv:
    for n, p in enumerate(pages, 1):
        print(f"--- page {n} ---")
        for r in p: print(r)
else:
    print(tables(), end="")
