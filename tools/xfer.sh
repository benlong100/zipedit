#!/bin/bash
# xfer.sh -- move Markdown between a ProDOS disk image and the Mac.
#
#   xfer.sh pull <image> <dir>   image -> dir, as UTF-8 with LF endings
#   xfer.sh push <image> <dir>   dir -> image, as ProDOS TXT
#
# Apple II text files are high ASCII with CR ($8D) line endings; the Mac wants
# low ASCII with LF. That conversion is the whole job.
#
# This also works against real hardware: dd a CFFA CompactFlash card to a .po
# file and the same commands apply, so the emulator and the real //e share one
# workflow.
#
# NOTE: Virtual ][ buffers writes to a mounted image until the disk is ejected.
# Pull after saving in the emulator will show stale contents unless you eject
# first -- `make eject` does that.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AC="$ROOT/tools/ac"

cmd="${1:?usage: xfer.sh pull|push <image> <dir>}"
IMAGE="${2:?}"
DIR="${3:?}"

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
        base="$(basename "${f%.*}" | tr 'a-z' 'A-Z' | tr -c 'A-Z0-9.' '.')"
        name="$(echo "$base" | cut -c1-12).MD"
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

*)
    sed -n '2,12p' "$0"
    exit 1
    ;;
esac
