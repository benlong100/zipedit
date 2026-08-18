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

# Virtual ][ now paces keystrokes itself (vii.sh pins a keyboard delay), so
# this sleep only has to cover the editor's redraw, not the key injection.
KEYSLEEP="${KEYSLEEP:-0.3}"
k() { "$VII" "$@" >/dev/null; sleep "$KEYSLEEP"; }

ln_field() { "$VII" screen-raw | sed -n '24p' | cut -c40-43 | tr -d ' '; }
cl_field() { "$VII" screen-raw | sed -n '24p' | cut -c47-49 | tr -d ' '; }

# drain_ok -- wait for the status row to hold still, then insist it reads
# line 1 column 1. A status that keeps drifting means keystrokes are still
# arriving that this section never sent.
drain_ok() {
    local prev="" cur stable=0 i
    for i in $(seq 1 40); do
        cur="$(ln_field):$(cl_field)"
        if [ "$cur" = "$prev" ]; then stable=$((stable+1)); else stable=0; fi
        if [ "$stable" -ge 4 ]; then [ "$cur" = "1:1" ]; return $?; fi
        prev="$cur"; sleep 0.5
    done
    return 1
}

# reboot [caps] -- boot the image and do not return until the editor is idle
# at the top of the document. Three failures used to slip through here, and
# each one silently poisoned every later section:
#   * `vii.sh boot` could fail to restart at all (a failed eject made the
#     insert throw), leaving the previous section's machine under test. It
#     now exits non-zero and we abort.
#   * `await` returns the instant the text appears, while the editor is still
#     drawing and still draining keys.
#   * Surplus AppleScript keystrokes outlive a restart. vii.sh pins a keyboard
#     delay so the queue cannot build up, but a run that inherits an already
#     wedged machine still has to wait it out.
reboot() {
    local capsval="${1:-false}" tries
    for tries in 1 2 3; do
        "$VII" boot "$IMAGE" >/dev/null || { echo "boot failed"; exit 1; }
        if ! "$VII" await "Notes from the Apple" 120 >/dev/null; then continue; fi
        "$VII" caps "$capsval" >/dev/null
        drain_ok && return 0
        echo "  (machine still restless after boot, retrying)" >&2
    done
    echo "editor never reached a quiet L1 C1 after 3 boots"; exit 1
}

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
reboot
snapshot

echo "toolchain"
assert_mem "loaded image matches build artifact" 0x2000 "$(stat -f%z "$BIN")" 0 "$BIN"

echo "display layer"
assert_width "screen is 80 columns wide"            0
assert_row   "heading rendered from the aux buffer" 0 "# Notes from the Apple //e"
assert_row   "prose rendered from the aux buffer"    2 "runs under ProDOS 8"
assert_row   "Markdown punctuation survives"       10 '**bold** with Ctrl-B, *italic* with Ctrl-I'
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
check_text "gap shuffle preserved bytes across 500+ moves" "**bold** with Ctrl-B, *italic* with Ctrl-I"
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
reboot
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
if [ "$(xxd -p "$TMP/before.bin")" = "aa" ]; then
    ok "\$89 italicises outside leading whitespace"
else
    bad "\$89 italicises outside leading whitespace" \
        "byte before the cursor is $(xxd -p "$TMP/before.bin"), wanted aa (closing *)"
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
reboot

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

# Cutting says nothing now -- the line visibly going away is the feedback.
k oa "X"
"$VII" settle 2 >/dev/null
snapshot
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
reboot

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
reboot

# digit fields, 1-based cut columns
assert_lc() {
    local name="$1" wl="$2" wc="$3" gl gc prev="" i
    for i in 1 2 3 4 5 6; do
        gl=$(ln_field); gc=$(cl_field)
        [ "$gl:$gc" = "$prev" ] && break
        prev="$gl:$gc"; sleep 0.4
    done
    if [ "$gl" = "$wl" ] && [ "$gc" = "$wc" ]; then ok "$name"; else
        bad "$name" "status reads L$gl C$gc, expected L$wl C$wc"
    fi
}

