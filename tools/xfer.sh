#!/bin/bash
# xfer.sh -- move Markdown between a ProDOS disk image and the Mac.
#
#   xfer.sh pull <image> <dir>   image -> dir, as UTF-8 with LF endings
#   xfer.sh push <image> <dir>   dir -> image, as ProDOS TXT
#   xfer.sh unwrap <file>...     rejoin paragraphs in a legacy file, in place
#
# Apple II text files are high ASCII with CR ($8D) line endings; the Mac wants
# low ASCII with LF. That conversion is the whole job.
#
# This also works against real hardware: dd a CFFA CompactFlash card to a .po
# file and the same commands apply, so the emulator and the real //e share one
# workflow.
#
# `unwrap` is for files saved before the editor learned to tell its own wrapping
# from a return the writer typed. In those every line ending is the same byte, so
# nothing can recover the difference -- and reflow in the editor cannot help,
# because it now treats every return as deliberate. This joins each paragraph
# back into one line so the file behaves like ordinary Mac text again. Files
# saved since do not need it: the editor already writes them unwrapped.
#
# NOTE: Virtual ][ buffers writes to a mounted image until the disk is ejected.
# Pull after saving in the emulator will show stale contents unless you eject
# first -- `make eject` does that.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AC="$ROOT/tools/ac"

cmd="${1:?usage: xfer.sh pull|push <image> <dir> | unwrap <file>...}"
shift

# pull and push work on an image and a directory; unwrap works on plain files,
# so only the first two demand them.
case "$cmd" in
pull|push)
    IMAGE="${1:?usage: xfer.sh $cmd <image> <dir>}"
    DIR="${2:?usage: xfer.sh $cmd <image> <dir>}"
    ;;
esac

case "$cmd" in
pull)
    mkdir -p "$DIR"
    n=0
    # -lsj gives us the catalog as JSON, so we can pick out just the TXT files
    # rather than parsing a human-readable listing.
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        "$AC" -g "$IMAGE" "$name" > "$DIR/.raw.$$" 2>/dev/null || continue
        out="$DIR/$(echo "$name" | tr 'A-Z' 'a-z')"
        case "$out" in *.md|*.markdown) ;; *) out="$out.md" ;; esac
        python3 -c '
import sys
raw = open(sys.argv[1],"rb").read()
text = "".join(chr(b & 0x7F) for b in raw).replace("\r","\n")
open(sys.argv[2],"w",encoding="utf-8").write(text)
' "$DIR/.raw.$$" "$out"
        rm -f "$DIR/.raw.$$"
        echo "  pulled $name -> $out ($(wc -c < "$out" | tr -d ' ') bytes)"
        n=$((n+1))
    done < <("$AC" -lsj "$IMAGE" 2>/dev/null \
             | python3 -c '
import json,sys
try:    d = json.load(sys.stdin)
except Exception: sys.exit(0)
def walk(node):
    for f in node.get("files", []):
        if f.get("type","").upper() == "TXT":
            print(f["name"])
        walk(f)
for disk in d.get("disks", []):
    walk(disk)
')
    echo "pulled $n file(s) from $IMAGE"
    ;;

push)
    [ -d "$DIR" ] || { echo "no such directory: $DIR" >&2; exit 1; }
    n=0
    for f in "$DIR"/*.md "$DIR"/*.markdown; do
        [ -e "$f" ] || continue
        # printf, not echo: basename ends with a newline, and `tr -c` faithfully
        # turns that newline into a dot -- which is how every pushed file ended
        # up called NAME..MD instead of NAME.MD.
        base="$(printf '%s' "$(basename "${f%.*}")" | tr 'a-z' 'A-Z' | tr -c 'A-Z0-9.' '.')"
        name="$(printf '%s' "$base" | cut -c1-12).MD"
        python3 -c '
import sys
text = open(sys.argv[1],encoding="utf-8").read().replace("\n","\r")
sys.stdout.buffer.write(bytes((ord(c) | 0x80) & 0xFF for c in text if ord(c) < 128))
' "$f" > "/tmp/.push.$$"
        "$AC" -d "$IMAGE" "$name" 2>/dev/null || true
        "$AC" -p "$IMAGE" "$name" TXT < "/tmp/.push.$$"
        rm -f "/tmp/.push.$$"
        echo "  pushed $f -> $name"
        n=$((n+1))
    done
    echo "pushed $n file(s) to $IMAGE"
    ;;

unwrap)
    [ $# -gt 0 ] || { echo "usage: xfer.sh unwrap <file>..." >&2; exit 1; }
    for f in "$@"; do
        [ -f "$f" ] || { echo "  no such file: $f" >&2; continue; }
        python3 - "$f" <<'PY'
import re, sys, pathlib

# Lines that must never be joined: blank, headings, list items, ordered items,
# quotes, tables, horizontal rules, indented code. Joining any of these is how
# an unwrapper eats a list.
STRUCT = re.compile(r'^(\s*$|#{1,6} |[-*+] |\d+[.)] |> |\||-{3,}\s*$|={3,}\s*$|    |\t|```|~~~)')
FENCE  = re.compile(r'^\s*(```|~~~)')

def unwrap(text):
    out, fenced = [], False
    for line in text.split("\n"):
        if FENCE.match(line):
            fenced = not fenced
            out.append(line)
            continue
        if fenced:                      # code is passed through untouched
            out.append(line)
            continue
        prev = out[-1] if out else ""
        joinable = (out and prev and not STRUCT.match(prev)
                    and not STRUCT.match(line)
                    and not prev.endswith("  "))   # a Markdown hard break
        if joinable:
            out[-1] = prev + " " + line
        else:
            out.append(line)
    return "\n".join(out)

path = pathlib.Path(sys.argv[1])
before = path.read_text(encoding="utf-8")
after = unwrap(before)

# Unwrapping only ever turns a newline into a space, so the text with runs of
# whitespace collapsed must come out identical. If it does not, something was
# lost or moved and the file is left alone.
sig = lambda t: re.sub(r'\s+', ' ', t).strip()
if sig(before) != sig(after):
    print(f"  REFUSED {path}: content would change, left untouched", file=sys.stderr)
    sys.exit(1)

if after == before:
    print(f"  {path}: already unwrapped")
else:
    path.write_text(after, encoding="utf-8")
    b, a = len(before.split("\n")), len(after.split("\n"))
    print(f"  {path}: {b} lines -> {a}")
PY
    done
    ;;

*)
    sed -n '2,14p' "$0"
    exit 1
    ;;
esac
