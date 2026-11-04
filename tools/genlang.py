#!/usr/bin/env python3
"""Turn a language file into the assembly the editor is built from.

    tools/genlang.py lang/sl.txt > src/lang_sl.S

The point is that a translator writes real Slovenian -- "Poišči: " -- and
never sees the assembler, the high bit, or the fact that this machine has no
letter š. The transliteration below is the whole reason this tool exists:
writing `Poi{~i` into a .S file by hand is how a translation acquires typos
nobody can see.

WHY THE LETTERS MOVE

The Apple //e's character generator is a ROM with 96 printable glyphs and no
carons among them, and it cannot be changed from software. Slovenian needs six
more letters than there are codes, so six ASCII characters are given up --
which is what YUSCII, the Yugoslav ISO 646 variant, did in the first place.

We follow YUSCII exactly, all ten letters, because Slovenian Apple IIs really
were built with it: a Yugoslav //e or //c has a character ROM that draws [ as
Š and a keyboard whose Š key sends [. A file written this way is plain YUSCII
text, which any YUSCII tool can read -- not only tools/xfer.sh.

    letter  code    letter  code
    Ž       @       ž       `
    Š       [       š       {
    Č       ^       č       ~
    Ć       ]       ć       }
    Đ       \\       đ       |

Slovenian itself uses six; Ć and Đ are there for names, Đoković among them.

So in a YUSCII language those ten codes are letters, and Markdown's [ and `
are not available: no links, checkboxes or code spans. Bold, italic, headings,
lists and quotes do not use them and all still work. A string here that
contains one of the ten characters literally would show as a letter on the
machine, so it is refused.

1.4 moved Š and ž off YUSCII to keep Markdown's characters, and a 1.5 beta
moved Markdown's into the Đ/đ slots instead. Janez Starc, who writes on a
YUSCII //e and //c and moves files without our script, showed that both made
files that were neither proper YUSCII nor proper Markdown anywhere else.
"""
import pathlib, re, sys

# what the editor stores, before bit 7 is set
XLAT = {"Ž": "@", "Š": "[", "Č": "^", "Ć": "]", "Đ": "\\",
        "ž": "`", "š": "{", "č": "~", "ć": "}", "đ": "|"}

# Languages written in YUSCII, where the ten codes above are letters.
YUSCII = {"sl"}
YCODES = set(XLAT.values())

# Fields written over the status row at fixed columns from src/geom.S. A label
# that runs long does not push the next one along, it overwrites it -- so the
# generator checks the total width rather than trusting the translator to.
WIDTHS = {"STATTXT": 80, "STATTXT40": 40}

TOKENS = {"{OA}": 0x41}          # the Open Apple glyph, from MouseText

# The placeholder name is drawn into a field 15 cells wide whose LAST cell
# carries the unsaved-changes star, so fourteen characters is the real limit --
# and it becomes a genuine ProDOS filename the moment the writer saves without
# naming the document, so ProDOS's own rules apply on top of that.
NAMEMAX = 14

def parse(path):
    entries, order = {}, []
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        # HELP "english" = "translation" belongs to tools/genhelp.py, which
        # draws the keyboard help. It lives in the same file so a language is
        # one file, and is skipped here.
        if line.lstrip().startswith("HELP "):
            continue
        m = re.match(r'^(\w+)\s*=\s*"(.*)"\s*$', line)
        if not m:
            sys.exit(f"{path}:{n}: expected  KEY = \"text\"\n  got: {line}")
        key, val = m.group(1), m.group(2)
        if key in entries:
            sys.exit(f"{path}:{n}: {key} is defined twice")
        entries[key] = val
        order.append(key)
    return entries, order

def encode(text, key, path):
    """The string as a list of ('asc', str) and ('dfb', int) pieces."""
    if path.stem in YUSCII:
        bare = text
        for tok in TOKENS:                # {OA} is a glyph, not two braces
            bare = bare.replace(tok, "")
        clash = sorted(set(bare) & YCODES)
        if clash:
            sys.exit(f"{path}: {key} contains {' '.join(clash)}, which this "
                     f"language's machines draw as a letter. Write the letter, "
                     f"or leave the character out.")
    out, buf = [], ""
    i = 0
    while i < len(text):
        for tok, code in TOKENS.items():
            if text.startswith(tok, i):
                if buf:
                    out.append(("asc", buf)); buf = ""
                out.append(("dfb", code))
                i += len(tok)
                break
        else:
            ch = text[i]
            if ch in XLAT:
                ch = XLAT[ch]
            if ch == '"':
                sys.exit(f'{path}: {key} contains a double quote, which the '
                         f'assembler uses to delimit the string')
            if not (0x20 <= ord(ch) <= 0x7e):
                sys.exit(f"{path}: {key} contains {ch!r}, which this machine "
                         f"has no glyph for. Add it to XLAT if it has a home.")
            buf += ch
            i += 1
    if buf:
        out.append(("asc", buf))
    return out

def width(pieces):
    return sum(len(p[1]) if p[0] == "asc" else 1 for p in pieces)

