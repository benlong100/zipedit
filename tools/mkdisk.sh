#!/bin/bash
# mkdisk.sh -- build a bootable ProDOS 8 disk containing the editor.
#
# Strategy: clone the verified ProDOS 2.4.3 image rather than formatting a
# fresh volume, so the ProDOS boot blocks are known-good. Then strip it down
# to just PRODOS and add our SYS file. ProDOS launches the first *.SYSTEM
# file in the volume directory, so leaving exactly one makes it auto-run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AC="$ROOT/tools/ac"
BASE="$ROOT/vendor/ProDOS_2_4_3.po"
OUT="${1:-$ROOT/build/EDIT.po}"
BIN="${2:-$ROOT/build/EDIT.SYSTEM}"
VOL="${VOL:-EDIT}"

# Everything on the stock 2.4.3 disk that we don't need. PRODOS stays.
# RELEASE=1 keeps BASIC.SYSTEM so that quitting the editor lands somewhere
# sensible instead of at the bare ProDOS dispatcher. It is added AFTER
# EDIT.SYSTEM so that EDIT.SYSTEM is still first in directory order and still
# what ProDOS auto-launches at boot.
STRIP=(VIEW.README BITSY.BOOT QUIT.SYSTEM BASIC.SYSTEM COPYIIPLUS.8.4
       BLOCKWARDEN CAT.DOCTOR UNSHRINK CD.EXT FASTDSK FASTDSK.CONF
       FASTDSK.SYSTEM MAKE.SMALL.P8 MINIBAS MR.FIXIT.Y2K README)

[ -f "$BASE" ] || { echo "missing base image: $BASE" >&2; exit 1; }
[ -f "$BIN" ]  || { echo "missing binary: $BIN (run make first)" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
cp "$BASE" "$OUT"

for f in "${STRIP[@]}"; do
    "$AC" -d "$OUT" "$f" 2>/dev/null || true
done

"$AC" -n "$OUT" "$VOL"
"$AC" -p "$OUT" EDIT.SYSTEM SYS 0x2000 < "$BIN"

if [ "${RELEASE:-0}" = "1" ]; then
    "$AC" -g "$BASE" BASIC.SYSTEM 2>/dev/null > /tmp/.basic.$$ \
      && "$AC" -p "$OUT" BASIC.SYSTEM SYS 0x2000 < /tmp/.basic.$$
    rm -f /tmp/.basic.$$
fi

echo "built $OUT"
"$AC" -l "$OUT"
