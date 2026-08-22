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
OUT="${1:-$ROOT/build/ZIPEDIT.po}"
BIN="${2:-$ROOT/build/ZIPEDIT.SYSTEM}"
VOL="${VOL:-ZIPEDIT}"
SYS="${SYS:-ZIPEDIT.SYSTEM}"

# Everything on the stock 2.4.3 disk that we don't need. PRODOS stays.
# RELEASE=1 keeps BASIC.SYSTEM so that quitting the editor lands somewhere
# sensible instead of at the bare ProDOS dispatcher. It is added AFTER
# our SYS file so that ours is still first in directory order and still
# what ProDOS auto-launches at boot.
STRIP=(VIEW.README BITSY.BOOT QUIT.SYSTEM BASIC.SYSTEM COPYIIPLUS.8.4
       BLOCKWARDEN CAT.DOCTOR UNSHRINK CD.EXT FASTDSK FASTDSK.CONF
       FASTDSK.SYSTEM MAKE.SMALL.P8 MINIBAS MR.FIXIT.Y2K README)

# A ProDOS filename stops at 15 characters, and AppleCommander truncates
# rather than complains. Truncating a .SYSTEM name takes the .SYSTEM off the
# end of it, ProDOS stops recognising it as bootable, and the disk comes up in
# BASIC with no hint as to why -- which is a long way to travel to find out,
# with a card in your hand and the Apple already switched on.
if [ ${#SYS} -gt 15 ]; then
    echo "SYS name '$SYS' is ${#SYS} characters; ProDOS allows 15." >&2
    echo "It would be written as '${SYS:0:15}' and would not auto-boot." >&2
    exit 1
fi

[ -f "$BASE" ] || { echo "missing base image: $BASE" >&2; exit 1; }
[ -f "$BIN" ]  || { echo "missing binary: $BIN (run make first)" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"

# Eject this image from Virtual ][ before overwriting it. The emulator buffers
# writes to a mounted image and flushes them on eject -- so building an image
# that is currently mounted, then booting it, lets that flush land ON TOP of
# what was just built. The editor then runs a stale binary of exactly the same
# size, which is invisible until something compares the two. That cost a whole
# suite run to find.
osascript >/dev/null 2>&1 <<EJECT || true
tell application "Virtual ]["
    repeat with m in machines
        tell m
            try
                if (disk image of device "S6D1") is "$OUT" then eject device "S6D1"
            end try
        end tell
    end repeat
end tell
EJECT

cp "$BASE" "$OUT"

for f in "${STRIP[@]}"; do
    "$AC" -d "$OUT" "$f" 2>/dev/null || true
done

"$AC" -n "$OUT" "$VOL"
"$AC" -p "$OUT" "$SYS" SYS 0x2000 < "$BIN"

if [ "${RELEASE:-0}" = "1" ]; then
    "$AC" -g "$BASE" BASIC.SYSTEM 2>/dev/null > /tmp/.basic.$$ \
      && "$AC" -p "$OUT" BASIC.SYSTEM SYS 0x2000 < /tmp/.basic.$$
    rm -f /tmp/.basic.$$
fi

# Strip macOS metadata: on a FAT card these become ._ sidecar files, which
# clutter the volume and help fragment it. The Floppy Emu needs each image
# stored contiguously and refuses one that is not.
xattr -c "$OUT" 2>/dev/null || true

echo "built $OUT"
"$AC" -l "$OUT"
