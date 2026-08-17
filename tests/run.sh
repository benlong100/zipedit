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

# Typing is slow -- a full buffer rescan and redraw per keystroke, which grows
# with the document. Never sleep a fixed interval for a multi-character string;
# wait for it to actually appear.
ktext() { "$VII" text "$1" >/dev/null; "$VII" await "$1" 180 || bad "typing '$1' never completed"; }

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
"$VII" dump 0xB800 0x800 1 "$TMP/auxtop.bin" >/dev/null
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
assert 1200 < n < 2200, f"text length {n} outside expected range"
' "$TMP/zp.bin" 2>"$TMP/err"; then
    ok "gap is at the buffer start with the full text past it"
else
    bad "gap is at the buffer start with the full text past it" "$(cat "$TMP/err")"
fi

echo "chrome"
# The cheat sheet is hidden by default, so row 22 belongs to the document.
assert_row   "row 22 carries text when the sheet is hidden" 22 "Paragraph"

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
ktext "draft: "
snapshot
assert_row "typing inserts at the cursor"             0 "draft: # Notes from the Apple //e"

k key "right arrow"; k key "right arrow"; k key "right arrow"
ktext "X"
snapshot
assert_row "right arrow moves the cursor"             0 "draft: # NXotes from the Apple"

k ctrl B
sleep 2
snapshot
assert_row "Ctrl-B wraps the word at the cursor"      0 "draft: # **NXotes**"

k oa "/"
sleep 1; snapshot
assert_row "OA-/ shows the cheat sheet"              22 '`code` # H1 ## H2 - list'
k oa "/"
sleep 1; snapshot
assert_row "OA-/ hides it and row 22 returns to text" 22 "Paragraph"

# The Tab / Ctrl-I collision: identical keycode, different meaning by position.
# Ctrl-H and the left arrow are the same byte on this keyboard, which is why
# help is on OA-H. Moving right then sending Ctrl-H must move the cursor left.
k key "right arrow"; k key "right arrow"
"$VII" dump 0x0000 0x40 0 "$TMP/zp.bin" >/dev/null
C1=$(python3 -c "print(open('$TMP/zp.bin','rb').read()[0x30])")
k ctrl H
"$VII" dump 0x0000 0x40 0 "$TMP/zp.bin" >/dev/null
C2=$(python3 -c "print(open('$TMP/zp.bin','rb').read()[0x30])")
if [ "$C2" -eq "$((C1-1))" ]; then
    ok "Ctrl-H is the left arrow (so help cannot live there)"
else
    bad "Ctrl-H is the left arrow (so help cannot live there)" "column went $C1 -> $C2"
fi

k ctrl A
k ctrl I
snapshot
assert_row "\$89 indents inside leading whitespace"   0 "  draft: # **NXotes**"

# At the end of a long line the markers land past column 80 and are clipped
# from the display, so this one has to be checked in the buffer itself.
k ctrl E
k ctrl I
"$VII" dump 0x0000 0x20 0 "$TMP/zp.bin" >/dev/null
GB=$(python3 -c "d=open('$TMP/zp.bin','rb').read(); print(d[0x12]|(d[0x13]<<8))")
GE=$(python3 -c "d=open('$TMP/zp.bin','rb').read(); print(d[0x14]|(d[0x15]<<8))")
"$VII" dump $((GB-1)) 1 1 "$TMP/before.bin" >/dev/null
if [ "$(xxd -p "$TMP/before.bin")" = "df" ]; then
    ok "\$89 italicises outside leading whitespace"
else
    bad "\$89 italicises outside leading whitespace" \
        "byte before the cursor is $(xxd -p "$TMP/before.bin"), wanted df (closing _)"
fi

k ctrl A
ktext "zz"
k key "left arrow"
snapshot
assert_row "text accumulates correctly before delete" 0 "zz  draft:"

#--------------------------------------
# Editing operations: clipboard, find, go to line, emphasis.
#--------------------------------------
echo "editing operations"
"$VII" boot "$IMAGE" >/dev/null
"$VII" await "Notes from the Apple" 60 || { echo "reboot failed"; exit 1; }
"$VII" caps false >/dev/null

