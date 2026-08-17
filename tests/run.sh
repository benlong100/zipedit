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
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; shift; [ $# -gt 0 ] && printf '       %s\n' "$@"; fail=$((fail+1)); }

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
assert_row   "heading renders"                      0 "# Notes from the Apple //e"
assert_row   "prose renders across full width"      2 "runs under ProDOS 8"
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

# The whole point of disconnecting /RAM: all 46K of aux must be ours. The
# editor poisons the buffer with $E5 at startup, so any byte that isn't $E5
# means something else is still living in auxiliary memory.
"$VII" dump 0x0800 0xB800 1 "$TMP/aux.bin" >/dev/null
if python3 -c '
import sys
d=open(sys.argv[1],"rb").read()
assert len(d)==0xB800, f"short dump: {len(d)}"
bad=[i for i,b in enumerate(d) if b!=0xE5]
assert not bad, f"{len(bad)} bytes not $E5, first at ${0x0800+bad[0]:04X}"
' "$TMP/aux.bin" 2>"$TMP/err"; then
    ok "all 46K of the aux text buffer is writable and intact"
else
    bad "all 46K of the aux text buffer is writable and intact" "$(cat "$TMP/err")"
fi

echo "chrome"
assert_row   "cheat sheet on row 22"               22 '**bold** _italic_ `code` # H1'
assert_row   "status line on row 23"               23 "UNTITLED.MD"
assert_width "status line fills the row"           23

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
