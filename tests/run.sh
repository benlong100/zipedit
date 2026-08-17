#!/bin/bash
# tests/run.sh -- regression suite driven through Virtual ][.
#
# Boots the built image, then asserts against the emulated screen and against
# emulated RAM read back with `dump memory`. RAM assertions matter more than
# screen assertions once the text buffer exists, since the buffer lives in the
# aux bank and is only ever partially visible on screen.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VII="$ROOT/tools/vii.sh"
IMAGE="${IMAGE:-$ROOT/build/EDIT.po}"
BIN="${BIN:-$ROOT/build/EDIT.SYSTEM}"
WRAPCOL=76        # must match src/equates.S
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; shift; [ $# -gt 0 ] && printf '       %s\n' "$@"; fail=$((fail+1)); }

k() { "$VII" "$@" >/dev/null; sleep 0.6; }

SCREEN="$TMP/screen.txt"
snapshot() { "$VII" screen-raw > "$SCREEN"; }

# assert_row <name> <0-based row> <expected substring>
assert_row() {
    local name="$1" row="$2" want="$3"
    local got; got="$(sed -n "$((row+1))p" "$SCREEN")"
    if [[ "$got" == *"$want"* ]]; then ok "$name"; else
        bad "$name" "row $row expected to contain: $want" "row $row actually: ${got}"
    fi
}

# assert_width <name> <0-based row> -- the 80 column screen must be 80 wide
assert_width() {
    local name="$1" row="$2"
    local got; got="$(sed -n "$((row+1))p" "$SCREEN")"
    if [ "${#got}" -eq 80 ]; then ok "$name"; else
        bad "$name" "row $row is ${#got} columns, expected 80"
    fi
}

# assert_blank <name> <0-based row>
assert_blank() {
    local name="$1" row="$2"
    local got; got="$(sed -n "$((row+1))p" "$SCREEN")"
    if [ -z "${got// /}" ]; then ok "$name"; else
        bad "$name" "row $row expected blank, got: $got"
    fi
}

# assert_maxcols <name> <0-based row> <max> -- trailing spaces ignored
assert_maxcols() {
    local name="$1" row="$2" max="$3"
    local got; got="$(sed -n "$((row+1))p" "$SCREEN" | sed 's/ *$//')"
    if [ "${#got}" -le "$max" ]; then ok "$name"; else
        bad "$name" "row $row is ${#got} columns, expected <= $max"
    fi
}

# assert_mem <name> <addr> <len> <bank> <expected-file>
assert_mem() {
    local name="$1" addr="$2" len="$3" bank="$4" expect="$5"
    "$VII" dump "$addr" "$len" "$bank" "$TMP/mem.bin" >/dev/null
    if cmp -s "$TMP/mem.bin" "$expect"; then ok "$name"; else
        bad "$name" "RAM at $addr (bank $bank) does not match $expect"
    fi
}

echo "booting $IMAGE"
"$VII" boot "$IMAGE" >/dev/null
"$VII" await "Notes from the Apple" 40 || { echo "editor did not start"; exit 1; }
snapshot

echo "toolchain"
assert_mem "loaded image matches build artifact" 0x2000 "$(stat -f%z "$BIN")" 0 "$BIN"

echo "display layer"
assert_width "screen is 80 columns wide"            0
assert_row   "heading rendered from the aux buffer" 0 "# Notes from the Apple //e"
assert_row   "prose rendered from the aux buffer"    2 "runs under ProDOS 8"
assert_row   "Markdown punctuation survives"       10 '**bold** with Ctrl-B, _italic_ with Ctrl-I'
assert_row   "backtick code span renders"          11 '`code` spans and [links](url)'
assert_row   "blank lines stay blank"               1 ""

echo "auxiliary memory"
"$VII" dump 0xBF00 0x100 0 "$TMP/globals.bin" >/dev/null
if python3 -c '
import sys
d=open(sys.argv[1],"rb").read()
w=lambda o: d[o]|(d[o+1]<<8)
cnt=d[0x31]
assert w(0x26)==w(0x10), "slot 3 drive 2 driver still hooked"
assert not any((d[0x32+i]&0xF0)==0xB0 for i in range(cnt+1)), "/RAM still in DEVLST"
' "$TMP/globals.bin" 2>"$TMP/err"; then
    ok "/RAM disconnected from the ProDOS device tables"
else
    bad "/RAM disconnected from the ProDOS device tables" "$(cat "$TMP/err")"
fi

# The editor poisons all of aux with $E5 at startup, then inserts sample text.
# The untouched middle of the buffer must still read back as poison -- if
# anything else were living in auxiliary memory, this is where it would show.
"$VII" dump 0x2000 0x8000 1 "$TMP/auxmid.bin" >/dev/null
if python3 -c '
import sys
d=open(sys.argv[1],"rb").read()
assert len(d)==0x8000, f"short dump: {len(d)}"
bad=[i for i,b in enumerate(d) if b!=0xE5]
assert not bad, f"{len(bad)} bytes not $E5, first at ${0x2000+bad[0]:04X}"
' "$TMP/auxmid.bin" 2>"$TMP/err"; then
    ok "32K of untouched aux still reads back as poison"
else
    bad "32K of untouched aux still reads back as poison" "$(cat "$TMP/err")"
fi

echo "gap buffer"
# HOMECURSOR walks the gap to the buffer start one byte at a time, so the text
# ends up at the TOP of aux. Getting there exercised one aux read and one aux
# write per byte through the stack-page stub.
"$VII" dump 0xBC00 0x400 1 "$TMP/auxtop.bin" >/dev/null
check_text() {
    python3 -c '
import sys
d=open(sys.argv[1],"rb").read()
t="".join(chr(b & 0x7F) for b in d)
assert sys.argv[2] in t, f"not found in aux: {sys.argv[2]!r}"
' "$TMP/auxtop.bin" "$2" 2>"$TMP/err" && ok "$1" || bad "$1" "$(cat "$TMP/err")"
}
check_text "text is stored in auxiliary memory"        "# Notes from the Apple //e"
check_text "gap shuffle preserved bytes across 500+ moves" "**bold** with Ctrl-B, _italic_ with Ctrl-I"
check_text "backtick survives the round trip"          '`code` spans and [links](url)'

# GAPBEG must be at the buffer start after HOMECURSOR, and GAPEND must leave
# room for exactly the sample text.
"$VII" dump 0x0000 0x20 0 "$TMP/zp.bin" >/dev/null
if python3 -c '
import sys
d=open(sys.argv[1],"rb").read()
w=lambda o: d[o]|(d[o+1]<<8)
assert w(0x12)==0x0800, f"GAPBEG is ${w(0x12):04X}, expected $0800"
n=0xC000-w(0x14)
assert 500 < n < 600, f"text length {n} outside expected range"
' "$TMP/zp.bin" 2>"$TMP/err"; then
    ok "gap is at the buffer start with the full text past it"
else
    bad "gap is at the buffer start with the full text past it" "$(cat "$TMP/err")"
fi

echo "chrome"
assert_row   "cheat sheet on row 22"               22 '**bold** _italic_ `code` # H1'
assert_row   "status line on row 23"               23 "UNTITLED.MD"
assert_width "status line fills the row"           23

#--------------------------------------
# Keyboard tests mutate the buffer, so they run last and start from a fresh
# boot. Each keystroke triggers a full redraw, hence the settle between them.
#--------------------------------------
echo "keyboard"
"$VII" boot "$IMAGE" >/dev/null
"$VII" await "Notes from the Apple" 40 || { echo "reboot failed"; exit 1; }
"$VII" caps false >/dev/null
k text "draft: "
snapshot
assert_row "typing inserts at the cursor"             0 "draft: # Notes from the Apple //e"

k key "right arrow"; k key "right arrow"; k key "right arrow"
k text "X"
snapshot
assert_row "right arrow moves the cursor"             0 "draft: # NXotes from the Apple"

k ctrl B
k text "loud"
snapshot
assert_row "Ctrl-B wraps the cursor in bold markers"  0 "**loud**"

k oa "?"
snapshot
assert_blank "OA-? hides the cheat sheet"            22
k oa "?"
snapshot
assert_row "OA-? restores the cheat sheet"           22 '**bold** _italic_ `code` # H1'

# The Tab / Ctrl-I collision: identical keycode, different meaning by position.
k ctrl A
k ctrl I
snapshot
assert_row "\$89 indents inside leading whitespace"   0 "  draft: # NX"

# At the end of a long line the markers land past column 80 and are clipped
# from the display, so this one has to be checked in the buffer itself.
k ctrl E
k ctrl I
"$VII" dump 0x0000 0x20 0 "$TMP/zp.bin" >/dev/null
GB=$(python3 -c "d=open('$TMP/zp.bin','rb').read(); print(d[0x12]|(d[0x13]<<8))")
GE=$(python3 -c "d=open('$TMP/zp.bin','rb').read(); print(d[0x14]|(d[0x15]<<8))")
"$VII" dump $((GB-1)) 1 1 "$TMP/before.bin" >/dev/null
"$VII" dump "$GE"     1 1 "$TMP/after.bin"  >/dev/null
if [ "$(xxd -p "$TMP/before.bin")" = "df" ] && [ "$(xxd -p "$TMP/after.bin")" = "df" ]; then
    ok "\$89 italicises outside leading whitespace, cursor between the markers"
else
    bad "\$89 italicises outside leading whitespace, cursor between the markers" \
        "byte before gap: $(xxd -p "$TMP/before.bin"), after gap: $(xxd -p "$TMP/after.bin"), wanted df/df"
fi

k ctrl A
k text "zz"
k key "left arrow"
snapshot
assert_row "text accumulates correctly before delete" 0 "zz  draft:"

#--------------------------------------
# Hard wrap. Typing is slow (~8 chars/sec: full buffer rescan and redraw per
# keystroke), so these wait on a sentinel word rather than a fixed delay.
#--------------------------------------
echo "hard wrap"
"$VII" boot "$IMAGE" >/dev/null
"$VII" await "Notes from the Apple" 40 || { echo "reboot failed"; exit 1; }
"$VII" caps false >/dev/null

"$VII" text "aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk lll mmm nnn ooo ppp qqq rrr sss ttt zebra " >/dev/null
"$VII" await "zebra" 180 || bad "typed text never arrived"
snapshot
assert_maxcols "typing past the margin breaks the line" 0 "$WRAPCOL"
assert_row     "the overflow continues on the next row" 1 "zebra"

# The break must land on a space, never mid-word.
if sed -n '1p' "$SCREEN" | sed 's/ *$//' | grep -qE '[a-z]$'; then
    ok "line breaks at a word boundary"
else
    bad "line breaks at a word boundary" "row 0 ends: $(sed -n '1p' "$SCREEN" | sed 's/ *$//' | tail -c 12)"
fi

#--------------------------------------
# Reflow. Rejoins a paragraph and re-wraps it, leaving neighbours alone.
#--------------------------------------
echo "reflow"
"$VII" boot "$IMAGE" >/dev/null
"$VII" await "Notes from the Apple" 40 || { echo "reboot failed"; exit 1; }
"$VII" caps false >/dev/null
k key "down arrow"; k key "down arrow"
"$VII" oa "R" >/dev/null
"$VII" await "was inserted into auxiliary" 180 || bad "reflow never completed"
snapshot
assert_maxcols "reflowed row 2 fits the margin"        2 "$WRAPCOL"
assert_maxcols "reflowed row 3 fits the margin"        3 "$WRAPCOL"
assert_maxcols "reflowed row 4 fits the margin"        4 "$WRAPCOL"
assert_row     "heading above the paragraph untouched" 0 "# Notes from the Apple //e"
assert_blank   "blank line above the paragraph kept"   1
if grep -q "## How it writes" "$SCREEN"; then
    ok "reflow stopped at the paragraph boundary"
else
    bad "reflow stopped at the paragraph boundary" "the following heading was consumed"
fi

#--------------------------------------
# File I/O. Round trips through a real ProDOS volume in the mounted image.
#--------------------------------------
echo "file i/o"
"$VII" boot "$IMAGE" >/dev/null
"$VII" await "Notes from the Apple" 40 || { echo "reboot failed"; exit 1; }
"$VII" caps true >/dev/null

# Disk operations take seconds of emulated time, and the Apple II keyboard has
# no buffer -- anything typed while ProDOS is working is simply dropped. So
# every file operation waits for its completion message before going on.
k text "MARKER "
k oa "S"; k text "T1.MD"; "$VII" line "" >/dev/null
"$VII" await "SAVED" 90 || bad "save never completed"
snapshot
assert_row "OA-S reports a successful save"          23 "SAVED"

# Corrupt the buffer, then load it back and check the corruption is gone.
k text "JUNKJUNK"
snapshot
assert_row "buffer modified before reload"            0 "MARKER JUNKJUNK# Notes"
k oa "O"; k text "T1.MD"; "$VII" line "" >/dev/null
"$VII" await "LOADED" 90 || bad "load never completed"
snapshot
assert_row "OA-O reports a successful load"          23 "LOADED"
assert_row "loaded file replaced the buffer"          0 "MARKER # Notes from the Apple //e"

# $46 is ProDOS "file not found". The buffer must survive a failed open.
k oa "O"; k text "NOSUCH.MD"; "$VII" line "" >/dev/null
"$VII" await "PRODOS ERROR" 90 || bad "error never reported"
snapshot
assert_row "missing file reports a ProDOS error"     23 "PRODOS ERROR \$46"
assert_row "failed load leaves the buffer intact"     0 "MARKER # Notes from the Apple //e"

# Finally, verify from the Mac side that a real ProDOS file exists in the
# image. Virtual ][ buffers writes until eject, so flush first.
osascript -e 'tell application "Virtual ][" to tell (last machine) to eject device "S6D1"' >/dev/null 2>&1
sleep 2
if "$ROOT/tools/ac" -l "$IMAGE" 2>/dev/null | grep -q "T1.MD TXT"; then
    ok "saved file is a real ProDOS TXT file on the volume"
else
    bad "saved file is a real ProDOS TXT file on the volume" \
        "$("$ROOT/tools/ac" -l "$IMAGE" 2>&1 | tr '\n' '|')"
fi

# And that it converts to clean UTF-8 Markdown on the way out.
if "$ROOT/tools/ac" -g "$IMAGE" T1.MD 2>/dev/null > "$TMP/t1.raw" && python3 -c '
import sys
raw=open(sys.argv[1],"rb").read()
assert raw, "empty file"
assert all(b & 0x80 for b in raw), "not high ASCII"
text="".join(chr(b & 0x7F) for b in raw).replace("\r","\n")
assert text.startswith("MARKER # Notes from the Apple //e"), repr(text[:40])
assert "`code` spans" in text, "content lost"
' "$TMP/t1.raw" 2>"$TMP/err"; then
    ok "file converts to clean UTF-8 Markdown for the Mac"
else
    bad "file converts to clean UTF-8 Markdown for the Mac" "$(cat "$TMP/err")"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
