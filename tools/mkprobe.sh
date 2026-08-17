#!/bin/bash
# mkprobe.sh -- bootable disk carrying only the character generator probe.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AC="$ROOT/tools/ac"
BASE="$ROOT/vendor/ProDOS_2_4_3.po"
OUT="$ROOT/build/CHARPROBE.po"
BIN="$ROOT/build/PROBE.SYSTEM"

STRIP=(VIEW.README BITSY.BOOT QUIT.SYSTEM BASIC.SYSTEM COPYIIPLUS.8.4
       BLOCKWARDEN CAT.DOCTOR UNSHRINK CD.EXT FASTDSK FASTDSK.CONF
       FASTDSK.SYSTEM MAKE.SMALL.P8 MINIBAS MR.FIXIT.Y2K README)

cp "$BASE" "$OUT"
for f in "${STRIP[@]}"; do "$AC" -d "$OUT" "$f" 2>/dev/null || true; done
"$AC" -n "$OUT" PROBE
"$AC" -p "$OUT" PROBE.SYSTEM SYS 0x2000 < "$BIN"
"$AC" -l "$OUT"