assert_lc "status opens at line 1 column 1"            1 1
for i in 1 2 3 4 5; do "$VII" key "right arrow" >/dev/null; sleep 0.3; done
assert_lc "column tracks rightward movement"           1 6
for i in 1 2 3; do "$VII" key "down arrow" >/dev/null; sleep 0.3; done
assert_lc "line tracks downward movement"              4 6
"$VII" text "hello" >/dev/null; "$VII" await "hello" 60 >/dev/null; sleep 1
assert_lc "column tracks typing"                       4 11
"$VII" key "left arrow" >/dev/null; sleep 1
assert_lc "column tracks backward movement"            4 10
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
# Goal column. Line 0 of the sample is 26 columns, line 1 is empty, line 2 is
# long -- so passing through line 1 is exactly the case that used to truncate
# the column and never give it back.
#--------------------------------------
echo "goal column"
reboot

for i in $(seq 1 20); do k key "right arrow"; done
assert_lc "start part way along a line"                1 21
k key "down arrow"
assert_lc "an empty line clamps the column"            2 1
k key "down arrow"
assert_lc "the column comes back on the next line"     3 21
k key "down arrow"
assert_lc "and holds for the rest of the run"          4 21
k key "up arrow"
k key "up arrow"
assert_lc "the goal survives moving back up"           2 1

# Any horizontal move ends the run and re-anchors the goal.
k key "left arrow"
assert_lc "left wraps to the end of the line above"    1 27
k key "down arrow"
k key "down arrow"
assert_lc "and the new column becomes the goal"        3 27

#--------------------------------------
# Help screen. Bound to OA-H, not Ctrl-H: the //e maps Ctrl-H and the left
# arrow to the same $88, which is verified in the keyboard section below.
#--------------------------------------
echo "help screen"
reboot

"$VII" oa "?" >/dev/null
"$VII" await "KEYBOARD COMMANDS" 60 || bad "OA-? never opened help"
snapshot
# The border is MouseText. Virtual ][ reads those codes back as the ASCII
# characters they share a code with: $4C -> L, $5F -> _, $5C -> backslash.
#
# Every rule must be $4C. $5C draws TWO strokes, one at the top of its cell and
# one at the bottom, so a row of it renders as a double line -- that is what put
# a stray line across the top of the screen and two lines under the title. No
# backslash may appear anywhere in the box.
if "$VII" screen-raw | sed -n '1,21p' | grep -q '\\\\'; then
    bad "no double-stroke rule anywhere in the box" "a $5C row is present"
else
    ok "no double-stroke rule anywhere in the box"
fi
assert_row "the box has a top edge"                   0 "LLLLLLLL"
assert_row "help is titled"                           1 "KEYBOARD COMMANDS"
assert_row "a single rule sits under the title"       2 "LLLLLLLL"
assert_row "the sides are MouseText verticals"        5 "_   arrows"
assert_row "the bottom border is a MouseText rule"   20 "LLLLLLLL"

# A rule row must START at the corner cell. $5F draws its vertical at the left
# edge of its cell, so a rule beginning one cell in stops a whole cell short of
# the vertical and the corner reads as broken. The right-hand end is the mirror
# case: the vertical owns the corner cell and the rule stops against it.
corners="$("$VII" screen-raw | sed -n '1p;3p' | cut -c9 | tr -d '\n')"
if [ "$corners" = "LL" ]; then
    ok "the top rules reach the left corner"
else
    bad "the top rules reach the left corner" "column 8 of rows 0 and 2 reads [$corners], wanted [LL]"
fi
right="$("$VII" screen-raw | sed -n '1p;3p' | cut -c72 | tr -d '\n')"
if [ "$right" = "__" ]; then
    ok "and stop against the right vertical"
else
    bad "and stop against the right vertical" "column 71 of rows 0 and 2 reads [$right], wanted [__]"