def main(argv):
    if len(argv) != 2:
        sys.exit("usage: genlang.py lang/<code>.txt")
    path = pathlib.Path(argv[1])
    entries, order = parse(path)

    ref = pathlib.Path("lang/en.txt")
    if ref.exists() and ref != path:
        want, _ = parse(ref)
        missing = [k for k in want if k not in entries]
        extra = [k for k in entries if k not in want]
        if missing:
            sys.exit(f"{path}: missing {', '.join(missing)} -- every string in "
                     f"lang/en.txt needs one here, or the editor jumps into "
                     f"whatever follows the gap")
        if extra:
            sys.exit(f"{path}: {', '.join(extra)} is not a string the editor "
                     f"uses; a typo in a name assembles fine and never shows")

    # UNTITLED is the one string with rules beyond its width, and it is easy to
    # break from a language file: the first Slovenian draft was BREZIMNO.MD,
    # which is eleven characters like UNTITLED.MD, so the hard-coded length in
    # equates.S went on being right by coincidence. It is emitted below now,
    # but the name still has to be a name.
    name = entries.get("UNTITLED", "")
    if len(name) > NAMEMAX:
        sys.exit(f"{path}: UNTITLED is {len(name)} characters and the status "
                 f"row gives it {NAMEMAX}, because the cell after it carries "
                 f"the unsaved-changes star.")
    if not name[:1].isascii() or not name[:1].isalpha():
        sys.exit(f"{path}: UNTITLED must start with a letter -- it becomes a "
                 f"real ProDOS filename if the writer saves without naming "
                 f"the document.")
    bad = [c for c in name if not (c.isascii() and (c.isalnum() or c == "."))]
    if bad:
        sys.exit(f"{path}: UNTITLED contains {''.join(sorted(set(bad)))!r}. "
                 f"ProDOS keeps letters, digits and full stops and nothing "
                 f"else, and the disk is read by other programs.")

    # THE TWO KEYS THE GUARD OFFERS. These are read by the program rather than
    # printed, so the ways they go wrong are silent ones: the comparison folds
    # case with AND #$DF, so a lowercase letter here produces a key that can
    # never match, and a letter the prompt does not name produces a prompt
    # offering one key while the editor listens for another. Both build
    # perfectly and both are only findable by pressing the key.
    for key in ("KEYSAVE", "KEYDISCARD"):
        k = entries.get(key, "")
        if len(k) != 1 or not k.isascii() or not k.isalpha():
            sys.exit(f"{path}: {key} must be a single ASCII letter, and is "
                     f"{k!r}. It is a key the writer presses, not a word.")
        if not k.isupper():
            sys.exit(f"{path}: {key} is {k!r} and must be a capital. The "
                     f"comparison folds case with AND #$DF before it gets "
                     f"here, so a lowercase letter never matches anything.")
        for named in ("MSGUNSAVED", "MSGUNSV40"):
            if k not in entries.get(named, ""):
                sys.exit(f"{path}: {key} is {k!r}, which {named} never names. "
                         f"The prompt would offer one key while the editor "
                         f"listened for another:\n  {named} = "
                         f"\"{entries.get(named, '')}\"")

    # The word count is built in a 40-byte buffer: the head, five digits, the
    # tail and a terminator. Twenty for the head leaves the tail plenty.
    for key, most in (("WHEAD", 20), ("WTAIL", 12), ("WTAIL1", 12)):
        if len(entries.get(key, "")) > most:
            sys.exit(f"{path}: {key} is {len(entries[key])} characters and the "
                     f"word count has room for {most}")

    # The header stays plain ASCII on purpose: this file is fed to Merlin32,
    # and the very characters this tool exists to translate are the ones an
    # assembler comment cannot be trusted to carry.
    out = [
        "*" + "-" * 37,
        f"* GENERATED from {path} by tools/genlang.py -- DO NOT EDIT.",
        "*",
        "* Edit the language file and rebuild. The letters this machine has no",
        "* glyph for are transliterated on the way here; tools/xfer.sh turns",
        "* them back into UTF-8 on the way to the Mac. See genlang.py for the",
        "* mapping.",
        "*" + "-" * 37,
        "",
    ]

    for key in order:
        pieces = encode(entries[key], key, path)
        if key in WIDTHS and width(pieces) != WIDTHS[key]:
            sys.exit(f"{path}: {key} is {width(pieces)} characters and the "
                     f"screen wants exactly {WIDTHS[key]}. It is a layout, not "
                     f"a sentence -- see the columns in lang/en.txt.")
        label = key.ljust(12)
        for kind, val in pieces:
            if kind == "asc":
                out.append(f'{label} asc   "{val}"')
            else:
                out.append(f"{label} dfb   ${val:02x}")
            label = " " * 12
        out.append(f"{label} dfb   $00")      # an empty string is just this, labelled
        if key == "UNTITLED":
            # display.S draws the placeholder from a length rather than from
            # the terminator, so the length is a property of the string and
            # belongs with it -- not in equates.S, where it cannot follow a
            # translation.
            out.append(f"{'UNTLEN'.ljust(12)} equ   {width(pieces)}")

    print("\n".join(out))

if __name__ == "__main__":
    main(sys.argv)
