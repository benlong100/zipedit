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
IMAGE="${IMAGE:-$ROOT/build/ZIPEDIT.po}"
BIN="${BIN:-$ROOT/build/ZIPEDIT.SYSTEM}"
PLAINIMAGE="${PLAINIMAGE:-$ROOT/build/ZIPEDIT-PLAIN.po}"
TWOIMAGE="${TWOIMAGE:-$ROOT/build/ZIPEDIT2P.po}"
SLIMAGE="${SLIMAGE:-$ROOT/build/ZIPEDIT-SL.po}"
RELIMAGE="${RELIMAGE:-$ROOT/build/ZIPEDIT-REL.po}"

# One suite at a time. Virtual ][ has exactly one front machine, so a second
# run -- or a stray boot from another window -- steers the machine out from
# under the first, and what comes back is a scatter of failures in sections
# that were never touched. That has happened three times in one day, and each
# time cost a full run to work out that nothing was wrong with the code.
LOCK="${TMPDIR:-/tmp}/zipedit-suite.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    # A bare lock cannot tell "held" from "abandoned", and a run that dies
    # badly would then block every later one. Record the pid and take over a
    # lock whose owner is gone.
    other="$(cat "$LOCK/pid" 2>/dev/null)"
    if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then
        echo "another test run (pid $other) holds the emulator" >&2
        exit 2
    fi
    echo "clearing a stale lock from pid ${other:-unknown}" >&2
    rm -rf "$LOCK"
    mkdir "$LOCK" || { echo "cannot take $LOCK" >&2; exit 2; }
fi
echo "$$" > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT INT TERM
WRAPCOL=76        # must match src/equates.S
SCRW=80           # 80-column screen, likewise
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Every section must set up its own document. Three rules, learned the hard way
# when the editor stopped planting a sample at startup:
#
#   * needs the sample text          -> reboot        (opens SAMPLE.MD)
#   * types its own text and saves   -> reboot_empty  (unnamed, so OA-S prompts)
#   * needs the sample AND saves     -> reboot, then OA-A
#
# The third rule matters: with SAMPLE.MD open, the document CARRIES that name,
# so OA-S writes silently back over the suite's own fixture and poisons every
# later section -- and every later run, since the image outlives one.
# `make test` pushes a fresh SAMPLE.MD before each run for the same reason.
#
# One section can be run on its own:  tests/run.sh "help screen"
# The whole suite takes several minutes, nearly all of it booting the machine
# 25 times, so a targeted change should not have to pay for all of it.
ONLY="${1:-}"
section() {
    case "$1" in
        *"$ONLY"*) echo "$1"; return 0 ;;
        *)         return 1 ;;
    esac
}

