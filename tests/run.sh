#!/bin/bash
# tests/run.sh -- regression suite driven through Virtual ][.
#
# Each test boots the built image, sends keystrokes, and asserts against the
# emulated screen and against emulated RAM read back with `dump memory`.
# Assertions on RAM matter more than screen assertions for the text buffer,
# which lives in the aux bank and is only partially visible on screen.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VII="$ROOT/tools/vii.sh"
IMAGE="${IMAGE:-$ROOT/build/EDIT.po}"
BIN="${BIN:-$ROOT/build/EDIT.SYSTEM}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; shift; [ $# -gt 0 ] && printf '       %s\n' "$*"; fail=$((fail+1)); }

assert_screen_has() {
    if "$VII" screen | grep -qF -- "$2"; then ok "$1"; else
        bad "$1" "expected on screen: $2" "actual: $("$VII" screen | tr '\n' '|')"
    fi
}

# assert_mem <name> <addr> <len> <bank> <expected-file>
assert_mem() {
    local name="$1" addr="$2" len="$3" bank="$4" expect="$5"
    "$VII" dump "$addr" "$len" "$bank" "$TMP/mem.bin" >/dev/null
    if cmp -s "$TMP/mem.bin" "$expect"; then ok "$name"; else
        bad "$name" "RAM at $addr (bank $bank) does not match $expect"
        cmp "$TMP/mem.bin" "$expect" 2>&1 | head -3 | sed 's/^/       /'
    fi
}

echo "booting $IMAGE"
"$VII" boot "$IMAGE" >/dev/null
"$VII" await "HELLO FROM MERLIN32" 40 || { echo "boot failed"; exit 1; }

echo "toolchain"
assert_screen_has "program runs and prints its banner" "HELLO FROM MERLIN32 ON PRODOS 8"
assert_mem "loaded image matches build artifact" 0x2000 "$(stat -f%z "$BIN")" 0 "$BIN"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
