#!/usr/bin/env python3
"""Check that no two dum blocks overlap.

    tools/dumcheck.py [directory]

Merlin will not catch this: a dum block declares addresses without emitting
anything, so two of them can quietly claim the same bytes and the only sign
is a variable that changes when nothing touched it. That is a bad afternoon,
so the build asks this question every time.

ONE DIRECTORY AT A TIME, because the tree holds two programs. The editor's
blocks and the compiler's may sit at the same addresses quite safely -- they
never run together -- so checking them as one set would report overlaps that
are not, and the real ones would be lost among them. That is not a
hypothetical: the compiler's own blocks were NOT being checked at all, having
been put in a subdirectory the glob did not reach, and two of them landed on
top of each other. The symptom was a filename that read CS300.
"""
import re, sys, glob, os

def equates(where):
    """ds sizes are often named. Resolve the simple ones from the source."""
    out = {}
    for path in glob.glob(os.path.join(where, "*.S")):
        for line in open(path):
            # A TRAILING COMMENT still leaves an equate. Requiring the end of
            # the line meant SCRW, which has one, resolved to nothing -- and
            # the blocks sized from it were never actually checked.
            m = re.match(r"(\S+)\s+equ\s+(\$?[0-9a-fA-F]+)\s*(;.*)?$", line.rstrip())
            if m:
                txt = m.group(2)
                base = 16 if txt.startswith("$") else 10
                txt = txt.lstrip("$")
                try:
                    out[m.group(1)] = int(txt, base)
                except ValueError:
                    pass
    return out

def size(text, names):
    """A ds operand: a number, a name, or a product of the two.

    A block sized VMAX*2 was resolving to zero, so its end came out BELOW its
    start and it overlapped nothing at all -- the check quietly passed on a
    block it had not looked at. Anything not understood now says so rather
    than counting as empty.
    """
    total = 1
    for part in text.split("*"):
        part = part.strip()
        if part.isdigit():
            total *= int(part)
        elif part in names:
            total *= names[part]
        else:
            print(f"dumcheck: cannot size '{text}'", file=sys.stderr)
            return 0
    return total


def main():
    root = os.path.join(os.path.dirname(__file__), "..")
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    where = os.path.join(root, args[0] if args else "src")
    SIZES = equates(where)
    spans = []
    for path in sorted(glob.glob(os.path.join(where, "*.S"))):
        addr = None
        items = []
        for i, line in enumerate(open(path), 1):
            m = re.match(r"\s+dum\s+\$([0-9a-fA-F]+)", line)
            if m:
                addr = int(m.group(1), 16); items = []; start = addr; ln = i
                continue
            if addr is not None and re.match(r"\s+dend", line):
                if items:
                    spans.append((start, addr - 1, os.path.basename(path), ln, items[0]))
                addr = None
                continue
            if addr is None:
                continue
            m = re.match(r"(\S*)\s+ds\s+(\S+)", line)
            if m:
                items.append(m.group(1) or "?")
                addr += size(m.group(2), SIZES)

    spans.sort()
    bad = 0
    for i, (s, e, f, ln, first) in enumerate(spans):
        for (s2, e2, f2, ln2, first2) in spans[i+1:]:
            if s2 <= e:
                print(f"OVERLAP: ${s:04x}-${e:04x} {first} ({f}:{ln})"
                      f"  and  ${s2:04x}-${e2:04x} {first2} ({f2}:{ln2})")
                bad += 1

    # AND NOT INTO PRODOS. Comparing the blocks with each other says nothing
    # about whether one of them has climbed into the global page at $BF00,
    # which is where the MLI keeps its vectors and where a SYS program's own
    # memory stops. A block moved to make room for a bigger table did exactly
    # that: six buffers added up to 1,184 bytes where the comment beside them
    # said four and 848, and the last of them ran 160 bytes past the top.
    #
    # It does not fail like a memory bug. The MLI comes back wrong from the
    # next call and the compiler executes whatever it lands in -- which was
    # its own message table.
    PRODOS = 0xBF00
    for s, e, f, ln, first in spans:
        if e >= PRODOS:
            print(f"INTO PRODOS: ${s:04x}-${e:04x} {first} ({f}:{ln})"
                  f" -- the global page at ${PRODOS:04x} is not yours")
            bad += 1
    if bad:
        return 1
    if "-v" in sys.argv:
        for s, e, f, ln, first in spans:
            print(f"${s:04x}-${e:04x}  {first:<12} {f}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