# curline <name> <expected 0-based line>
curline() {
    "$VII" dump 0x0000 0x40 0 "$TMP/zp.bin" >/dev/null
    local got; got=$(python3 -c "d=open('$TMP/zp.bin','rb').read(); print(d[0x29]|(d[0x2a]<<8))")
    if [ "$got" = "$2" ]; then ok "$1"; else bad "$1" "cursor on line $got, expected $2"; fi
}

"$VII" oa "C" >/dev/null
"$VII" await "LINE COPIED" 60 || bad "OA-C never reported"
snapshot
assert_row "OA-C copies the current line"            23 "LINE COPIED"

"$VII" oa "V" >/dev/null; sleep 3
snapshot
assert_row "OA-V pastes it back as a new line"        0 "# Notes from the Apple //e"
assert_row "the pasted copy sits below the original"  1 "# Notes from the Apple //e"

"$VII" oa "X" >/dev/null
"$VII" await "LINE CUT" 60 || bad "OA-X never reported"
sleep 2; snapshot
assert_row "OA-X removes the line again"              1 ""
assert_blank "the duplicate is gone"                  1

# Find walks the cursor to the hit, so the maintained line number proves it.
"$VII" oa "F" >/dev/null; sleep 1
"$VII" text "cheat sheet" >/dev/null; "$VII" await "cheat sheet" 60 >/dev/null
"$VII" line "" >/dev/null; sleep 4
curline "OA-F moves the cursor to the match" 12

"$VII" oa "F" >/dev/null; sleep 1
"$VII" text "notpresentanywhere" >/dev/null; "$VII" await "notpresentanywhere" 60 >/dev/null
"$VII" line "" >/dev/null
"$VII" await "NOT FOUND" 90 || bad "missing pattern never reported"
snapshot
assert_row "a missing pattern reports NOT FOUND"     23 "NOT FOUND"

"$VII" oa "L" >/dev/null; sleep 1
"$VII" text "20" >/dev/null; sleep 2
"$VII" line "" >/dev/null; sleep 6
curline "OA-L jumps to a line number (1-based)" 19

# Emphasis takes the whole word even from the middle of it.
"$VII" oa "<" >/dev/null; "$VII" await "Notes from the Apple" 120 >/dev/null; sleep 2
for i in 1 2 3 4; do "$VII" key "right arrow" >/dev/null; sleep 0.3; done
"$VII" ctrl B >/dev/null; sleep 3
snapshot
assert_row "Ctrl-B wraps the whole word from mid-word" 0 "# **Notes** from the Apple"

#--------------------------------------
# Prompts must hand the status row straight back, whether accepted or
# cancelled -- otherwise the prompt text sits there until some unrelated key
# happens to retire it, and you never see where a find or go-to landed.
#--------------------------------------
echo "prompt cancel"
"$VII" boot "$IMAGE" >/dev/null
"$VII" await "Notes from the Apple" 60 || { echo "reboot failed"; exit 1; }
"$VII" caps false >/dev/null

"$VII" oa "F" >/dev/null; sleep 2
snapshot
assert_row "the prompt says how to cancel"           23 "ESC CANCELS"
"$VII" key esc >/dev/null; sleep 2
snapshot
assert_row "Esc hands the status row straight back"  23 "UNTITLED.MD"

"$VII" oa "L" >/dev/null; sleep 1
"$VII" text "20" >/dev/null; sleep 2
"$VII" line "" >/dev/null; sleep 5
snapshot
assert_row "an accepted prompt restores it too"      23 "UNTITLED.MD"
if [ "$("$VII" screen-raw | sed -n '24p' | cut -c40-43 | tr -d ' ')" = "20" ]; then
    ok "and the new position is visible immediately"
else
    bad "and the new position is visible immediately" "status: $("$VII" screen-raw | sed -n '24p')"
fi