pass=0; fail=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; shift; [ $# -gt 0 ] && printf '       %s\n' "$@"; fail=$((fail+1)); }

# Virtual ][ now paces keystrokes itself (vii.sh pins a keyboard delay), so
# this sleep only has to cover the editor's redraw, not the key injection.
KEYSLEEP="${KEYSLEEP:-0.3}"
k() { "$VII" "$@" >/dev/null; sleep "$KEYSLEEP"; }

# The numbers sit immediately after "L:" and "C:" and are LEFT aligned, so
# these are the cells the digits occupy, not a right-aligned field.
ln_field() { "$VII" screen-raw | sed -n '24p' | cut -c41-44 | tr -d ' '; }
cl_field() { "$VII" screen-raw | sed -n '24p' | cut -c48-50 | tr -d ' '; }

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
# reboot_empty -- boot to the empty document the editor now opens on. Sections
# that type their own text do not need SAMPLE.MD, and opening it costs a prompt
# and a disk read on every one of them.
reboot_empty() {
    local capsval="${1:-false}" tries
    for tries in 1 2 3; do
        "$VII" boot "$IMAGE" >/dev/null || { echo "boot failed"; exit 1; }
        if ! "$VII" await "ZipEdit" 120 >/dev/null; then continue; fi
        "$VII" text " " >/dev/null
        if ! "$VII" await "UNTITLED.MD" 60 >/dev/null; then continue; fi
        "$VII" caps "$capsval" >/dev/null
        if drain_ok; then snapshot; return 0; fi
        echo "  (machine still restless after boot, retrying)" >&2
    done
    echo "editor never reached a quiet L1 C1 after 3 boots"; exit 1
}

reboot() {
    local capsval="${1:-false}" tries
    for tries in 1 2 3; do
        "$VII" boot "$IMAGE" >/dev/null || { echo "boot failed"; exit 1; }
        # The splash screen comes up first and holds until a key is pressed.
        if ! "$VII" await "ZipEdit" 120 >/dev/null; then continue; fi
        "$VII" text " " >/dev/null
        # The editor opens on an empty document now, so the suite's text comes
        # off the disk: SAMPLE.MD is put there by the disk build.
        if ! "$VII" await "UNTITLED.MD" 60 >/dev/null; then continue; fi
        "$VII" caps true >/dev/null
        "$VII" oa "O" >/dev/null
        # Answer the unsaved-changes guard if it shows. It should not after a
        # fresh boot, but if it ever does, the S of SAMPLE.MD is read as
        # "S = SAVE FIRST" and the rest of the name lands in a save prompt.
        if "$VII" screen 2>/dev/null | grep -q "UNSAVED CHANGES"; then
            "$VII" text "D" >/dev/null
            sleep 1
        fi
        if ! "$VII" await "OPEN:" 30 >/dev/null; then continue; fi
        "$VII" text "SAMPLE.MD" >/dev/null
        "$VII" line "" >/dev/null
        if ! "$VII" await "Notes from the Apple" 120 >/dev/null; then continue; fi
        "$VII" caps "$capsval" >/dev/null
        if drain_ok; then snapshot; return 0; fi
        echo "  (machine still restless after boot, retrying)" >&2
    done
    echo "editor never reached a quiet L1 C1 after 3 boots"; exit 1
}

# Typing is slow -- a full buffer rescan and redraw per keystroke, which grows
# with the document. Never sleep a fixed interval for a multi-character string;
# wait for it to actually appear.
ktext() { "$VII" text "$1" >/dev/null; "$VII" await "$1" 180 || bad "typing '$1' never completed"; }

linenum() { "$VII" screen-raw | sed -n '24p' | cut -c41-44 | tr -d ' '; }
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

# new_doc -- OA-N, answering the unsaved-changes guard only if it appears.
# Without this, a following ktext feeds the guard letters until one of them is
# read as S = SAVE FIRST, and the test wanders into the save prompt.
new_doc() {
    "$VII" caps true >/dev/null
    k oa "N"
    if "$VII" screen 2>/dev/null | grep -q "UNSAVED CHANGES"; then
        "$VII" text "D" >/dev/null
        sleep 1
    fi
    "$VII" caps false >/dev/null
}

# prompt_open <OA key> <prompt text> -- open a prompt and wait for it to be up.
# A fixed sleep here is a race: type too early and the text goes into the
# document instead, the command gets an empty answer, and the failure looks
# like the command is broken.
prompt_open() {
    "$VII" oa "$1" >/dev/null
    "$VII" await "$2" 30 >/dev/null || bad "the $2 prompt never appeared"
}

# open_file <name> -- OA-O, answering the unsaved-changes guard only if it
# actually appears. Sending "D" unconditionally would type a D into the
# document on the runs where the buffer happens to be clean.
open_file() {
    k oa "O"
    if "$VII" screen 2>/dev/null | grep -q "UNSAVED CHANGES"; then
        "$VII" text "D" >/dev/null
        sleep 1
    fi
    ktext "$1"
    "$VII" line "" >/dev/null
}

# assert_block <name> <0-based column> -- the prompt's cursor is the MouseText
# checkerboard ($56) on the status row. The screen TEXT readback cannot tell it
# from a letter, so this reads the cell itself.
# Row 23 begins at $07D0; even columns live in aux, odd in main.
ROWBASE=(0x400 0x480 0x500 0x580 0x600 0x680 0x700 0x780
         0x428 0x4A8 0x528 0x5A8 0x628 0x6A8 0x728 0x7A8
         0x450 0x4D0 0x550 0x5D0 0x650 0x6D0 0x750 0x7D0)

# assert_cell <name> <0-based row> <0-based column> <expected byte>
assert_cell() {
    local name="$1" row="$2" col="$3" want="$4" bank addr byte
    if [ $((col % 2)) -eq 0 ]; then bank=1; else bank=0; fi
    addr=$(( ${ROWBASE[$row]} + col / 2 ))
    "$VII" dump "$addr" 1 "$bank" "$TMP/cell.bin" >/dev/null 2>&1
    byte="$(od -An -tu1 "$TMP/cell.bin" 2>/dev/null | tr -d ' \n')"
    if [ "$byte" = "$want" ]; then ok "$name"; else
        bad "$name" "row $row column $col holds $byte, wanted $want"
    fi
}

assert_block() { assert_cell "$1" 23 "$2" 86; }

# assert_centred <name> <0-based row> <text> -- and actually centred, which a
# substring check cannot tell you.
assert_centred() {
    local name="$1" row="$2" want="$3" got col pad
    got="$(sed -n "$((row+1))p" "$SCREEN" | sed 's/[[:space:]]*$//')"
    col=$(( (SCRW - ${#want}) / 2 ))
    pad="$(printf '%*s' "$col" '')"
    if [ "$got" = "$pad$want" ]; then ok "$name"; else
        bad "$name" "row $row is [$got]" "wanted [$want] centred at column $col"
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


#--- helpers that individual sections used to define for themselves. They live
#    here so that running one section alone still has them: bash reports a
#    missing function as 'command not found' WITHOUT failing, so a filtered run
#    would otherwise look green while skipping the assertions entirely.

check_text() {
    python3 -c '
import sys
d=open(sys.argv[1],"rb").read()
t="".join(chr(b & 0x7F) for b in d)
assert sys.argv[2] in t, f"not found in aux: {sys.argv[2]!r}"
' "$TMP/auxtop.bin" "$2" 2>"$TMP/err" && ok "$1" || bad "$1" "$(cat "$TMP/err")"
}
# curline <name> <expected 0-based line>
curline() {
    "$VII" dump 0x0000 0x40 0 "$TMP/zp.bin" >/dev/null
    local got; got=$(python3 -c "d=open('$TMP/zp.bin','rb').read(); print(d[0x29]|(d[0x2a]<<8))")
    if [ "$got" = "$2" ]; then ok "$1"; else bad "$1" "cursor on line $got, expected $2"; fi
}
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
scrolltop() {
    "$VII" dump 0x0000 0x30 0 "$TMP/zp.bin" >/dev/null
    python3 -c "d=open('$TMP/zp.bin','rb').read(); print(d[0x23]|(d[0x24]<<8))"
}
selstate() {
    "$VII" dump 0x0050 0x08 0 "$TMP/sel.bin" >/dev/null
    python3 -c "d=open('$TMP/sel.bin','rb').read(); print(d[0], d[1])"
}
assert_sel() {
    local got; got="$(selstate)"
    if [ "$got" = "$2 $3" ]; then ok "$1"; else bad "$1" "SELACT/SELMODE are [$got], expected [$2 $3]"; fi
}
# Unsaved changes show as a star directly after the filename, so the marker
# moves with the name and cannot be read from a fixed column. The filename is
# the first token on the status row; the star, if any, is stuck to it.
mod_star() {
    local row; row="$("$VII" screen-raw | sed -n '24p')"
    set -- $row
    case "$1" in *'*') echo yes ;; *) echo no ;; esac
}
assert_mod() {
    local got; got="$(mod_star)"
    if [ "$got" = "$2" ]; then ok "$1"; else
        bad "$1" "unsaved star: $got, wanted $2" \
            "row: $("$VII" screen-raw | sed -n '24p' | cut -c1-26)"
    fi
}


# --- helpers for the paste sections. All three read the buffer rather than the
#     screen: RENDER clips at the margin, so a line running past it is exactly
#     the thing the screen cannot show.

# _pregap -- everything between the start of the buffer and the cursor
_pregap() {
    "$VII" dump 0x12 4 0 "$TMP/gap.bin" >/dev/null
    _PGB=$(python3 -c "d=open('$TMP/gap.bin','rb').read(); print(d[0]|(d[1]<<8))")
    _PGE=$(python3 -c "d=open('$TMP/gap.bin','rb').read(); print(d[2]|(d[3]<<8))")
    : > "$TMP/pre.bin"
    [ "$_PGB" -gt 2048 ] && "$VII" dump 0x0800 $((_PGB-2048)) 1 "$TMP/pre.bin" >/dev/null
}

# maxline <name> <max> -- longest unbroken run of text before the cursor
maxline() {
    local name="$1" max="$2" got
    _pregap
    got=$(python3 -c "
d=open('$TMP/pre.bin','rb').read()
best=n=0
for b in d:
    if b<0xa0: n=0
    else:
        n+=1
        if n>best: best=n
print(best)")
    if [ "$got" -le "$max" ]; then ok "$name"; else
        bad "$name" "longest line is $got characters, expected <= $max"
    fi
}

# ccol_true <name> -- the column the editor reports against the column the
# buffer actually holds. It was the disagreement between the two, not the long
# line itself, that broke the reflow: CCOL wrapped at 256 and every wrap
# decision after that was taken on a lie.
ccol_true() {
    local name="$1" want got
    _pregap
    "$VII" dump 0x30 2 0 "$TMP/ccol.bin" >/dev/null
    got=$(python3 -c "d=open('$TMP/ccol.bin','rb').read(); print(d[0]|(d[1]<<8))")
    want=$(python3 -c "
d=open('$TMP/pre.bin','rb').read()
n=0
for b in reversed(d):
    if b<0xa0: break
    n+=1
print(n)")
    if [ "$got" = "$want" ]; then ok "$name"; else
        bad "$name" "editor says column $got, buffer says $want"
    fi
}

# textcount -- characters in the whole document as the FILE would hold them,
# newlines excluded. A SOFTCR counts as the one it stands in for: wrapping
# spends a space to store the break, so a paragraph that gains a soft wrap
# genuinely holds one text byte fewer while holding the same writing. Counting
# raw text bytes instead makes a correct reflow look like it lost a character
# per wrap. SOFTWD stands in for nothing and so counts as nothing, and HARDCR
# is a newline, not a character. The gap is not text either, so this is the two
# live halves and nothing between them.
textcount() {
    _pregap
    : > "$TMP/post.bin"
    [ "$_PGE" -lt 49152 ] && "$VII" dump "$_PGE" $((49152-_PGE)) 1 "$TMP/post.bin" >/dev/null
    python3 -c "
n=0
for f in ('$TMP/pre.bin','$TMP/post.bin'):
    for b in open(f,'rb').read():
        if b>=0xa0 or b==0x8a: n+=1
print(n)"
}

# cliplen -- how many characters OA-V would insert
cliplen() {
    "$VII" dump 0x63 2 0 "$TMP/clip.bin" >/dev/null
    python3 -c "d=open('$TMP/clip.bin','rb').read(); print(d[0]|(d[1]<<8))"
}


if section "toolchain"; then
assert_mem "loaded image matches build artifact" 0x2000 "$(stat -f%z "$BIN")" 0 "$BIN"
fi

#--------------------------------------
# Splash screen. Shown once at startup and held until a key is pressed. This
# boots directly rather than through reboot(), which dismisses the splash on
# its way to the document.
#--------------------------------------
if section "splash screen"; then
"$VII" boot "$IMAGE" >/dev/null || { echo "boot failed"; exit 1; }
"$VII" await "ZipEdit" 120 >/dev/null || bad "the splash never appeared"
"$VII" settle 2 >/dev/null
snapshot
assert_centred "the name is centred"                  10 "ZipEdit"
assert_centred "the version is centred below it"      12 "Version 1.4"
assert_centred "the date is centred below that"       14 "August, 2026"
assert_blank   "with a blank line between them"       13
# The Open Apple is a MouseText glyph, which reads back as "A".
assert_centred "the help hint is centred"             20 "A-? to get help"
assert_centred "and the prompt sits under it"         21 "press any key to continue"
assert_row     "the document is not showing yet"       0 ""
assert_blank   "the screen is otherwise blank"         5

# Any key dismisses it -- and must not reach the document. The editor opens on
# an empty document now, so what appears is the status row, not any text.
"$VII" text "Z" >/dev/null
"$VII" await "UNTITLED.MD" 60 >/dev/null || bad "the splash never cleared"
"$VII" settle 2 >/dev/null
snapshot
assert_row   "the status row appears once dismissed"  23 "UNTITLED.MD"
assert_blank "and the document is empty"               0
if [ "$(sed -n '1p' "$SCREEN" | cut -c1)" = "Z" ]; then
    bad "the dismissing key does not reach the document" "row 0 begins with the Z that dismissed it"
else
    ok "the dismissing key does not reach the document"
fi

fi

#--------------------------------------
# Quit, then relaunch from the ProDOS selector. Nothing in a dum block or on
# zero page is part of the loaded file, so none of it starts at a known value.
# A cold boot leaves that memory zero and the launch path looked correct by
# luck. Coming back from the selector it holds whatever that left behind, and
# FNAME's length byte read non-zero: the editor believed the document was
# already named, printed the garbage as its filename, and OA-S saved to it and
# threw a ProDOS error. KNEW cleared FNAME for a new document all along; only
# the launch path never did.
#--------------------------------------
if section "relaunch after quit"; then
"$VII" boot "$IMAGE" >/dev/null || { echo "boot failed"; exit 1; }
"$VII" await "ZipEdit" 120 >/dev/null || bad "the splash never appeared"
"$VII" text " " >/dev/null
"$VII" await "UNTITLED.MD" 60 >/dev/null || bad "the editor never opened"

"$VII" caps true >/dev/null
"$VII" oa "Q" >/dev/null
"$VII" await "RETURN:SELECT" 60 >/dev/null || bad "OA-Q never reached the selector"
"$VII" line "" >/dev/null            # our SYS file is the first entry
"$VII" await "ZipEdit" 120 >/dev/null || bad "the editor never relaunched"
"$VII" text " " >/dev/null
"$VII" await "UNTITLED.MD" 60 >/dev/null || bad "the relaunched editor never opened"
"$VII" caps false >/dev/null
"$VII" settle 2 >/dev/null
snapshot
assert_row "a relaunch still shows UNTITLED.MD"          23 "UNTITLED.MD"

# The other half of the same bug: believing it had a name, OA-S wrote to the
# garbage instead of asking for one, and reported a ProDOS error.
ktext "relaunched"
"$VII" caps true >/dev/null
k oa "S"
"$VII" settle 3 >/dev/null
snapshot
assert_row "and OA-S asks for a name instead of failing" 23 "SAVE AS:"
"$VII" key esc >/dev/null
"$VII" caps false >/dev/null
"$VII" settle 2 >/dev/null
fi

if section "display layer"; then
reboot
assert_width "screen is 80 columns wide"            0
assert_row   "heading rendered from the aux buffer" 0 "# Notes from the Apple //e"
assert_row   "prose rendered from the aux buffer"    2 "runs under ProDOS 8"
assert_row   "Markdown punctuation survives"       10 '**bold** with Ctrl-B, *italic* with Ctrl-I'
assert_row   "backtick code span renders"          11 '`code` spans and [links](url)'
assert_row   "blank lines stay blank"               1 ""
fi

if section "auxiliary memory"; then
reboot
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
fi

if section "gap buffer"; then
reboot
# HOMECURSOR walks the gap to the buffer start one byte at a time, so the text
# ends up at the TOP of aux. Getting there exercised one aux read and one aux
# write per byte through the stack-page stub.
"$VII" dump 0xB800 0x800 1 "$TMP/auxtop.bin" >/dev/null
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
fi

if section "chrome"; then
reboot
# The cheat sheet is hidden by default, so row 22 belongs to the document.
assert_row   "row 22 carries text when the sheet is hidden" 22 "Paragraph"

assert_row   "status line on row 23"               23 "A-? HELP"
assert_width "status line fills the row"           23
fi

#--------------------------------------
# Keyboard tests mutate the buffer, so they run last and start from a fresh
# boot. Each keystroke triggers a full redraw, hence the settle between them.
#--------------------------------------
if section "keyboard"; then
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
fi

#--------------------------------------
# Editing operations: clipboard, find, go to line, emphasis.
#--------------------------------------
if section "editing operations"; then
reboot


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
prompt_open F "FIND:"
"$VII" text "cheat sheet" >/dev/null; "$VII" await "cheat sheet" 60 >/dev/null
"$VII" line "" >/dev/null; sleep 4
curline "OA-F moves the cursor to the match" 12

prompt_open F "FIND:"
"$VII" text "notpresentanywhere" >/dev/null; "$VII" await "notpresentanywhere" 60 >/dev/null
"$VII" line "" >/dev/null
"$VII" await "NOT FOUND" 90 || bad "missing pattern never reported"
snapshot
assert_row "a missing pattern reports NOT FOUND"     23 "NOT FOUND"

prompt_open L "GO TO LINE:"
"$VII" text "20" >/dev/null; sleep 2
"$VII" line "" >/dev/null; sleep 6
curline "OA-L jumps to a line number (1-based)" 19

# Emphasis takes the whole word even from the middle of it.
"$VII" oa "<" >/dev/null; "$VII" await "Notes from the Apple" 120 >/dev/null; sleep 2
for i in 1 2 3 4; do "$VII" key "right arrow" >/dev/null; sleep 0.3; done
"$VII" ctrl B >/dev/null; sleep 3
snapshot
assert_row "Ctrl-B wraps the whole word from mid-word" 0 "# **Notes** from the Apple"
fi

#--------------------------------------
# Find, and the two ends it could not reach.
#
# The suite could see neither of these, because it only ever checked that OA-F
# lands on a match and that a missing pattern says so. It never pressed OA-G
# twice, and it never looked for anything lying at either end of the buffer.
#--------------------------------------
if section "find wraps"; then
reboot

# OA-G has to ADVANCE. The scan began at GAPEND, which is not one past the
# cursor but the character UNDER it, so a repeat re-matched where it stood and
# the cursor never moved -- for every pattern, every time.
prompt_open F "FIND:"
"$VII" text "the" >/dev/null; "$VII" settle 2 >/dev/null
"$VII" line "" >/dev/null; sleep 4
curline "OA-F lands on the first match"                    0
# ...and this one did not wrap, so the row must not claim it did
snapshot
if grep -q "WRAPPED" "$SCREEN"; then
    bad "an ordinary find stays quiet" "row 23: $(sed -n '24p' "$SCREEN")"
else
    ok "an ordinary find stays quiet"
fi
"$VII" caps true >/dev/null
k oa "G"; "$VII" settle 4 >/dev/null
curline "and OA-G moves on rather than standing still"     4
k oa "G"; "$VII" settle 4 >/dev/null
curline "and goes on again"                                12

# Wrapping: from the end of the document, a phrase that occurs only at the
# top. Without the second pass this is NOT FOUND.
k oa ">"; "$VII" settle 6 >/dev/null
prompt_open F "FIND:"
"$VII" caps false >/dev/null
"$VII" text "Notes from" >/dev/null
"$VII" await "Notes from" 60 >/dev/null
"$VII" line "" >/dev/null; "$VII" settle 5 >/dev/null
curline "a search from the end of the document wraps to the top" 0
snapshot
assert_row "and the row explains the backwards jump"    23 "WRAPPED TO THE TOP"

# The text after the cursor always runs to $BFFF, so a match lying against the
# end of the document is the very last thing a forward scan can reach -- and
# the limit was one byte short of reaching it.
"$VII" caps true >/dev/null
k oa ">"; "$VII" settle 6 >/dev/null
ktext "ZZQ"
"$VII" settle 3 >/dev/null
k oa "<"; "$VII" settle 6 >/dev/null
prompt_open F "FIND:"
"$VII" text "ZZQ" >/dev/null; "$VII" await "ZZQ" 60 >/dev/null
"$VII" line "" >/dev/null; "$VII" settle 5 >/dev/null
curline "a match against the end of the buffer is found"    35

# And a pattern that genuinely is absent still says so, rather than the wrap
# pass finding something or looping. Caps went on for ZZQ and has to come off
# again, or this types NOTPRESENTANYWHERE and then waits 60s for the lowercase
# it will never see.
prompt_open F "FIND:"
"$VII" caps false >/dev/null
"$VII" text "notpresentanywhere" >/dev/null
"$VII" await "notpresentanywhere" 60 >/dev/null
"$VII" line "" >/dev/null
"$VII" await "NOT FOUND" 90 || bad "an absent pattern never reported"
snapshot
assert_row "an absent pattern still reports NOT FOUND"     23 "NOT FOUND"
fi

#--------------------------------------
# Prompts must hand the status row straight back, whether accepted or
# cancelled -- otherwise the prompt text sits there until some unrelated key
# happens to retire it, and you never see where a find or go-to landed.
#--------------------------------------
if section "prompt cancel"; then
reboot

prompt_open F "FIND:"
snapshot
assert_row "the prompt says how to cancel"           23 "ESC CANCELS"
"$VII" key esc >/dev/null; sleep 2
snapshot
assert_row "Esc hands the status row straight back"  23 "A-? HELP"

prompt_open L "GO TO LINE:"
"$VII" text "20" >/dev/null; sleep 2
"$VII" line "" >/dev/null; sleep 5
snapshot
assert_row "an accepted prompt restores it too"      23 "A-? HELP"
if [ "$(ln_field)" = "20" ]; then
    ok "and the new position is visible immediately"
else
    bad "and the new position is visible immediately" "status: $("$VII" screen-raw | sed -n '24p')"
fi
fi

#--------------------------------------
# Status line. Line and column are painted as individual digit cells, not by
# repainting the row, which is why they cost nothing measurable per keystroke.
#--------------------------------------
if section "status line"; then
reboot


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
assert_row "the next keystroke restores the status"   23 "A-? HELP"
assert_lc "and the digits come back correct"          35 8

# Left aligned means the label touches its number: "L:35", not "L    35".
# Last in the section: the jump below moves the cursor, so nothing may depend
# on where it ends up.
snapshot
assert_row "the line label sits against its number"   23 "L:35"
assert_row "and so does the column label"             23 "C:8"

# Going back to a shorter number must not strand the old digits.
"$VII" oa "<" >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "a shrinking number blanks the rest of its field" 23 "L:1    C:1"
fi

#--------------------------------------
# Goal column. Line 0 of the sample is 26 columns, line 1 is empty, line 2 is
# long -- so passing through line 1 is exactly the case that used to truncate
# the column and never give it back.
#--------------------------------------
if section "goal column"; then
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
fi

#--------------------------------------
# Help screen. Bound to OA-H, not Ctrl-H: the //e maps Ctrl-H and the left
# arrow to the same $88, which is verified in the keyboard section below.
#--------------------------------------
if section "help screen"; then
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
# The top edge keeps a vertical in its corner cell, so the left border runs
# unbroken from the very top. The rule under the title starts AT the corner
# cell instead: the title row above already carries the vertical there, so the
# rule meets it squarely.
corners="$("$VII" screen-raw | sed -n '1p;3p' | cut -c9 | tr -d '\n')"
if [ "$corners" = "_L" ]; then
    ok "the corner cells carry the right glyphs"
else
    bad "the corner cells carry the right glyphs" "column 8 of rows 0 and 2 reads [$corners], wanted [_L]"
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

# This row was blank in every build up to 1.0.2: the command went into the
# layout in genhelp.py and src/help.S was never regenerated. Nothing asserted
# the row, so nothing noticed.
assert_row "page one documents OA-Delete"           10 "A-Delete delete word left"
# The Open Apple is now its own glyph ($41), which Virtual ][ reads back as "A"
# since they share a code. Verified identical on real hardware.
assert_row "page one lists selecting"                12 "A-space      start selecting"
assert_row "page one carries the web address"        18 "https://trompingmarmots.com/AppSites/ZipEdit/"
assert_row "page one says a key turns the page"      19 "press any key for more"
assert_row "page one numbers itself"                 19 "page 1 of 2"
assert_row "page one lists the Tab indent"            8 "indent two spaces"
assert_row "the status line still shows under the box" 23 "A-? HELP"

# A key turns to page two rather than dismissing. CLIPBOARD appears only there.
"$VII" text " " >/dev/null
"$VII" await "CLIPBOARD" 60 || bad "a key never turned to page two"
snapshot
assert_row "page two lists the Markdown keys"         5 "**bold** word"
assert_row "page two lists search"                    5 "find / again"
assert_row "page two lists the word count"            7 "A-W      word count"
assert_row "page two lists the clipboard"             9 "CLIPBOARD"
assert_row "page two lists new"                      10 "A-N      new"
assert_row "page two lists the file keys"            12 "A-S      save"
assert_row "page two lists save as"                  13 "A-A      save as"
assert_row "page two lists the screen toggles"       17 "cheat sheet"
assert_row "page two says a key leaves"              19 "press any key to return"
assert_row "page two numbers itself"                 19 "page 2 of 2"
assert_row "page two is still the same box"          20 "LLLLLLLL"
assert_row "the status line still shows on page two" 23 "A-? HELP"

# And a key from page two returns to the document.
"$VII" text " " >/dev/null; sleep 3
snapshot
assert_row "a key from page two restores the text"    0 "# Notes from the Apple //e"

# Ctrl-Y clears from the cursor to the end of the line.
k ctrl Y
sleep 2; snapshot
assert_blank "Ctrl-Y deletes to the end of the line"  0
fi

#--------------------------------------
# Hard wrap. Typing is slow (~8 chars/sec: full buffer rescan and redraw per
# keystroke), so these wait on a sentinel word rather than a fixed delay.
#--------------------------------------
if section "hard wrap"; then
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
fi

#--------------------------------------
# Reflow. Rejoins a paragraph and re-wraps it, leaving neighbours alone.
#--------------------------------------
if section "reflow"; then
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
fi

#--------------------------------------
# Scrolling. The sample document is ~35 lines against a 22-row viewport.
#
# NOTE: OA-up / OA-down (page up/down) cannot be driven from here -- Virtual ][
# has no way to send an arrow key with Open-Apple held. The page handlers are
# just KUP/KDOWN repeated, which the arrow tests below do cover, but the
# bindings themselves are only verifiable by hand.
#--------------------------------------
if section "scrolling"; then
reboot


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
fi

#--------------------------------------
# Selection. OA-Space latches the mode, the arrows paint, Esc cancels.
# Shift-arrow was tried and dropped: $C063 does not track the shift key on real
# //e hardware, so there was nothing to detect.
#--------------------------------------
if section "selection"; then
reboot


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
fi

#--------------------------------------
# A selection whose start is ABOVE the viewport.
#
# RENDER caches where the top visible line begins so it need not count down
# from byte zero, and that cache used to be refused whenever a selection was
# up: the bounds are logical positions and RPOS counts them one byte at a
# time. So every keystroke with a selection walked the whole document above
# the viewport, and the deeper in you were the worse it got. Measured at line
# 111 of a nine-kilobyte document: ten down-arrows took 11.2s with a selection
# up and 2.9s without the restriction -- about 1.1s of lag per keypress.
#
# By the time the cache is consulted the address is behind the gap and the
# text before the gap is contiguous, so the logical position is a subtraction
# rather than a count. SELPRIME then settles INSEL on arrival -- SELTEST
# cannot, because it only fires where RPOS lands exactly on a bound and a walk
# starting partway down never lands on one.
#
# THE FAILURE THIS CATCHES IS SILENT: get INSEL wrong and the selection simply
# does not draw, while every other selection test still passes because they
# select near the top where the slow path runs anyway.
#--------------------------------------
if section "selection above the viewport"; then
reboot
"$VII" caps true >/dev/null; "$VII" oa "<" >/dev/null; "$VII" caps false >/dev/null
"$VII" settle 4 >/dev/null
"$VII" caps true >/dev/null; "$VII" oa " " >/dev/null; "$VII" caps false >/dev/null
"$VII" settle 3 >/dev/null
for _i in $(seq 1 30); do "$VII" key "down arrow" >/dev/null; done
"$VII" settle 8 >/dev/null
snapshot

if [ "$(scrolltop)" -gt 0 ]; then
    ok "the view scrolled past the anchor"
else
    bad "the view scrolled past the anchor" "SCROLLTOP=$(scrolltop)"
fi


# Read the text page out of BOTH banks -- 80-column text interleaves, even
# cells in aux and odd in main -- and check the drawn cells are inverse.
# Inverse screen codes are below $80; ordinary high-ASCII text is $A0 and up.
"$VII" dump 0x0400 0x400 1 "$TMP/selaux.bin" >/dev/null
"$VII" dump 0x0400 0x400 0 "$TMP/selmain.bin" >/dev/null
if python3 - "$TMP/selaux.bin" "$TMP/selmain.bin" <<'PYEOF'
import sys
aux = open(sys.argv[1],'rb').read(); main = open(sys.argv[2],'rb').read()
bad = []
checked = 0
for r in (0, 1, 2, 3, 4):
    off = (r % 8) * 0x80 + (r // 8) * 0x28
    cells = []
    for c in range(40):
        cells.append(aux[off+c]); cells.append(main[off+c])
    while cells and cells[-1] in (0xA0, 0x20):   # trailing blanks, either ink
        cells.pop()
    if not cells:
        continue
    checked += 1
    plain = [b for b in cells if b >= 0x80]
    if plain:
        bad.append(f"row {r}: {len(plain)} of {len(cells)} cells not inverse")
if not checked:
    # every row blank means this proved nothing -- say so rather than pass
    print("no drawn cells on rows 0-4 at all"); sys.exit(1)
if bad:
    print('; '.join(bad)); sys.exit(1)
sys.exit(0)
PYEOF
then
    ok "every drawn cell above the anchor is selected"
else
    bad "every drawn cell above the anchor is selected" "the selection did not paint"
fi
# AND THE COST ITSELF. The old code was correct, only slow, so no correctness
# assertion can tell the two apart -- this one has to measure.
#
# Ten down-arrows go in as one burst, deep inside a nine-kilobyte document with
# a selection up, and the clock runs until the cursor has actually ARRIVED ten
# lines down. Timing to a known end state matters: an earlier version of this
# waited for the screen to "stop changing", which gives up early whenever a
# redraw takes longer than a poll, and it reported keystrokes as dropped that
# were merely still queued. Nothing is dropped -- Virtual ][ queues them. What
# the writer feels is the lag.
#
# Measured at line 111: 11.2s before the cache was allowed to work with a
# selection up, 2.9s after. The threshold sits well between.
"$VII" caps true >/dev/null; "$VII" oa "O" >/dev/null; "$VII" caps false >/dev/null
"$VII" await "OPEN:" 30 >/dev/null || bad "no open prompt for the deep document"
"$VII" text "DEEPDOC.TXT" >/dev/null; "$VII" line "" >/dev/null
"$VII" await "Paragraph 1." 240 >/dev/null || bad "DEEPDOC.TXT never loaded"
"$VII" settle 8 >/dev/null
"$VII" caps true >/dev/null; "$VII" oa ">" >/dev/null; "$VII" caps false >/dev/null
"$VII" settle 15 >/dev/null
for _i in $(seq 1 30); do "$VII" key "up arrow" >/dev/null; done
"$VII" settle 15 >/dev/null

# Esc FIRST. OA-Space is a latch, not a fresh start, and it was left on by the
# SAMPLE.MD half of this section -- pressing it again turned selecting OFF, and
# the burst below then measured ordinary cursor movement, which takes the fast
# path whatever this test is trying to prove. It passed either way and proved
# nothing until SELMODE was read out of the machine and found to be zero.
"$VII" key esc >/dev/null
"$VII" settle 4 >/dev/null
"$VII" caps true >/dev/null; "$VII" oa " " >/dev/null; "$VII" caps false >/dev/null
"$VII" settle 8 >/dev/null

# AT 1MHz, DELIBERATELY. The suite runs the emulator flat out, where the whole
# difference disappears. The machine is put back afterwards.
"$VII" speed regular >/dev/null
"$VII" settle 4 >/dev/null

before="$(linenum)"; target=$(( before + 10 ))
t0=$(python3 -c 'import time;print(time.time())')
osascript >/dev/null <<'ASEOF'
tell application "Virtual ]["
  tell (last machine)
    repeat 10 times
      type key down arrow
    end repeat
  end tell
end tell
ASEOF
for _i in $(seq 1 300); do
    [ "$(linenum)" = "$target" ] && break
done
t1=$(python3 -c 'import time;print(time.time())')
"$VII" speed maximum >/dev/null
took=$(python3 -c "print(f'{$t1-$t0:.1f}')")
if [ "$(linenum)" != "$target" ]; then
    bad "ten arrows land at depth" "cursor reached $(linenum), wanted $target"
elif python3 -c "import sys; sys.exit(0 if $took < 6.0 else 1)"; then
    ok "ten arrows land in under six seconds at depth (${took}s)"
else
    bad "ten arrows land in under six seconds at depth" \
        "took ${took}s -- the redraw is walking the document again"
fi

fi

#--------------------------------------
# Unsaved-changes guard. OA-Q sits beside OA-S and OA-O, so a slip must not
# cost the document. Runs before the file section because quitting ends the
# editor.
#--------------------------------------
if section "unsaved changes guard"; then
reboot_empty


assert_mod "a fresh document does not count as unsaved work"    no
ktext "x"
assert_mod "editing raises the unsaved star"                     yes
snapshot
assert_row "the star sits against the filename"       23 " UNTITLED.MD*"

"$VII" caps true >/dev/null
k oa "Q"
sleep 2; snapshot
assert_row "OA-Q with unsaved work asks instead of quitting"   23 "UNSAVED CHANGES"

"$VII" key esc >/dev/null; sleep 2
snapshot
assert_row "Esc returns to editing"                            23 "A-? HELP"
assert_mod "and the document is still modified"                 yes

# Cancelling the filename prompt must not quit either -- that is the path that
# would silently discard work.
k oa "Q"; sleep 1
"$VII" text "S" >/dev/null; sleep 2
"$VII" key esc >/dev/null; sleep 3
snapshot
assert_row "a cancelled save prompt does not quit"             23 "A-? HELP"
assert_mod "and still has unsaved changes"                      yes

k oa "S"; ktext "MODTEST.MD"
"$VII" line "" >/dev/null
"$VII" await "MODTEST.MD" 90 || bad "save never completed"
assert_mod "saving clears the star"                              no

# With nothing outstanding, OA-Q goes straight out to ProDOS. The save above
# just finished a disk write and the //e keyboard has no buffer, so let the
# machine come to rest first or OA-Q is dropped rather than queued.
"$VII" settle 2 >/dev/null
k oa "Q"
quit_seen=0
for _ in $(seq 1 30); do
    quitscr="$("$VII" screen 2>/dev/null || true)"
    case "$quitscr" in *SELECT*|*"S6,D1"*) quit_seen=1; break ;; esac
    sleep 1
done
if [ "$quit_seen" = 1 ]; then
    ok "OA-Q with no unsaved work quits immediately"
else
    bad "OA-Q with no unsaved work quits immediately" "screen: $(printf '%s' "$quitscr" | head -2 | tr '\n' '|')"
fi
fi

#--------------------------------------
# A final line with no trailing return. RENDER flushes that partial line at
# CURROW but used to leave CURROW pointing at it, so BLANKTAIL immediately
# erased the row RENDER had just drawn. Any full redraw lost the line, and only
# the one-row path put it back -- which is why it looked like a help screen bug
# and was really a rendering one. Reported on real hardware.
#--------------------------------------
if section "unterminated last line"; then
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
fi

#--------------------------------------
# A last line that fits, with no trailing break. WRAPCHECK reads ahead for a
# line end and caps that read at the end of the buffer -- and used to treat
# "ran out of buffer" as if it were "ran out of margin", so it wrapped a line
# that fitted perfectly well. Then it reflowed and walked the cursor back to
# the wrong place, and the next characters scattered.
#
# A one-line document is where anyone notices, because the condition is true
# from the first keystroke. But it is not really about one-line documents: it
# is the LAST line of any document that does not end in a break, which is every
# document ZipEdit saves.
#--------------------------------------
if section "short last line"; then
reboot_empty

ktext "the quick brown fox jumps over the lazy dog"
"$VII" caps true >/dev/null
k oa "A"; ktext "SHORT.MD"; "$VII" line "" >/dev/null
"$VII" await "SHORT.MD" 90 || bad "save never completed"
open_file "SHORT.MD"
"$VII" await "quick brown fox" 90 || bad "load never completed"
"$VII" caps false >/dev/null
"$VII" settle 2 >/dev/null
snapshot
assert_row   "the reloaded line is still one line"    0 "the quick brown fox jumps over the lazy dog"
assert_blank "nothing was wrapped below it"           1

# Walk into the line. This is the move that used to go nowhere.
for _i in 1 2 3 4 5 6 7 8 9 10; do k key "right arrow"; done
assert_lc    "the cursor walks along it"              1 11

ktext "ZZZ"
"$VII" settle 2 >/dev/null
snapshot
assert_row   "an insert lands under the cursor"       0 "the quick ZZZbrown fox"
assert_blank "and still nothing is wrapped"           1
assert_lc    "and the cursor followed the insert"     1 14
fi

#--------------------------------------
# Reflow while typing. Inserting into a filled paragraph pushes a word onto
# the next line, which pushes a word onto the one after it, all the way down.
# RTFWD stops that cascade as soon as a break lands back on a byte that
# already held one, which is only sound if the paragraph below really is
# untouched from there on -- so what is checked here is the whole paragraph,
# not the line that was typed into: every line still inside the margin, and
# not one character gained or lost.
#--------------------------------------
if section "reflow while typing" ; then
reboot_empty

# Joined text of rows 0..N, with the wrap breaks read back as the spaces they
# stood in for. Short words on purpose: they leave each line little slack, so
# the cascade runs far rather than dying on the first line below the insert.
joined() {
    sed -n "1,$(($1+1))p" "$SCREEN" | sed 's/ *$//' | tr '\n' ' ' \
        | sed 's/  */ /g; s/ *$//'
}

# ktext awaits the whole string on one row, which text this long never is --
# it wraps. Type it and wait for the screen to stop moving instead.
ktext_wrapped() { "$VII" text "$1" >/dev/null; "$VII" settle 4 >/dev/null; }

PARA="the quick brown fox jumps over the lazy dog and then keeps running for a very long time indeed "
ktext_wrapped "$PARA$PARA$PARA"
"$VII" settle 2 >/dev/null
snapshot
WANT="$(joined 5)"
[ -n "$WANT" ] || bad "the paragraph was typed" "nothing on screen"

# Into the middle of the first line, where the whole paragraph lies below.
"$VII" caps true >/dev/null; k oa "<"; "$VII" caps false >/dev/null
for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do k key "right arrow"; done
assert_lc    "the cursor is inside the first line"        1 21

ktext "ZZZ"
"$VII" settle 2 >/dev/null
snapshot
for r in 0 1 2 3 4; do
    assert_maxcols "line $r is still inside the margin"    "$r" 76
done
GOT="$(joined 5)"
if [ "${GOT//ZZZ/}" = "$WANT" ]; then
    ok "the paragraph below the insert is intact"
else
    bad "the paragraph below the insert is intact" \
        "expected: $WANT" "got:      ${GOT//ZZZ/}"
fi

# A word longer than the margin wraps with a break that stood in for nothing,
# which shifts every byte below it. Nothing after that can be compared against
# a position recorded before it, and reading one as a match would stop the
# reflow dead with the rest of the paragraph still over-long.
ktext_wrapped " aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "
"$VII" settle 2 >/dev/null
snapshot
# Strip the inserts back out -- the long word's own breaks stood in for
# nothing, so the runs of it rejoin with no space between them.
# Two or more a's in a row is the inserted word -- broken into runs by
# breaks that stood in for nothing. A single a is the word "a".
GOT="$(joined 6 | sed 's/ZZZ//g; s/a\{2,\}//g; s/  */ /g; s/ *$//')"
if [ "$GOT" = "$WANT" ]; then
    ok "the reflow ran on past a word longer than the margin"
else
    bad "the reflow ran on past a word longer than the margin" \
        "expected: $WANT" "got:      $GOT"
fi

# NOT asserted here: that these lines sit inside the margin. They do not --
# a word with no space in it breaks at column 77, one past the 76 the margin
# is set to, on a plain empty document with nothing inserted and on the build
# before any of the reflow work. That is its own defect and wants its own fix;
# writing it down as an expectation here would only make it permanent.
fi

#--------------------------------------
# New document. OA-N throws the whole document away, so it is guarded exactly
# as OA-Q is -- they share ASKUNSAVED, and these assertions are what stop the
# two from drifting apart.
#--------------------------------------
if section "new document"; then
reboot

ktext "zz"
assert_mod "editing before New raises the star"                  yes

"$VII" caps true >/dev/null
k oa "N"
sleep 2; snapshot
assert_row "OA-N with unsaved work asks first"                 23 "UNSAVED CHANGES"

"$VII" key esc >/dev/null; sleep 2
snapshot
assert_row "Esc returns to editing"                            23 "A-? HELP"
assert_row "and the document is untouched"                      0 "zz# Notes from the Apple"
assert_mod "and it is still modified"                           yes

# D discards. The buffer empties and the cursor goes back to the top.
k oa "N"; sleep 1
"$VII" text "D" >/dev/null
"$VII" settle 2 >/dev/null
snapshot
assert_blank "New empties the first row"                        0
assert_blank "and the rows below it"                           10
assert_mod "a new document counts as no unsaved work"           no
assert_lc "and the cursor sits at the top"                      1 1

# Nothing outstanding now, so OA-N must wipe without asking.
k oa "N"
sleep 2; snapshot
assert_row "OA-N with no unsaved work does not ask"            23 "UNTITLED.MD"

"$VII" caps false >/dev/null       # caps went on for the OA-N chords above
ktext "fresh"
snapshot
assert_row "typing starts the new document"                     0 "fresh"
assert_mod "and typing marks the new document modified"         yes
fi

#--------------------------------------
# Save and Save As. A named document saves back to its own file without asking;
# only a document that has never been named prompts. OA-A always asks, and the
# file it names becomes the one a later OA-S writes to.
#--------------------------------------
if section "save and save as"; then
reboot_empty

ktext "alpha"
"$VII" caps true >/dev/null
k oa "S"
sleep 2; snapshot
assert_row "the first save asks for a name"            23 "SAVE AS:"
ktext "AAA.MD"; "$VII" line "" >/dev/null
"$VII" await "AAA.MD" 90 || bad "first save never completed"
snapshot
assert_row "and the status row takes that name"        23 " AAA.MD"

# Saving again must not ask -- the row keeps the name rather than prompting.
"$VII" caps false >/dev/null; ktext " beta"
"$VII" caps true >/dev/null
k oa "S"
"$VII" settle 3 >/dev/null
snapshot
assert_row "saving again does not ask"                 23 " AAA.MD"

# OA-A always asks, and switches the document to the new file.
k oa "A"
sleep 2; snapshot
assert_row "OA-A asks for a new name"                  23 "SAVE AS:"
ktext "BBB.MD"; "$VII" line "" >/dev/null
"$VII" await "BBB.MD" 90 || bad "save as never completed"
snapshot
assert_row "and the document takes the new name"       23 " BBB.MD"

"$VII" caps false >/dev/null; ktext " gamma"
"$VII" caps true >/dev/null
k oa "S"
"$VII" settle 3 >/dev/null
snapshot
assert_row "a later OA-S writes to the new file"       23 " BBB.MD"
"$VII" caps false >/dev/null

# The proof is on the volume: the first file must NOT have the later edits.
# Virtual ][ buffers writes to a mounted image until it is ejected, so the
# volume shows stale contents until this happens.
osascript -e 'tell application "Virtual ][" to tell (last machine) to eject device "S6D1"' >/dev/null 2>&1 || true
aaa="$("$ROOT/tools/ac" -g "$IMAGE" AAA.MD 2>/dev/null | python3 -c '
import sys
raw = sys.stdin.buffer.read()[:16]
print("".join(chr(b & 0x7F) for b in raw))')"
bbb="$("$ROOT/tools/ac" -g "$IMAGE" BBB.MD 2>/dev/null | python3 -c '
import sys
raw = sys.stdin.buffer.read()[:16]
print("".join(chr(b & 0x7F) for b in raw))')"
# The silent OA-S went to AAA.MD, so it holds "alpha beta" -- and nothing after
# the Save As touched it again.
if [[ "$aaa" == "alpha beta"* && "$aaa" != *gamma* ]]; then
    ok "the silent save wrote to the original file"
else
    bad "the silent save wrote to the original file" "AAA.MD begins [$aaa]"
fi
case "$bbb" in "alpha beta gamma"*) ok "and the new file has every later edit" ;;
    *) bad "and the new file has every later edit" "BBB.MD begins [$bbb]" ;; esac
fi

#--------------------------------------
# Word count. A word is a run of non-blank characters, so the count is the
# number of blank-to-non-blank transitions. The sample document has 302 by the
# Mac's own reckoning, which is what makes this assertion worth anything.
#--------------------------------------
if section "word count"; then
reboot

"$VII" caps true >/dev/null; k oa "W"; "$VII" caps false >/dev/null
"$VII" settle 2 >/dev/null
snapshot
assert_row "OA-W counts the sample document"           23 " 302 WORDS"

# The gap sits at the cursor, so counting from the middle of the document is
# the case that proves the walk steps over it rather than counting through it.
"$VII" text "x" >/dev/null; "$VII" await "x" 60 >/dev/null
k key "down arrow"; k key "down arrow"; k key "right arrow"
"$VII" caps true >/dev/null; k oa "W"; "$VII" caps false >/dev/null
"$VII" settle 2 >/dev/null
snapshot
assert_row "and counts the same with the gap moved"    23 " 302 WORDS"

# An empty document, and the singular. The "x" above raised MOD, so OA-N asks
# before discarding -- answer it, or the guard swallows everything after it.
"$VII" caps true >/dev/null; k oa "N"; k text "D"; k oa "W"; "$VII" caps false >/dev/null
"$VII" settle 2 >/dev/null
snapshot
assert_row "an empty document has no words"            23 " 0 WORDS"

ktext "hello"
"$VII" caps true >/dev/null; k oa "W"; "$VII" caps false >/dev/null
"$VII" settle 2 >/dev/null
snapshot
assert_row "one word is singular"                      23 " 1 WORD "

ktext " there"
"$VII" caps true >/dev/null; k oa "W"; "$VII" caps false >/dev/null
"$VII" settle 2 >/dev/null
snapshot
assert_row "two words are plural"                      23 " 2 WORDS"
fi

#--------------------------------------
# Delete word. Mid-word it goes back to that word's start; after a word it
# takes the spaces and then the word. Ctrl-Delete cannot be used for this: the
# //e folds Ctrl into the character code and Delete arrives as $ff either way,
# so it is OA-Delete, alongside OA-arrows for word movement.
#--------------------------------------
if section "delete word"; then
reboot_empty

"$VII" caps true >/dev/null; k oa "N"; "$VII" caps false >/dev/null
ktext "one two three"
"$VII" oadel >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "deletes the word behind the cursor"         0 "one two "

# Sitting after a space now, so this one takes the spaces AND the word.
"$VII" oadel >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "and takes the spaces with the next word"    0 "one "
assert_lc  "the cursor follows it back"                 1 5

# Mid-word it stops at that word's start, leaving the rest of the word alone.
ktext "hello"
k key "left arrow"; k key "left arrow"
"$VII" oadel >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "mid-word it deletes back to the word start" 0 "one lo"

# A newline directly behind the cursor is simply joined, as Delete does.
# Return splits "one lo" at the cursor, so line 1 is "one " -- four characters,
# and joining puts the cursor at column 5, not at the end of the unsplit line.
"$VII" line "" >/dev/null; "$VII" settle 2 >/dev/null
assert_lc  "Return opens a second line"                 2 1
"$VII" oadel >/dev/null; "$VII" settle 2 >/dev/null
assert_lc  "and a word delete there just joins"         1 5
snapshot
assert_row "with the two lines back together"           0 "one lo"
fi

#--------------------------------------
# Prompt cursor. A prompt with no cursor reads as a label rather than a field,
# so there is a block where the next character will land. It is an inverse
# space, which the screen text readback renders as a plain space -- these
# assertions read the screen cell instead.
#--------------------------------------
if section "prompt cursor"; then
reboot_empty

"$VII" caps true >/dev/null
k oa "S"
"$VII" settle 2 >/dev/null
snapshot
assert_row   "the save prompt is showing"              23 "SAVE AS:"
# "SAVE AS: " is nine characters, so input starts at column 9.
assert_block "an empty prompt shows the block"          9

ktext "REPORT"
"$VII" settle 2 >/dev/null
assert_block "and it follows what was typed"           15

"$VII" del >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row   "delete removes the last character"       23 "SAVE AS: REPOR"
assert_block "and the block comes back with it"        14
# The block that was at 15 must be gone, not stranded there.
if "$VII" screen-raw | sed -n '24p' | cut -c1-20 | grep -q "REPORT"; then
    bad "the old block leaves no ghost" "row 23 still reads REPORT"
else
    ok "the old block leaves no ghost"
fi

"$VII" key esc >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "Esc puts the status row back"              23 "A-? HELP"

# Find prompts the same way, through the same routine.
k oa "F"
"$VII" settle 2 >/dev/null
snapshot
assert_row   "the find prompt is showing"              23 "FIND:"
assert_block "and it has a block too"                   6
"$VII" key esc >/dev/null; "$VII" settle 2 >/dev/null
"$VII" caps false >/dev/null
fi

#--------------------------------------
# The original //e. MouseText only exists on an Enhanced machine; the original
# keeps a second copy of inverse uppercase at $40-$5F, so every rule we draw
# comes out as a letter and the help screen is a fence of L's. The editor asks
# the CPU -- 65C02 means the enhancement, which came as a set -- and falls back
# to $20, an inverse space, which is a solid block on either machine.
#
# Virtual ][ offers no unenhanced //e, so this runs against a second image
# whose override byte is patched on (tools/forceplain.py). That exercises the
# drawing, which is all of it bar the detection itself; the one thing left for
# real hardware is whether a genuine original //e takes the 6502 branch.
#--------------------------------------
if section "original //e glyphs"; then
if [ ! -f "$PLAINIMAGE" ]; then
    bad "the plain-glyph image exists" "no $PLAINIMAGE -- run: make plaindisk"
else
"$VII" boot "$PLAINIMAGE" >/dev/null || { echo "boot failed"; exit 1; }
"$VII" await "ZipEdit" 120 >/dev/null || bad "the splash never appeared"
"$VII" text " " >/dev/null
"$VII" await "UNTITLED.MD" 60 >/dev/null || bad "the editor never opened"
"$VII" caps true >/dev/null
"$VII" oa "?" >/dev/null
"$VII" settle 3 >/dev/null
snapshot

# $4C is the thin rule on an Enhanced machine and an inverse L on an original.
# $20 is an inverse space on both.
assert_cell "the bottom border is a solid block, not a rule"  20 20 32
assert_cell "and so is the left edge"                          10  8 32
assert_row  "the help text itself is unchanged"                 4 "MOVING"

# The point of the substitution: a border with no letters in it. Row 20 was a
# run of inverse L's before this, which is what an original //e would show.
if "$VII" screen-raw | sed -n '21p' | grep -qE "[A-Za-z]"; then
    bad "the border carries no stray letters" "row 20: $("$VII" screen-raw | sed -n '21p' | cut -c1-40)"
else
    ok "the border carries no stray letters"
fi

"$VII" text " " >/dev/null
"$VII" await "CLIPBOARD" 60 >/dev/null || bad "a key never turned to page two"
"$VII" settle 2 >/dev/null
snapshot
assert_row  "page two turns and reads normally"                 9 "CLIPBOARD"
assert_cell "with a block border of its own"                   20 20 32
"$VII" text " " >/dev/null; "$VII" settle 2 >/dev/null

# The prompt cursor is the checkerboard on an Enhanced machine; here a block.
k oa "S"
"$VII" settle 3 >/dev/null
snapshot
assert_row  "the save prompt still opens"                      23 "SAVE AS:"
assert_cell "and its cursor is a block, not a checkerboard"    23  9 32
"$VII" key esc >/dev/null
"$VII" caps false >/dev/null
"$VII" settle 2 >/dev/null
fi
fi

#--------------------------------------
# The ][+ splash names a key that machine actually has
#
# splash.S is shared by every build, so a key name written into it is a claim
# about a keyboard we may not be sitting at. 1.2 shipped telling ][+ users to
# press Open Apple, a key that machine has never had, because nothing in the
# suite had ever looked at the 40-column build's screen. The hint lives with
# the keymap now -- keysiie.S and keys2p.S -- and this is what would have
# caught it.
#
# The split is by KEYMAP, not by width: edit40.S is 40 columns and still a //e,
# so it takes the Open Apple form. Only the ][+ build changes.
#
# Virtual ][ offers no ][+, but the ][+ build runs on a //e, which is enough to
# read a string back. That machine has no lowercase, so the splash comes back
# in upper case throughout.
#--------------------------------------
if section "the ][+ splash"; then
if [ ! -f "$TWOIMAGE" ]; then
    bad "the 40-column image exists" "no $TWOIMAGE -- run: make twodisk"
else
"$VII" boot "$TWOIMAGE" >/dev/null || { echo "boot failed"; exit 1; }
"$VII" await "ZIPEDIT" 120 >/dev/null || bad "the ][+ splash never appeared"
"$VII" settle 3 >/dev/null
snapshot

assert_row "the ][+ splash offers Esc-? for help"    20 "ESC-? TO GET HELP"
assert_row "and still names its version"             12 "VERSION 1.4"

# The Open Apple is a MouseText glyph, which reads back as "A" -- so the old
# hint would surface here as "A-?". Row 20 of the //e build says exactly that
# and is right to; on this machine it is a key that does not exist.
if sed -n '21p' "$SCREEN" | grep -q "A-?"; then
    bad "and not a key the ][+ does not have" "row 20: $(sed -n '21p' "$SCREEN")"
else
    ok "and not a key the ][+ does not have"
fi
fi
fi

#--------------------------------------
# The backtick key
#
# Markdown's code marker is the one character no Apple II keyboard can send --
# neither the //e nor the ][+ has a grave-accent key, which was found on the
# hardware and not here, because Virtual ][ will happily synthesise codes a
# real keyboard cannot produce.
#
# Everything else about the character already worked: the buffer holds it, the
# //e draws it, and the cheat sheet has carried one since it was written. So
# the fix is a key -- OA-' here, Esc ' on the ][+ -- and not a translation on
# the way to disk. That distinction is what the second assertion guards. A
# backtick that merely LOOKS right on screen still reaches the file as the
# wrong byte, and the file is the whole point of the editor.
#--------------------------------------
if section "the backtick key"; then
reboot_empty

k oa "'"
ktext "code"
k oa "'"
"$VII" settle 3 >/dev/null
snapshot
assert_row "OA-' types the marker the keyboard has no key for" 0 '`code`'

# $E0 is a backtick. Read the buffer rather than the screen: the display maps
# characters on their way out -- the ][+ build draws this one as an apostrophe
# because its ROM has no glyph for it -- so the screen cannot tell a real
# backtick from a stand-in. The file gets what is in the buffer.
_pregap
_tick="$(python3 -c "print(open('$TMP/pre.bin','rb').read().hex())")"
if [ "$_tick" = "e0e3efe4e5e0" ]; then
    ok "and the buffer holds the character itself, not a lookalike"
else
    bad "and the buffer holds the character itself, not a lookalike" \
        "buffer reads $_tick, wanted e0e3efe4e5e0" \
        "(backtick, c, o, d, e, backtick)"
fi

# Three of them open a fenced block. This inserts one character rather than
# wrapping the word the way Ctrl-B and Ctrl-I do, and a fence is why.
"$VII" line "" >/dev/null
k oa "'"
k oa "'"
k oa "'"
"$VII" settle 3 >/dev/null
snapshot
assert_row "and three of them make a fence" 1 '```'
fi

#--------------------------------------
# Text files this editor did not write. The buffer holds high ASCII and the
# line-end test is one compare against TEXTLO, so anything below $A0 ends a
# line. A .txt from a Mac or a PC is LOW ascii throughout, so every byte read
# as a line break and the document came up as thousands of empty lines --
# which on screen is indistinguishable from nothing at all. Reported from a
# //c under MAME: a 6.5K file, a blank screen.
#
# The fixtures are generated by tools/asciifixtures.py rather than committed:
# a file whose point is that it ends lines with CRLF is exactly the file a
# checkout normalises, after which the test passes for the wrong reason.
#--------------------------------------
if section "text from other machines"; then
reboot_empty

# Low ASCII with LF endings -- the reported case.
open_file "LFONLY.TXT"
"$VII" await "Line one" 90 || bad "the LF file never loaded"
"$VII" caps false >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "a low-ASCII LF file shows its text"       0 "Line one of the file."
assert_row "and breaks where the LF was"              1 "Line two of the file."
assert_blank "with nothing after it"                  2

# CRLF: the LF must not add a second break of its own.
"$VII" caps true >/dev/null
open_file "CRLFTXT.TXT"
"$VII" await "Line one" 90 || bad "the CRLF file never loaded"
"$VII" caps false >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "a CRLF file shows its text"               0 "Line one of the file."
assert_row "and CRLF counts as ONE break"             1 "Line two of the file."
assert_blank "so no blank line creeps in between"     2

# The Apple II convention, which must keep working exactly as it did.
"$VII" caps true >/dev/null
open_file "HIGHCR.TXT"
"$VII" await "Line one" 90 || bad "the high-ASCII file never loaded"
"$VII" caps false >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "high ASCII with CR still loads"           0 "Line one of the file."
assert_row "and still breaks on the CR"               1 "Line two of the file."

# Tabs become spaces, and control bytes are dropped rather than breaking lines.
"$VII" caps true >/dev/null
open_file "TABS.TXT"
"$VII" await "Tabs:" 90 || bad "the tab file never loaded"
"$VII" caps false >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "tabs come in as spaces"                   0 "Tabs:  here  and  here."
assert_row "and stray control bytes are dropped"      1 "After the junk."
assert_blank "leaving no phantom blank lines"         2

# A paragraph longer than 255 characters. CCOL is one byte and GAPLEFT
# decrements it per character, so HOMECURSOR walking back over a line this
# long wrapped the count around -- and WRAPALL, starting with CCOL already
# past the margin, broke the line at its FIRST character. "**Bold**" opened
# as "*" with "*Bold**" on the line below. Reported from a real document
# whose paragraphs were, quite reasonably, longer than 255 characters.
"$VII" caps true >/dev/null
open_file "LONGLINE.TXT"
"$VII" await "alpha bravo" 120 || bad "the long-line file never loaded"
"$VII" caps false >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "a paragraph over 255 chars keeps its first word" 0 "**Bold** alpha bravo"
if "$VII" screen-raw | sed -n '1p' | grep -qE '^\*[[:space:]]*$'; then
    bad "and is not broken at its first character" "row 0 is a lone asterisk"
else
    ok "and is not broken at its first character"
fi
fi

#--------------------------------------
# What a soft wrap becomes on the way out. A wrap that replaced a space is
# written back as a space -- except where nothing follows it. A paragraph that
# ends exactly at the wrap margin used to put a space before its own newline,
# and a document ending there gained a trailing space, because WRITERUN
# translated every soft wrap the same way regardless of what came next.
#
# Nothing caught it: the suite checked that files round-trip and never that
# they are TIDY.
#
# HONEST LABEL: this passes against the binary from BEFORE that fix too, so it
# is not a regression test for it. Typing cannot end a paragraph on a soft
# wrap -- the character that triggers a wrap always lands after it -- and I
# could not construct the case by deleting either. What this does guard is the
# general property: no space before a newline, none at the end. If some future
# change puts one there, this fails.
#--------------------------------------
if section "no litter in saved files"; then
reboot_empty

# Long enough to wrap at 76, so the paragraph ends on a soft wrap.
# Not ktext: it waits for the whole string on one row, and this one is
# deliberately long enough to wrap, so it never appears that way.
"$VII" text "the quick brown fox jumps over the lazy dog and keeps on running along until it wraps" >/dev/null
"$VII" await "wraps" 180 || bad "typing never completed"   # the last word: any
                                                          # longer a fragment
                                                          # may straddle the wrap
"$VII" settle 2 >/dev/null
"$VII" line "" >/dev/null            # one Return
"$VII" settle 2 >/dev/null
ktext "second paragraph"
"$VII" caps true >/dev/null
k oa "A"; ktext "TIDY.MD"; "$VII" line "" >/dev/null
"$VII" await "TIDY.MD" 90 || bad "save never completed"
"$VII" caps false >/dev/null
"$VII" settle 2 >/dev/null

osascript -e 'tell application "Virtual ][" to tell (last machine) to eject device "S6D1"' >/dev/null 2>&1
sleep 2
if "$ROOT/tools/ac" -g "$IMAGE" TIDY.MD 2>/dev/null > "$TMP/tidy.raw" && python3 -c '
import sys
raw = open(sys.argv[1], "rb").read()
text = "".join(chr(b & 0x7F) for b in raw)
assert raw, "empty file"
assert " \r" not in text, "a space before a return: " + repr(text)
assert not text.endswith(" "), "a trailing space at the end: " + repr(text[-30:])
assert "fox jumps" in text, "the soft wrap did not become a space: " + repr(text[:60])
assert "\r" in text, "the typed return is missing: " + repr(text)
' "$TMP/tidy.raw" 2>"$TMP/tidy.err"; then
    ok "a saved file carries no stray spaces"
else
    bad "a saved file carries no stray spaces" "$(cat "$TMP/tidy.err" | tail -2 | tr '\n' ' ')"
fi
fi

#--------------------------------------
# Long filenames. FNAME holds a whole PATHNAME, not a bare filename, so the
# field has to fit /VOLUME/FILE.MD. When even that is not enough the head is
# what goes: losing the star to a long path makes an unsaved document look
# saved, which is the worst way to lose it.
#--------------------------------------
if section "long filenames"; then
reboot_empty

ktext "x"
"$VII" caps true >/dev/null
k oa "S"; ktext "/ZIPEDIT/RICHSCAM.MD"; "$VII" line "" >/dev/null
"$VII" await "RICHSCAM" 90 || bad "save never completed"
"$VII" settle 2 >/dev/null
snapshot
assert_row "a whole pathname fits in the field"        23 " /ZIPEDIT/RICHSCAM.MD"

"$VII" caps false >/dev/null; ktext "y"
"$VII" settle 2 >/dev/null
snapshot
assert_row "and the star shows after it"               23 "/ZIPEDIT/RICHSCAM.MD*"

# Longer than the field: the leading directories go, the filename and star stay.
"$VII" caps true >/dev/null
k oa "A"; ktext "/ZIPEDIT/SUBDIRECTORY/ANOTHERONE/RICHSCAM.MD"; "$VII" line "" >/dev/null
sleep 3
"$VII" key esc >/dev/null; "$VII" settle 2 >/dev/null
"$VII" caps false >/dev/null
snapshot
assert_row "an over-long path keeps its tail"          23 "RICHSCAM.MD*"
fi

#--------------------------------------
# Status filename. The row carried UNTITLED.MD as static text, so it went on
# claiming that name after a save. It now shows whatever the last save or load
# used, and reverts when OA-N starts a fresh document.
#--------------------------------------
if section "status filename"; then
reboot_empty

snapshot
assert_row "an unnamed document reads UNTITLED.MD"     23 " UNTITLED.MD"

ktext "x"
k oa "S"; ktext "NAMED.MD"; "$VII" line "" >/dev/null
"$VII" await "NAMED.MD" 90 || bad "save never completed"
snapshot
assert_row "saving puts the name in the status row"    23 " NAMED.MD"
# The field is blanked past the end of the name, so no tail of the longer
# placeholder is left behind -- UNTITLED.MD is 11 characters, NAMED.MD is 8.
assert_row "and no tail of the placeholder survives"   23 "NAMED.MD    "

"$VII" caps true >/dev/null; k oa "N"; "$VII" caps false >/dev/null
"$VII" settle 2 >/dev/null
snapshot
assert_row "a new document goes back to UNTITLED.MD"   23 " UNTITLED.MD"
fi

#--------------------------------------
# Wrapping mid-line. The cursor's own column is not enough to go on: insert
# into the middle of a line and the cursor sits far short of the margin while
# the LINE runs past it. RENDER drops everything past column 80, so the text
# went off the right edge unseen.
#--------------------------------------
if section "mid-line wrap"; then
reboot

k key "down arrow"; k key "down arrow"
for i in $(seq 1 20); do k key "right arrow"; done
ktext "INSERTEDWORDSHERE "
"$VII" settle 3 >/dev/null
snapshot
assert_row     "the insert lands mid-paragraph"         2 "INSERTEDWORDSHERE"
assert_maxcols "and no row runs past the margin"        2 "$WRAPCOL"
assert_maxcols "nor the row below it"                   3 "$WRAPCOL"
assert_maxcols "nor the one after that"                 4 "$WRAPCOL"
# The word pushed off the end goes onto a line of its own; it is not dropped.
if grep -q "ProDOS" "$SCREEN"; then
    ok "the word pushed off the end is still on screen"
else
    bad "the word pushed off the end is still on screen" "ProDOS went missing"
fi

# The break reflows what follows it, so the overflow does not sit on a stub
# line of its own and no further word starts another. Reflowing the WHOLE
# paragraph per keystroke measured 7 chars/sec; reflowing only forward, from
# the cursor to the end, is what makes this affordable -- everything behind the
# cursor is already wrapped correctly.
snapshot
assert_maxcols "every row fits the margin while typing"     2 "$WRAPCOL"
assert_maxcols "including the one below"                    3 "$WRAPCOL"
assert_maxcols "and the one after that"                     4 "$WRAPCOL"
# In the stub version this row was just "ProDOS"; joined, it runs on.
assert_row     "the pushed word joins the line below"       3 "ProDOS 8 on an Enhanced"

# Nothing follows the cursor in an empty document, which is the case where the
# look-ahead length comes out zero. Getting that wrong hung the editor on the
# first keystroke.
new_doc
ktext "fresh"
"$VII" settle 2 >/dev/null
snapshot
assert_row "typing into an empty document still works"  0 "fresh"
assert_lc  "and the cursor keeps up with it"            1 6
fi

#--------------------------------------
# Open guards unsaved work. OA-O replaces the document wholesale, so it asks
# first -- it used not to, and silently threw the unsaved document away.
#--------------------------------------
if section "open guards unsaved work"; then
reboot_empty

ktext "unsaved edit"
assert_mod "the document is modified"                   yes
"$VII" caps true >/dev/null
k oa "O"
sleep 2; snapshot
assert_row "OA-O asks before replacing the document"   23 "UNSAVED CHANGES"

"$VII" key esc >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "Esc keeps the document"                     0 "unsaved edit"
assert_mod "and it is still unsaved"                    yes

# D means "go on without saving", so the open prompt follows it.
k oa "O"; "$VII" text "D" >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "D goes on to the open prompt"              23 "OPEN:"
"$VII" key esc >/dev/null; "$VII" settle 2 >/dev/null
snapshot
assert_row "and cancelling that keeps the document"     0 "unsaved edit"
"$VII" caps false >/dev/null
fi

#--------------------------------------
# xfer.sh unwrap, for files saved before the editor could tell its own wrapping
# from a typed return. Host side only -- no emulator involved.
#--------------------------------------
if section "xfer unwrap"; then
u="$TMP/legacy"; mkdir -p "$u"
printf 'A paragraph that the old\neditor wrapped at the margin.\n\n- list item one\n- list item two\n\n```\ncode line\nmore code\n```\n\n# A heading\nfollowed by prose.\n\nEnds with a hard break  \nnext line.\n' > "$u/legacy.md"
"$ROOT/tools/xfer.sh" unwrap "$u/legacy.md" >/dev/null 2>&1

if [ "$(sed -n '1p' "$u/legacy.md")" = "A paragraph that the old editor wrapped at the margin." ]; then
    ok "unwrap joins a wrapped paragraph"
else
    bad "unwrap joins a wrapped paragraph" "line 1: $(sed -n '1p' "$u/legacy.md")"
fi
if [ "$(grep -c '^- list item' "$u/legacy.md")" = "2" ]; then
    ok "and leaves list items on their own lines"
else
    bad "and leaves list items on their own lines" "$(grep -n 'list item' "$u/legacy.md" | tr '\n' '|')"
fi
if grep -qx "code line" "$u/legacy.md" && grep -qx "more code" "$u/legacy.md"; then
    ok "and passes fenced code through untouched"
else
    bad "and passes fenced code through untouched" "$(sed -n '/```/,/```/p' "$u/legacy.md" | tr '\n' '|')"
fi
if grep -qx "# A heading" "$u/legacy.md"; then
    ok "and never joins prose onto a heading"
else
    bad "and never joins prose onto a heading" "$(grep -n heading "$u/legacy.md")"
fi
if grep -q "hard break  $" "$u/legacy.md"; then
    ok "and respects a Markdown hard break"
else
    bad "and respects a Markdown hard break" "trailing double space was eaten"
fi

# Running it twice must be a no-op, not a slow drift.
cp "$u/legacy.md" "$u/once.md"
"$ROOT/tools/xfer.sh" unwrap "$u/legacy.md" >/dev/null 2>&1
if cmp -s "$u/once.md" "$u/legacy.md"; then
    ok "and is idempotent"
else
    bad "and is idempotent" "a second pass changed the file"
fi
fi

#--------------------------------------
# Wrapped for the screen, unwrapped in the file. The buffer marks its own wraps
# separately from the writer's returns, so a saved file carries only the
# returns that were typed and a loaded file gets our wraps put back.
#--------------------------------------
if section "unwrapped files"; then
reboot

# The sample's opening paragraph is four screen rows joined by our wraps.
snapshot
assert_row "the paragraph is wrapped on screen"        2 "This editor is written"
assert_row "across several rows"                       3 "Enhanced Apple //e with 128K"

"$VII" caps true >/dev/null
k oa "A"; ktext "UNWRAP.MD"; "$VII" line "" >/dev/null
"$VII" await "UNWRAP.MD" 90 || bad "save never completed"
"$VII" caps false >/dev/null
osascript -e 'tell application "Virtual ][" to tell (last machine) to eject device "S6D1"' >/dev/null 2>&1 || true

# In the file that paragraph is one line, and the returns that were typed --
# after the heading, between paragraphs, between list items -- are all still
# there.
"$ROOT/tools/ac" -g "$IMAGE" UNWRAP.MD 2>/dev/null > "$TMP/unwrap.bin" || true
python3 - "$TMP/unwrap.bin" > "$TMP/unwrap.txt" <<'PY'
import sys
raw = open(sys.argv[1], "rb").read()
sys.stdout.write("".join(chr(b & 0x7F) for b in raw).replace("\r", "\n"))
PY
para="$(sed -n '3p' "$TMP/unwrap.txt")"
if [ "${#para}" -gt 200 ]; then
    ok "the paragraph is one long line in the file"
else
    bad "the paragraph is one long line in the file" "line 3 is ${#para} characters: ${para:0:60}"
fi
if [ "$(sed -n '1p' "$TMP/unwrap.txt")" = "# Notes from the Apple //e" ]; then
    ok "and the typed returns survive around it"
else
    bad "and the typed returns survive around it" "line 1: $(sed -n '1p' "$TMP/unwrap.txt")"
fi
# A wrap inside an over-long word saves as nothing, not as a space, so no
# stray space can appear inside a word.
if grep -q "one screen row" "$TMP/unwrap.txt"; then
    ok "list items keep their own returns"
else
    bad "list items keep their own returns" "list item missing from the file"
fi

# Loading puts our wraps back, so the screen is wrapped again.
reboot
"$VII" caps true >/dev/null
open_file "UNWRAP.MD"
"$VII" await "Notes from the Apple" 120 || bad "load never completed"
"$VII" settle 3 >/dev/null
snapshot
assert_maxcols "the loaded paragraph is re-wrapped"     2 "$WRAPCOL"
assert_maxcols "on every row of it"                     3 "$WRAPCOL"
assert_row     "and it continues onto the next row"     3 "Enhanced Apple"

# Save it again: the round trip must not drift.
k oa "A"; ktext "UNWRAP2.MD"; "$VII" line "" >/dev/null
"$VII" await "UNWRAP2.MD" 90 || bad "second save never completed"
"$VII" caps false >/dev/null
osascript -e 'tell application "Virtual ][" to tell (last machine) to eject device "S6D1"' >/dev/null 2>&1 || true
"$ROOT/tools/ac" -g "$IMAGE" UNWRAP2.MD 2>/dev/null > "$TMP/unwrap2.bin" || true
if cmp -s "$TMP/unwrap.bin" "$TMP/unwrap2.bin"; then
    ok "save, load and save again is byte identical"
else
    bad "save, load and save again is byte identical" \
        "$(wc -c < "$TMP/unwrap.bin") bytes then $(wc -c < "$TMP/unwrap2.bin") bytes"
fi
fi

#--------------------------------------
# Reflow keeps the writer's returns. It used to flatten every break in the
# paragraph, which was harmless when they were all the wrapper's.
#--------------------------------------
if section "reflow keeps typed returns"; then
reboot_empty

"$VII" caps true >/dev/null; k oa "N"; "$VII" caps false >/dev/null
ktext "alpha"
"$VII" line "" >/dev/null; "$VII" settle 2 >/dev/null
ktext "beta"
"$VII" settle 2 >/dev/null
snapshot
assert_row "two lines, split by a typed return"         0 "alpha"
assert_row "the second on its own row"                  1 "beta"

"$VII" caps true >/dev/null; k oa "R"; "$VII" caps false >/dev/null
"$VII" settle 3 >/dev/null
snapshot
assert_row "reflow leaves the typed return alone"       0 "alpha"
assert_row "so the lines stay apart"                    1 "beta"
fi

#--------------------------------------
# File I/O. Round trips through a real ProDOS volume in the mounted image.
#--------------------------------------
if section "file i/o"; then
reboot true

# Disk operations take seconds of emulated time, and the Apple II keyboard has
# no buffer -- anything typed while ProDOS is working is simply dropped. So
# every file operation waits for its completion message before going on.
ktext "MARKER "
k oa "A"; ktext "T1.MD"; "$VII" line "" >/dev/null
# The busy notice is the feedback; completion is the status row coming back,
# and it comes back carrying the name that was just saved to.
"$VII" await "T1.MD" 90 || bad "save never completed"
snapshot
assert_row "OA-S returns to the status row when done" 23 "T1.MD"
assert_row "and the status row now names the saved file" 23 " T1.MD"

# Corrupt the buffer, then load it back and check the corruption is gone.
ktext "JUNKJUNK"
snapshot
assert_row "buffer modified before reload"            0 "MARKER JUNKJUNK# Notes"
open_file "T1.MD"
"$VII" await "T1.MD" 90 || bad "load never completed"
snapshot
assert_row "OA-O returns to the status row when done" 23 "T1.MD"
assert_row "loaded file replaced the buffer"          0 "MARKER # Notes from the Apple //e"

# $46 is ProDOS "file not found". The buffer must survive a failed open.
open_file "NOSUCH.MD"
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
fi

#--------------------------------------
# Paste keeps the hard wrap.
#
# Every other insert reaches the buffer one character at a time with a
# WRAPCHECK behind it. Paste lays down a whole clipboard between two of them,
# so before this it simply built a line as long as the clipboard and left it
# there. Two symptoms, and the second is the dangerous one:
#
#   * RENDER clips at the margin, so the overflow was in the buffer and not on
#     the screen. It came back when something reflowed, which made it look
#     like a redraw glitch rather than a wrap that never happened.
#   * Past 255 characters the one-byte column count wrapped. The status row
#     read C:1 with the cursor at the end of a 292-character line, and OA-R
#     then broke the paragraph after its FIRST character -- the same signature
#     as the unwrapped-file bug fixed in 1.1, reached from the other end.
#
# The assertions are against RAM, not the screen: a line running past the
# margin is exactly the thing the screen cannot show.
#--------------------------------------
if section "paste keeps the wrap"; then
reboot_empty

# Long enough to wrap, so ktext is no use here: it waits for its whole string
# to turn up on ONE row and this one cannot. settle covers it instead -- the
# screen changes on every keystroke, so it cannot go quiet until typing stops.
"$VII" text "Here's a paragraph that's five lines long. Here's a paragraph that's five lines long. " >/dev/null
"$VII" settle 5 >/dev/null
snapshot
assert_row "the test paragraph goes in"  0 "Here's a paragraph that's five"
assert_row "and wraps onto a second row" 1 "lines long."

"$VII" oa "<" >/dev/null; sleep 2
k oa "C"
"$VII" await "LINE COPIED" 60 || bad "OA-C never reported"
k ctrl E
k oa "V"
"$VII" settle 3 >/dev/null
snapshot

assert_maxcols "the pasted line does not overrun the margin"   0 "$WRAPCOL"
assert_maxcols "nor does the row it flows onto"                1 "$WRAPCOL"
maxline        "no line in the buffer runs past the margin"    "$WRAPCOL"
ccol_true      "the reported column is the real one"

# Four more onto the END OF THE SAME LINE, which is what makes this bite: a
# paste leaves the cursor on a fresh line below, so pasting again from where it
# lands grows a different line every time and never gets near 255. Stepping
# back up first is what Ben did by hand, and the third of these is the one that
# used to carry the line past 255 characters and wrap the column count.
PASTE_N="$(cliplen)"
PASTE_BEFORE="$(textcount)"
for i in 1 2 3 4; do
    k key "up arrow"
    k ctrl E
    k oa "V"
    "$VII" settle 3 >/dev/null
done
snapshot
maxline "repeated pastes still leave every line inside the margin" "$WRAPCOL"

# Stand at the end of that line before asking about the column. A paste leaves
# the cursor at the start of a fresh line, where the count and the buffer both
# read zero and agree about nothing; the disagreement only shows where the
# cursor actually sits past character 255. Getting there is also what runs
# CALCCOL over a line that long, which is where the count used to come back as
# zero and put the cursor at "column 1" of a 292-character line.
k key "up arrow"
k ctrl E
"$VII" settle 3 >/dev/null
ccol_true "and the column count has not wrapped round"

# The reflow is only allowed to move breaks about. Four pastes of a known
# length must leave exactly that many characters more than we started with --
# no word dropped on a wrap, none laid down twice.
PASTE_AFTER="$(textcount)"
PASTE_WANT=$((PASTE_BEFORE + 4 * PASTE_N))
if [ "$PASTE_AFTER" = "$PASTE_WANT" ]; then
    ok "four pastes add exactly four clipboards of text"
else
    bad "four pastes add exactly four clipboards of text" \
        "document holds $PASTE_AFTER characters, expected $PASTE_WANT" \
        "(started at $PASTE_BEFORE, clipboard is $PASTE_N)"
fi
fi

#--------------------------------------
# Another language
#
# The editor is built from lang/<code>.txt, and this checks the one thing that
# machinery is for: the words on screen change and nothing else does.
#
# It also checks the part that is easy to get wrong and impossible to see. The
# //e has no glyph for c, s or z with a caron, so those six letters are stored
# as the ASCII codes YUSCII gives them and turned back into UTF-8 on the way to
# the Mac. On SCREEN they are the substitutes -- Razli~ica -- and a test that
# only read the screen would pass just as happily if the file were spelt that
# way too. So the round trip is checked against the bytes, not the display.
#--------------------------------------
# Launched from BASIC rather than booted.
#
# ProDOS sets a prefix when it boots and launches the first .SYSTEM file, so a
# disk that boots straight into the editor is fine and this went unnoticed for
# four releases. BASIC.SYSTEM leaves NONE behind when it launches a SYS file
# with -NAME, and every relative pathname then fails with $40 -- invalid
# pathname syntax, which on screen is indistinguishable from having mistyped
# the filename.
#
# Needs BASIC.SYSTEM, so it runs against the release image rather than the
# build one, which mkdisk strips back to PRODOS plus the editor.
#--------------------------------------
if section "launched from BASIC"; then
if [ ! -f "$RELIMAGE" ]; then
    bad "the release image exists" "no $RELIMAGE -- run: make release"
else
"$VII" boot "$RELIMAGE" >/dev/null || { echo "boot failed"; exit 1; }
"$VII" await "ZipEdit" 120 >/dev/null || bad "the splash never appeared"
"$VII" text " " >/dev/null
"$VII" await "UNTITLED.MD" 60 >/dev/null || bad "the editor never opened"

# Out to the dispatcher, down one entry to BASIC.SYSTEM, and run it.
"$VII" caps true >/dev/null
"$VII" oa "Q" >/dev/null
if "$VII" await "BASIC.SYSTEM" 60 >/dev/null; then
    ok "OA-Q reaches the dispatcher"
else
    bad "OA-Q reaches the dispatcher" "no file list appeared"
fi
"$VII" key "down arrow" >/dev/null
"$VII" settle 2 >/dev/null
"$VII" line "" >/dev/null
if "$VII" await "PRODOS BASIC" 90 >/dev/null; then
    ok "and BASIC.SYSTEM starts from it"
else
    bad "and BASIC.SYSTEM starts from it" "never reached the ] prompt"
fi

# Back into the editor the way a user would, and open a RELATIVE name.
"$VII" line "-ZIPEDIT.SYSTEM" >/dev/null
"$VII" await "ZipEdit" 120 >/dev/null || bad "the editor never relaunched"
"$VII" text " " >/dev/null
"$VII" await "UNTITLED.MD" 60 >/dev/null || bad "the relaunched editor never opened"
"$VII" oa "O" >/dev/null
"$VII" await "OPEN:" 30 >/dev/null || bad "no open prompt after the relaunch"
"$VII" text "SAMPLE.MD" >/dev/null
"$VII" line "" >/dev/null
"$VII" settle 6 >/dev/null
snapshot
"$VII" caps false >/dev/null
assert_row "a relative name opens after launching from BASIC" 0 "Notes from the Apple"
if "$VII" screen | grep -q "ERROR \$40"; then
    bad "with no invalid-pathname error" "PRODOS ERROR \$40 -- the prefix is empty again"
else
    ok "with no invalid-pathname error"
fi
fi
fi

#--------------------------------------
if section "another language"; then
if [ ! -f "$SLIMAGE" ]; then
    bad "the Slovenian image exists" "no $SLIMAGE -- run: make LANG=sl disk"
else
"$VII" boot "$SLIMAGE" >/dev/null || { echo "boot failed"; exit 1; }
"$VII" await "ZipEdit" 120 >/dev/null || bad "the Slovenian splash never appeared"
"$VII" settle 3 >/dev/null
snapshot

# The name is not translated; everything round it is. ~ is c-with-a-caron.
# The translator folded the date into the version line and spent the line it
# freed on a credit, so row 14 is a name rather than a month.
assert_centred "the version line is Slovenian"   12 "Razli~ica 1.4 - avgust 2026"
assert_centred "and the translator is credited"  14 "Ben Long, prevod Janez Starc"
assert_row     "and the prompt"                  21 "pritisnite tipko"

"$VII" text " " >/dev/null
"$VII" await "BREZNASLOVA.MD" 60 >/dev/null || bad "the Slovenian editor never opened"
"$VII" caps false >/dev/null
"$VII" settle 2 >/dev/null
snapshot
assert_row "the untitled document has a Slovenian name" 23 "BREZNASLOVA.MD"
assert_row "and the status row is translated"           23 "PROSTO"

# The labels are translated too -- V: vrstica, S: stolpec -- and this is the
# assertion that matters, because the numbers are written OVER the row at the
# columns in src/geom.S. A translation that renames a label may not move it:
# the first edit that came back had a longer filename pushing both labels three
# columns right, which genlang.py caught only as a width error. Asserting the
# label against its digit catches it as what it is.
assert_row "and its labels are still on their columns" 23 "V:1    S:1"

# A string added after the first translation round, which is the case the
# machinery exists for: type something, then search for it from BELOW, which
# is the only way to force the wrap pass and its notice.
"$VII" caps false >/dev/null
"$VII" text "abc" >/dev/null; "$VII" settle 2 >/dev/null
"$VII" oa "F" >/dev/null
"$VII" await "POI" 30 >/dev/null || bad "the Slovenian find prompt never appeared"
"$VII" text "abc" >/dev/null
"$VII" line "" >/dev/null; "$VII" settle 4 >/dev/null
snapshot
assert_row "a new string reaches the screen translated" 23 "NADALJEVANO Z VRHA"

# The help screen comes from the same language file, through a different
# generator -- and that generator uses | = ~ and @ as its own box-drawing
# markup, which is what a caron collided with the first time.
"$VII" caps true >/dev/null
"$VII" oa "?" >/dev/null
"$VII" settle 3 >/dev/null
snapshot
assert_row "the help screen is Slovenian"         1 "UREJEVALNIK MARKDOWN"
assert_row "its sections are translated"          4 "PREMIKANJE"
assert_row "and a caron is a letter, not a rule"  7 "za~etek vrstice"
# The rules are on rows 0 and 2, not on a content row -- MouseText $4C reads
# back as "L". A content row carries only the two verticals, which read as "_".
if sed -n '1p' "$SCREEN" | grep -q "LLLLLLLLLL"; then
    ok "the box rule is still drawn"
else
    bad "the box rule is still drawn" "row 0: $(sed -n '1p' "$SCREEN")"
fi
if [ "$(sed -n '8p' "$SCREEN" | tr -cd '_' | wc -c | tr -d ' ')" = "2" ]; then
    ok "and a translated row still has both verticals"
else
    bad "and a translated row still has both verticals" \
        "row 7: $(sed -n '8p' "$SCREEN")"
fi
"$VII" text " " >/dev/null; "$VII" text " " >/dev/null
"$VII" caps false >/dev/null; "$VII" settle 2 >/dev/null

# And the bytes. A paragraph of Slovenian pushed to the image and pulled back
# has to come out the same, which is the promise the substitution rests on.
SLDIR="$ROOT/build/sltest"
rm -rf "$SLDIR" && mkdir -p "$SLDIR"
printf '# Naslov\n\nBesedilo z \305\276, \305\241 in \304\215.\nVelike: \305\275, \305\240, \304\214.\n' > "$SLDIR/proba.md"
cp "$SLIMAGE" "$ROOT/build/slround.po"
XLANG=sl "$ROOT/tools/xfer.sh" push "$ROOT/build/slround.po" "$SLDIR" >/dev/null 2>&1
ondisk="$("$ROOT/tools/ac" -g "$ROOT/build/slround.po" PROBA.MD | python3 -c "
import sys; print(''.join(chr(b & 0x7f) for b in sys.stdin.buffer.read()), end='')")"
if [ "${ondisk#*Besedilo z }" != "${ondisk}" ] && [ "${ondisk%%|*}" != "$ondisk" ]; then
    ok "the disk holds the substitute codes, not UTF-8"
else
    bad "the disk holds the substitute codes, not UTF-8" "got: $ondisk"
fi
rm -rf "$SLDIR/back" && mkdir -p "$SLDIR/back"
XLANG=sl "$ROOT/tools/xfer.sh" pull "$ROOT/build/slround.po" "$SLDIR/back" >/dev/null 2>&1
if diff -q "$SLDIR/proba.md" "$SLDIR/back/proba.md" >/dev/null 2>&1; then
    ok "and a round trip returns the Slovenian byte for byte"
else
    bad "and a round trip returns the Slovenian byte for byte" \
        "$(diff "$SLDIR/proba.md" "$SLDIR/back/proba.md" 2>&1 | head -4)"
fi

# The same mapping over an English file would turn every @ into a Z-caron, so
# it must not run unless it is asked for.
printf 'mail@example.com and a [link](url)\n' > "$SLDIR/plain.md"
rm -rf "$SLDIR/back2" && mkdir -p "$SLDIR/back2"
cp "$ROOT/build/ZIPEDIT.po" "$ROOT/build/enround.po"
"$ROOT/tools/xfer.sh" push "$ROOT/build/enround.po" "$SLDIR" >/dev/null 2>&1
"$ROOT/tools/xfer.sh" pull "$ROOT/build/enround.po" "$SLDIR/back2" >/dev/null 2>&1
if diff -q "$SLDIR/plain.md" "$SLDIR/back2/plain.md" >/dev/null 2>&1; then
    ok "and an English file is left alone"
else
    bad "and an English file is left alone" \
        "$(diff "$SLDIR/plain.md" "$SLDIR/back2/plain.md" 2>&1 | head -4)"
fi
fi
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
