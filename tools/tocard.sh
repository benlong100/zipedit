#!/bin/bash
# tocard.sh -- copy a disk image to an SD card or CF card cleanly.
#
#   tools/tocard.sh <volume-name> [image ...]
#
# The Floppy Emu reads the card at block level and needs each image stored
# CONTIGUOUSLY; it reports "File not contiguous" otherwise. Fragmentation comes
# from writing and deleting files over time, and from the metadata macOS
# scatters across a FAT volume. So this removes any existing copy first, purges
# the macOS clutter, and writes the image as one fresh file.
#
# If it still complains, reformat the card as MS-DOS (FAT32) and copy again --
# a freshly formatted card has one contiguous free extent.
set -euo pipefail

VOL="${1:?usage: tocard.sh <volume-name> [image ...]}"; shift
DEST="/Volumes/$VOL"
[ -d "$DEST" ] || { echo "no volume mounted at $DEST" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGES=("$@")
[ ${#IMAGES[@]} -eq 0 ] && IMAGES=("$ROOT/build/ZIPEDIT-REL.po")

# Stop Spotlight re-creating its index here; that is what keeps scattering
# directories among the disk images.
touch "$DEST/.metadata_never_index" 2>/dev/null || true

echo "==> clearing macOS metadata from $DEST"
rm -rf "$DEST/.Spotlight-V100" "$DEST/.fseventsd" "$DEST/.Trashes" 2>/dev/null || true
find "$DEST" -name '._*' -delete 2>/dev/null || true

for img in "${IMAGES[@]}"; do
    name="$(basename "$img")"
    echo "==> $name"
    rm -f "$DEST/$name"            # remove first: overwriting can reuse a hole
    sync
    cp -X "$img" "$DEST/$name"    # -X: no extended attributes, so no ._ sidecar
    xattr -c "$DEST/$name" 2>/dev/null || true
    printf '    %s bytes\n' "$(stat -f%z "$DEST/$name")"
done

find "$DEST" -name '._*' -delete 2>/dev/null || true
sync

# Every image on the card, not just the ones we wrote. Copying leaves earlier
# images in place -- they are somebody's data as far as this script knows -- so
# a renamed build quietly leaves its predecessor behind, and the Floppy Emu
# lists both. That is confusing enough to be worth naming out loud rather than
# deleting on a guess.
echo
echo "images now on $DEST:"
stray=0
while IFS= read -r f; do
    name="$(basename "$f")"
    mark="   "
    for img in "${IMAGES[@]}"; do
        [ "$name" = "$(basename "$img")" ] && mark="** "
    done
    [ "$mark" = "   " ] && stray=$((stray + 1))
    printf "  %s%-28s %6s KB\n" "$mark" "$name" "$(( $(stat -f%z "$f") / 1024 ))"
done < <(find "$DEST" -maxdepth 1 \( -iname '*.po' -o -iname '*.dsk' -o -iname '*.2mg' \) | sort)
echo "  ** = written by this run"
if [ "$stray" -gt 0 ]; then
    echo
    echo "note: $stray other image(s) are on the card. If one is an older build"
    echo "      under a previous name, delete it -- otherwise it still boots."
fi

echo
echo "done. Eject the card in Finder before removing it."
df -h "$DEST" | tail -1 | awk '{print "free on card: "$4}'