fi

# $5F draws its vertical at the LEFT edge of its cell, so a full 64-cell rule
# overhangs the corner by a whole cell. 8 leading columns + 63 rule cells = 71.
bottom="$("$VII" screen-raw | sed -n '21p' | sed 's/[[:space:]]*$//')"
if [ "${#bottom}" -eq 71 ]; then
    ok "the bottom rule stops at the vertical"
else
    bad "the bottom rule stops at the vertical" "rule ends at column ${#bottom}, expected 71"
fi

# Page one is the typing page: moving, editing, selecting.
assert_row "page one lists movement keys"             5 "char / line"
assert_row "page one lists editing keys"              5 "delete left"
assert_row "page one keeps a gap before the border"   7 "delete to line end "
# The Open Apple is now its own glyph ($41), which Virtual ][ reads back as "A"
# since they share a code. Verified identical on real hardware.
assert_row "page one lists selecting"                12 "A-space      start selecting"
assert_row "page one says a key turns the page"      19 "press any key for more"
assert_row "page one numbers itself"                 19 "page 1 of 2"
assert_row "page one lists the Tab indent"            8 "indent two spaces"
assert_row "the status line still shows under the box" 23 "UNTITLED.MD"

# A key turns to page two rather than dismissing. CLIPBOARD appears only there.
"$VII" text " " >/dev/null
"$VII" await "CLIPBOARD" 60 || bad "a key never turned to page two"
snapshot
assert_row "page two lists the Markdown keys"         5 "**bold** word"
assert_row "page two lists search"                    5 "find / again"
assert_row "page two lists the clipboard"             8 "CLIPBOARD"
assert_row "page two lists new"                       9 "A-N      new"
assert_row "page two lists the file keys"            11 "A-S      save"
assert_row "page two lists the screen toggles"       15 "cheat sheet"
assert_row "page two says a key leaves"              19 "press any key to return"
assert_row "page two numbers itself"                 19 "page 2 of 2"
assert_row "page two is still the same box"          20 "LLLLLLLL"
assert_row "the status line still shows on page two" 23 "UNTITLED.MD"

# And a key from page two returns to the document.
"$VII" text " " >/dev/null; sleep 3
snapshot
assert_row "a key from page two restores the text"    0 "# Notes from the Apple //e"

# Ctrl-Y clears from the cursor to the end of the line.
k ctrl Y
sleep 2; snapshot
assert_blank "Ctrl-Y deletes to the end of the line"  0

#--------------------------------------
# Hard wrap. Typing is slow (~8 chars/sec: full buffer rescan and redraw per
# keystroke), so these wait on a sentinel word rather than a fixed delay.
#--------------------------------------
echo "hard wrap"
reboot

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
reboot
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
reboot

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
# Selection. OA-Space latches the mode, the arrows paint, Esc cancels.
# Shift-arrow was tried and dropped: $C063 does not track the shift key on real
# //e hardware, so there was nothing to detect.
#--------------------------------------
echo "selection"
reboot

selstate() {
    "$VII" dump 0x0050 0x08 0 "$TMP/sel.bin" >/dev/null
    python3 -c "d=open('$TMP/sel.bin','rb').read(); print(d[0], d[1])"
}
assert_sel() {
    local got; got="$(selstate)"
    if [ "$got" = "$2 $3" ]; then ok "$1"; else bad "$1" "SELACT/SELMODE are [$got], expected [$2 $3]"; fi
}

assert_sel "selection state is clean at startup"        0 0
k oa " "
assert_sel "OA-Space latches selection mode"            1 1
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do "$VII" key "right arrow" >/dev/null; sleep 0.25; done
sleep 2

# The selected run is drawn inverse, which Virtual ][ reads back as the plain
# characters -- so prove it from the buffer instead: cut and see what moved.
"$VII" caps true >/dev/null
k oa "X"
sleep 3; snapshot
assert_row "OA-X cuts the selected run, not the line"    0 " the Apple //e"
assert_sel "cutting ends selection mode"                0 0