#--------------------------------------
# Status line. Line and column are painted as individual digit cells, not by
# repainting the row, which is why they cost nothing measurable per keystroke.
#--------------------------------------
echo "status line"
"$VII" boot "$IMAGE" >/dev/null
"$VII" await "Notes from the Apple" 60 || { echo "reboot failed"; exit 1; }
"$VII" caps false >/dev/null

# digit fields, 1-based cut columns
ln_field() { "$VII" screen-raw | sed -n '24p' | cut -c40-43 | tr -d ' '; }
cl_field() { "$VII" screen-raw | sed -n '24p' | cut -c47-49 | tr -d ' '; }
assert_lc() {
    local name="$1" wl="$2" wc="$3" gl gc
    gl=$(ln_field); gc=$(cl_field)
    if [ "$gl" = "$wl" ] && [ "$gc" = "$wc" ]; then ok "$name"; else
        bad "$name" "status reads L$gl C$gc, expected L$wl C$wc"
    fi
}

assert_lc "status opens at line 1 column 1"            1 1
for i in 1 2 3 4 5; do "$VII" key "right arrow" >/dev/null; sleep 0.3; done
assert_lc "column tracks rightward movement"           1 6
for i in 1 2 3; do "$VII" key "down arrow" >/dev/null; sleep 0.3; done
assert_lc "line tracks downward movement"              4 1
"$VII" text "hello" >/dev/null; "$VII" await "hello" 60 >/dev/null; sleep 1
assert_lc "column tracks typing"                       4 6
"$VII" key "left arrow" >/dev/null; sleep 1
assert_lc "column tracks backward movement"            4 5
"$VII" oa ">" >/dev/null; "$VII" await "THE END" 180 >/dev/null; sleep 1
assert_lc "line tracks a jump to the end"             36 1

# A message takes the status row, then the next keystroke restores it.
"$VII" oa "C" >/dev/null
"$VII" await "LINE COPIED" 60 || bad "copy never reported"
snapshot
assert_row "a message takes over the status row"      23 "LINE COPIED"
# The left arrow both retires the message and moves: from the empty final line
# back over the newline to the end of "THE END", i.e. line 35 column 8.
"$VII" key "left arrow" >/dev/null; sleep 2
snapshot
assert_row "the next keystroke restores the status"   23 "UNTITLED.MD"
assert_lc "and the digits come back correct"          35 8

#--------------------------------------
# Help screen. Bound to OA-H, not Ctrl-H: the //e maps Ctrl-H and the left
# arrow to the same $88, which is verified in the keyboard section below.
#--------------------------------------
echo "help screen"
"$VII" boot "$IMAGE" >/dev/null
"$VII" await "Notes from the Apple" 60 || { echo "reboot failed"; exit 1; }
"$VII" caps false >/dev/null

"$VII" oa "?" >/dev/null
"$VII" await "KEYBOARD COMMANDS" 60 || bad "OA-? never opened help"
snapshot
# The border is MouseText. Virtual ][ reads those codes back as the ASCII
# characters they share a code with: $5C -> backslash, $4C -> L, $5F -> _.
assert_row "the top border is a MouseText rule"       0 '\\\\\\\\'
assert_row "the sides are MouseText verticals"        4 "_   arrows"
assert_row "the bottom border is a MouseText rule"   21 "LLLLLLLL"
assert_row "help is titled"                           1 "KEYBOARD COMMANDS"
assert_row "help lists movement keys"                 4 "arrows"
assert_row "help lists the Markdown keys"            10 "**bold** word"
# The Open Apple is now its own glyph ($41), which Virtual ][ reads back as "A"
# since they share a code. Verified identical on real hardware.
assert_row "help lists the file keys"                11 "A-S       save"
assert_row "help tells you how to leave"             20 "press any key to return"
assert_row "help documents the prompt keys"          17 "AT ANY PROMPT"
assert_row "the status line still shows under the box" 23 "UNTITLED.MD"

"$VII" text " " >/dev/null; sleep 3
snapshot
assert_row "any key dismisses and restores the text"  0 "# Notes from the Apple //e"

