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

# The Floppy Emu reads FAT16 or FAT32. Disk Utility offers ExFAT by default for
# anything but a small card, and an ExFAT card looks perfectly fine on the Mac
# while the Emu cannot make sense of it -- which comes back as a complaint about
# the image rather than about the card, and sends you hunting the wrong problem.
FSTYPE="$(diskutil info "$DEST" 2>/dev/null | awk -F: '/Type \(Bundle\)/{gsub(/^[ \t]+/,"",$2); print $2}')"
case "$FSTYPE" in
    msdos|"") ;;
    *)  echo "WARNING: $DEST is $FSTYPE, and the Floppy Emu wants FAT32." >&2
        echo "         Reformat in Disk Utility as MS-DOS (FAT), not ExFAT." >&2
        echo "         Copying anyway, but expect the Emu to refuse it." >&2
        echo >&2
        ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGES=("$@")
[ ${#IMAGES[@]} -eq 0 ] && IMAGES=("$ROOT/build/ZIPEDIT-REL.po")

# Stop Spotlight re-creating its index here; that is what keeps scattering
# directories among the disk images.
touch "$DEST/.metadata_never_index" 2>/dev/null || true

echo "==> clearing macOS metadata from $DEST"
rm -rf "$DEST/.Spotlight-V100" "$DEST/.fseventsd" "$DEST/.Trashes" 2>/dev/null || true
find "$DEST" -name '._*' -delete 2>/dev/null || true

# THE HOLES THOSE DELETIONS JUST MADE ARE THE PROBLEM, AND THE BIGGEST OF THEM
# IS THE OLD COPY OF THE IMAGE ITSELF.
#
# macOS's FAT driver allocates from the first free cluster, so a hole near the
# front of the volume is where the next write goes. Clearing the metadata above
# leaves a scatter of small ones; deleting the previous image leaves eighteen
# clusters' worth in exactly the shape the previous image had.
#
# THE ORDER HERE IS THE WHOLE FIX. An earlier version wrote the filler first
# and deleted the old image afterwards, inside the copy loop -- so the filler
# covered the metadata holes, the delete then opened up the old image's
# clusters, and the copy dropped straight back into them. Fragmented exactly as
# before, every time, on a card that is 99.8% free. It appeared to work once,
# on a card that had never held the image.
#
# So: delete everything we are about to write FIRST, then fill what that left,
# then copy into the clean space beyond it, then take the filler away. The
# image is placed by then and does not move.
#
# HOW THIS WAS ESTABLISHED, because it took three bad guesses first: read the
# card's own FAT with tools/fatchain.py. A real card showed
#
#     ZIPEDIT-REL.po   clusters 8227..8244
#     ZIPFILER.po      clusters 8248..8249     <- a two-cluster hole
#     APPLESIDE.po     clusters 8250..8267
#     ZIPFILER.po      clusters 8268..8283
#
# -- the new copy had gone straight back into the shape the old one left. That
# is the whole mechanism, and it is self-perpetuating: once an image is
# fragmented, deleting it reopens exactly those clusters and the next copy
# takes them again. It never recovers on its own, which is why it happened
# every single time rather than now and then.
#
# THE FILLER ALSO HAS TO BE BIG ENOUGH. At 32MB it covered 4096 clusters and
# reached fifteen clusters past the fragmentation on that card -- true by luck
# rather than by design. 128MB is four times the distance the damage ran.
echo "==> removing previous copies"
for img in "${IMAGES[@]}"; do
    rm -f "$DEST/$(basename "$img")" 2>/dev/null || true
done
sync

FILLER="$DEST/.contiguous.tmp"
FILLMB="${FILLMB:-128}"
echo "==> filling fragmented free space (${FILLMB}MB scratch file)"
rm -f "$FILLER" 2>/dev/null || true
dd if=/dev/zero of="$FILLER" bs=1m count="$FILLMB" 2>/dev/null || \
    echo "    (could not write the filler; the copy may fragment)" >&2
sync

for img in "${IMAGES[@]}"; do
    name="$(basename "$img")"
    echo "==> $name"
    cp -X "$img" "$DEST/$name"    # -X: no extended attributes, so no ._ sidecar
    xattr -c "$DEST/$name" 2>/dev/null || true
    printf '    %s bytes\n' "$(stat -f%z "$DEST/$name")"
done

find "$DEST" -name '._*' -delete 2>/dev/null || true
sync

rm -f "$FILLER" 2>/dev/null || true    # the images are placed; let the space go
sync

# Every image on the card, not just the ones we wrote. The pattern below has to
# cover hard-disk images as well as floppies: a card holding a 32MB .hdv would
# otherwise be reported as holding one fewer image than it does. Nothing is
# lost, but a listing that quietly omits a file is worse than no listing,
# because it is read as a statement that the file is gone.
#
# Copying leaves earlier
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
done < <(find "$DEST" -maxdepth 1 \( -iname '*.po' -o -iname '*.dsk' -o -iname '*.2mg' \
                                      -o -iname '*.hdv' -o -iname '*.2img' \) | sort)
echo "  ** = written by this run"
if [ "$stray" -gt 0 ]; then
    echo
    echo "note: $stray other image(s) are on the card. If one is an older build"
    echo "      under a previous name, delete it -- otherwise it still boots."
fi

echo
strays="$(find "$DEST" -name '._*' 2>/dev/null | wc -l | tr -d ' ')"
[ "$strays" != "0" ] && echo "WARNING: $strays macOS sidecar file(s) still on the card" >&2

echo "done. Eject the card in Finder before removing it."
df -h "$DEST" | tail -1 | awk '{print "free on card: "$4}'