k oa "V"
sleep 3; snapshot
assert_row "OA-V pastes the run back, without a newline" 0 "# Notes from the Apple //e"

# Typing over a selection replaces it.
"$VII" oa "<" >/dev/null; "$VII" await "Notes" 90 >/dev/null; sleep 1
k oa " "
for i in 1 2 3; do "$VII" key "right arrow" >/dev/null; sleep 0.25; done
"$VII" caps false >/dev/null
"$VII" text "Q" >/dev/null; sleep 3; snapshot
assert_row "typing replaces the selection"               0 "Qotes from the Apple"
assert_sel "and returns to ordinary editing"            0 0

# Esc abandons a selection without changing the text.
k oa " "
for i in 1 2 3 4; do "$VII" key "right arrow" >/dev/null; sleep 0.25; done
# Every arrow while selecting forces a full redraw, and the //e keyboard has no
# buffer -- an Esc sent into that redraw is dropped rather than queued. Settle
# first, or this fails intermittently with the selection still latched.
"$VII" settle 2 >/dev/null
"$VII" key esc >/dev/null; sleep 2; snapshot
assert_row "Esc leaves the text alone"                   0 "Qotes from the Apple"
assert_sel "Esc cancels selecting entirely"             0 0

#--------------------------------------
# Unsaved-changes guard. OA-Q sits beside OA-S and OA-O, so a slip must not
# cost the document. Runs before the file section because quitting ends the
# editor.
#--------------------------------------
echo "unsaved changes guard"
reboot

mod_field() { "$VII" screen-raw | sed -n '24p' | cut -c15-17; }
assert_mod() {
    local got; got="$(mod_field)"
    if [ "$got" = "$2" ]; then ok "$1"; else bad "$1" "MOD field reads [$got], expected [$2]"; fi
}

assert_mod "the sample document does not count as unsaved work" "   "
ktext "x"
assert_mod "editing raises MOD"                                 "MOD"

"$VII" caps true >/dev/null
k oa "Q"
sleep 2; snapshot
assert_row "OA-Q with unsaved work asks instead of quitting"   23 "UNSAVED CHANGES"

"$VII" key esc >/dev/null; sleep 2
snapshot
assert_row "Esc returns to editing"                            23 "UNTITLED.MD"
assert_mod "and the document is still modified"                 "MOD"

# Cancelling the filename prompt must not quit either -- that is the path that
# would silently discard work.
k oa "Q"; sleep 1
"$VII" text "S" >/dev/null; sleep 2
"$VII" key esc >/dev/null; sleep 3
snapshot
assert_row "a cancelled save prompt does not quit"             23 "UNTITLED.MD"
assert_mod "and still has unsaved changes"                      "MOD"

k oa "S"; ktext "MODTEST.MD"
"$VII" line "" >/dev/null
"$VII" await "UNTITLED" 90 || bad "save never completed"
assert_mod "saving clears MOD"                                  "   "

# With nothing outstanding, OA-Q goes straight out to ProDOS. The save above
# just finished a disk write and the //e keyboard has no buffer, so let the
# machine come to rest first or OA-Q is dropped rather than queued.
"$VII" settle 2 >/dev/null
k oa "Q"
for _ in $(seq 1 20); do "$VII" screen | grep -qE "SELECT|S6,D1" && break; sleep 1; done
if "$VII" screen | grep -qE "SELECT|S6,D1"; then
    ok "OA-Q with no unsaved work quits immediately"
else
    bad "OA-Q with no unsaved work quits immediately" "screen: $("$VII" screen | head -2 | tr '\n' '|')"
fi

#--------------------------------------
# A final line with no trailing return. RENDER flushes that partial line at
# CURROW but used to leave CURROW pointing at it, so BLANKTAIL immediately
# erased the row RENDER had just drawn. Any full redraw lost the line, and only
# the one-row path put it back -- which is why it looked like a help screen bug
# and was really a rendering one. Reported on real hardware.
#--------------------------------------
echo "unterminated last line"
reboot