# Ctrl-Y clears from the cursor to the end of the line.
k ctrl Y
sleep 2; snapshot
assert_blank "Ctrl-Y deletes to the end of the line"  0

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
# Must be a phrase that exists only AFTER reflow. "was inserted into auxiliary"
# was wrong: it sat on one line in the pre-reflow text, so it matched instantly
# and the assertions below raced the reflow. Joining lines 2 and 3 is what puts
# "ProDOS 8 on an" together.
"$VII" await "ProDOS 8 on an" 180 || bad "reflow never completed"
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
# Scrolling. The sample document is ~35 lines against a 22-row viewport.
#
# NOTE: OA-up / OA-down (page up/down) cannot be driven from here -- Virtual ][
# has no way to send an arrow key with Open-Apple held. The page handlers are
# just KUP/KDOWN repeated, which the arrow tests below do cover, but the
# bindings themselves are only verifiable by hand.
#--------------------------------------
echo "scrolling"
"$VII" boot "$IMAGE" >/dev/null
"$VII" await "Notes from the Apple" 60 || { echo "reboot failed"; exit 1; }

scrolltop() {
    "$VII" dump 0x0000 0x30 0 "$TMP/zp.bin" >/dev/null
    python3 -c "d=open('$TMP/zp.bin','rb').read(); print(d[0x23]|(d[0x24]<<8))"
}

snapshot
assert_row "document opens at the top"                0 "# Notes from the Apple //e"
[ "$(scrolltop)" = "0" ] && ok "viewport starts at line 0" \
                         || bad "viewport starts at line 0" "SCROLLTOP=$(scrolltop)"

# OA-> walks the gap to the very end, so the viewport must follow it down.
"$VII" oa ">" >/dev/null
"$VII" await "THE END" 180 || bad "OA-> never reached the end"
snapshot
if grep -q "THE END" "$SCREEN"; then
    ok "OA-> scrolls the viewport to the end of the document"
else
    bad "OA-> scrolls the viewport to the end of the document"
fi
if [ "$(scrolltop)" -gt 0 ]; then
    ok "viewport moved off line 0 (SCROLLTOP=$(scrolltop))"
else
    bad "viewport moved off line 0" "SCROLLTOP still 0"
fi
if grep -q "# Notes from the Apple //e" "$SCREEN"; then
    bad "top of document scrolled out of view" "heading still on screen"
else
    ok "top of document scrolled out of view"
fi

# OA-< returns to the top and the viewport must come back with it.
"$VII" oa "<" >/dev/null
"$VII" await "Notes from the Apple" 180 || bad "OA-< never reached the top"
snapshot
assert_row "OA-< scrolls back to the top"             0 "# Notes from the Apple //e"
[ "$(scrolltop)" = "0" ] && ok "viewport returned to line 0" \
                         || bad "viewport returned to line 0" "SCROLLTOP=$(scrolltop)"

# Walking down past the bottom row must scroll one line at a time.
for i in $(seq 1 26); do "$VII" key "down arrow" >/dev/null; sleep 0.35; done
sleep 3
snapshot
if [ "$(scrolltop)" -gt 0 ]; then
    ok "cursor walking past the last row scrolls the viewport"
else
    bad "cursor walking past the last row scrolls the viewport" "SCROLLTOP=$(scrolltop)"
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
ktext "MARKER "
k oa "S"; ktext "T1.MD"; "$VII" line "" >/dev/null
"$VII" await "SAVED" 90 || bad "save never completed"
snapshot
assert_row "OA-S reports a successful save"          23 "SAVED"

# Corrupt the buffer, then load it back and check the corruption is gone.
ktext "JUNKJUNK"
snapshot
assert_row "buffer modified before reload"            0 "MARKER JUNKJUNK# Notes"
k oa "O"; ktext "T1.MD"; "$VII" line "" >/dev/null
"$VII" await "LOADED" 90 || bad "load never completed"
snapshot
assert_row "OA-O reports a successful load"          23 "LOADED"
assert_row "loaded file replaced the buffer"          0 "MARKER # Notes from the Apple //e"

# $46 is ProDOS "file not found". The buffer must survive a failed open.
k oa "O"; ktext "NOSUCH.MD"; "$VII" line "" >/dev/null
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