"$VII" caps true >/dev/null; k oa "N"; "$VII" caps false >/dev/null
ktext "hello world"
snapshot
assert_row "typing shows the line"                              0 "hello world"

# Opening and closing help forces a full redraw, RENDER plus BLANKTAIL.
"$VII" oa "?" >/dev/null; "$VII" settle 2 >/dev/null
"$VII" text "x" >/dev/null; "$VII" settle 2 >/dev/null
"$VII" text "x" >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "a full redraw keeps the unterminated line"          0 "hello world"
assert_lc "and the cursor is still where it was"                1 12

# Same again with an earlier line above it, so the partial line is not row 0.
"$VII" line "" >/dev/null; "$VII" settle 2 >/dev/null
ktext "second line"
"$VII" oa "?" >/dev/null; "$VII" settle 2 >/dev/null
"$VII" text "x" >/dev/null; "$VII" settle 2 >/dev/null
"$VII" text "x" >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "the line above survives too"                        0 "hello world"
assert_row "and so does the partial line below it"              1 "second line"

#--------------------------------------
# New document. OA-N throws the whole document away, so it is guarded exactly
# as OA-Q is -- they share ASKUNSAVED, and these assertions are what stop the
# two from drifting apart.
#--------------------------------------
echo "new document"
reboot

ktext "zz"
assert_mod "editing before New raises MOD"                      "MOD"

"$VII" caps true >/dev/null
k oa "N"
sleep 2; snapshot
assert_row "OA-N with unsaved work asks first"                 23 "UNSAVED CHANGES"

"$VII" key esc >/dev/null; sleep 2
snapshot
assert_row "Esc returns to editing"                            23 "UNTITLED.MD"
assert_row "and the document is untouched"                      0 "zz# Notes from the Apple"
assert_mod "and it is still modified"                           "MOD"

# D discards. The buffer empties and the cursor goes back to the top.
k oa "N"; sleep 1
"$VII" text "D" >/dev/null
"$VII" settle 2 >/dev/null
snapshot
assert_blank "New empties the first row"                        0
assert_blank "and the rows below it"                           10
assert_mod "a new document counts as no unsaved work"           "   "
assert_lc "and the cursor sits at the top"                      1 1

# Nothing outstanding now, so OA-N must wipe without asking.
k oa "N"
sleep 2; snapshot
assert_row "OA-N with no unsaved work does not ask"            23 "UNTITLED.MD"

"$VII" caps false >/dev/null       # caps went on for the OA-N chords above
ktext "fresh"
snapshot
assert_row "typing starts the new document"                     0 "fresh"
assert_mod "and typing marks the new document modified"         "MOD"

#--------------------------------------
# File I/O. Round trips through a real ProDOS volume in the mounted image.
#--------------------------------------
echo "file i/o"
reboot true

# Disk operations take seconds of emulated time, and the Apple II keyboard has
# no buffer -- anything typed while ProDOS is working is simply dropped. So
# every file operation waits for its completion message before going on.
ktext "MARKER "
k oa "S"; ktext "T1.MD"; "$VII" line "" >/dev/null
# The busy notice is the feedback now; completion is the status row returning.
"$VII" await "UNTITLED" 90 || bad "save never completed"
snapshot
assert_row "OA-S returns to the status row when done" 23 "UNTITLED.MD"

# Corrupt the buffer, then load it back and check the corruption is gone.
ktext "JUNKJUNK"
snapshot
assert_row "buffer modified before reload"            0 "MARKER JUNKJUNK# Notes"
k oa "O"; ktext "T1.MD"; "$VII" line "" >/dev/null
"$VII" await "UNTITLED" 90 || bad "load never completed"
snapshot
assert_row "OA-O returns to the status row when done" 23 "UNTITLED.MD"
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
