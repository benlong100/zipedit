#!/bin/bash
# vii.sh -- drive Virtual ][ from the shell.
#
# Thin wrapper over the Virtual ][ AppleScript dictionary. Every subcommand
# targets `last machine`, and `boot` creates one if none exists. Nothing here
# ever closes a machine you didn't ask it to -- an open Merlin session is safe.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# A frozen machine refuses every command with "Cannot perform this command
# while the machine is frozen". That silently drops the keystroke and leaves
# every later assertion testing a machine that never received it -- one freeze
# swallowed 26 keys in a row and failed a test three sections downstream.
# Virtual ][ freezes on its own during long automated sessions, so thaw and
# retry once rather than lose the key.
run_osa() {
    local tmp rc
    tmp="$(mktemp)"
    OSA_OUT="$(osascript -e "tell application \"Virtual ][\"" -e "$@" -e "end tell" 2>"$tmp")" && rc=0 || rc=$?
    OSA_ERR="$(cat "$tmp")"; rm -f "$tmp"
    return "$rc"
}

as() {
    local rc=0
    run_osa "$@" || rc=$?
    if [ "$rc" -ne 0 ] && [[ "$OSA_ERR" == *frozen* ]]; then
        osascript -e 'tell application "Virtual ][" to unfreeze (last machine)' >/dev/null 2>&1 || true
        rc=0
        run_osa "$@" || rc=$?
    fi
    [ -n "$OSA_ERR" ] && printf '%s\n' "$OSA_ERR" >&2
    [ -n "$OSA_OUT" ] && printf '%s\n' "$OSA_OUT"
    return "$rc"
}

# Ensure a machine exists, then return a script fragment binding `m`.
ensure_machine() {
    osascript <<'EOF' >/dev/null
tell application "Virtual ]["
    if (count of machines) = 0 then
        activate
        make new AppleIIe
        delay 2
    end if
end tell
EOF
}

cmd="${1:-}"; shift || true

case "$cmd" in

# boot <image.po> -- insert into S6D1 and cold-restart (warm `reset` will NOT
# reboot from disk; it just drops into the monitor/BASIC).
boot)
    img="${1:?usage: vii.sh boot <image>}"
    img="$(cd "$(dirname "$img")" && pwd)/$(basename "$img")"
    ensure_machine
    "$0" thaw
    # The eject used to be a bare `try`. When it failed, `insert` threw
    # "the disk drive already contains a disk", and because that aborted the
    # script before `restart` ever ran, the caller carried on testing the
    # PREVIOUS session's machine. Retry the eject, and let a genuine failure
    # here abort with a non-zero exit rather than pretending we booted.
    osascript >/dev/null <<EOF
tell application "Virtual ]["
    set m to last machine
    tell m
        repeat 5 times
            try
                eject device "S6D1"
            end try
            delay 0.3
        end repeat
        insert "$img" into device "S6D1"
        delay 0.3
        restart
    end tell
end tell
EOF
    # `restart` resets both of these to the machine's saved defaults, so they
    # have to be set AFTER it, never before.
    "$0" speed "${VII_SPEED:-maximum}"
    "$0" kbdelay "${VII_KEYDELAY:-0.2}"
    echo "booted $img"
    ;;

# screen -- compact text (blank lines and trailing spaces stripped)
screen)
    as 'return (content of (compact screen text of (last machine))) as string'
    ;;

# screen-raw -- all 24 lines including blanks and trailing spaces
screen-raw)
    as 'return (content of (screen text of (last machine))) as string'
    ;;

# text/line/ctrl/oa/ca -- keyboard input
text) as "tell (last machine) to type text \"$1\"" ;;

# del -- the Delete key. Virtual ][ has no special key for it (only the four
# arrows and Esc), but DEL as a character code reaches the //e as $ff, which is
# what the keyboard encoder produces.
del)  as 'tell (last machine) to type text (character id 127)' ;;

# oadel -- Open-Apple with Delete, by the same character-code route.
oadel) as 'tell (last machine) to type open Apple (character id 127)' ;;
line) as "tell (last machine) to type line \"$1\"" ;;
ctrl) as "tell (last machine) to type ctrl \"$1\"" ;;
oa)   as "tell (last machine) to type open Apple \"$1\"" ;;
ca)   as "tell (last machine) to type solid Apple \"$1\"" ;;

# key <name> -- a special key, e.g. left, right, up, down, escape, return, tab
key)  as "tell (last machine) to type key $1" ;;

# dump <addr> <len> <bank> <outfile> -- read emulated RAM.
# bank 0 = main, bank 1 = auxiliary (where our text buffer lives).
dump)
    addr="${1:?}"; len="${2:?}"; bank="${3:-0}"; out="${4:?}"
    addr=$((addr)); len=$((len))
    as "return dump memory (last machine) into \"$out\" address $addr length $len bank $bank"
    ;;

# snap <file.png> -- screenshot
snap)
    out="${1:?}"
    as "return snap (screen picture of (last machine)) to \"${out%.png}\" format png"
    ;;

# await <substring> [timeout_s] -- block until the substring appears on screen.
# Deterministic, unlike `settle`; prefer this in tests. Exits 1 on timeout so
# a failing test fails the build rather than silently reading a stale screen.
await)
    want="${1:?usage: vii.sh await <substring> [timeout]}"; timeout="${2:-30}"
    deadline=$(( $(date +%s) + timeout ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if "$0" screen 2>/dev/null | grep -qF -- "$want"; then exit 0; fi
        sleep 0.5
    done
    echo "vii.sh await: timed out after ${timeout}s waiting for: $want" >&2
    echo "--- screen was ---" >&2; "$0" screen >&2 || true
    exit 1
    ;;

# settle -- wait for the screen to stop changing. Honours a minimum wait so the
# static boot-ROM splash isn't mistaken for a finished program.
settle)
    minwait="${1:-6}"; prev=""; stable=0
    start=$(date +%s)
    for _ in $(seq 1 60); do
        cur="$("$0" screen 2>/dev/null || true)"
        elapsed=$(( $(date +%s) - start ))
        if [ "$cur" = "$prev" ] && [ "$elapsed" -ge "$minwait" ]; then
            stable=$((stable+1)); [ "$stable" -ge 3 ] && break
        else
            stable=0
        fi
        prev="$cur"; sleep 0.5
    done
    ;;

caps) as "set caps lock of (last machine) to $1" ;;

# thaw -- Virtual ][ can leave a machine frozen (it refuses every command with
# "Cannot perform this command while the machine is frozen"). A frozen machine
# silently serves stale screens, so unfreeze before anything else.
thaw) osascript -e 'tell application "Virtual ][" to unfreeze (last machine)' >/dev/null 2>&1 || true ;;
speed) as "set speed of (last machine) to $1" ;;

# kbdelay <seconds> -- Virtual ][ paces AppleScript keystrokes itself. It
# defaults to 0.0, which injects keys faster than the program can read them;
# the surplus queues up, SURVIVES a restart, and dribbles into whatever runs
# next. Any non-zero value keeps the queue empty and makes bursts exact.
kbdelay) as "set keyboard delay of (last machine) to $1" ;;

*)
    sed -n '2,10p' "$0"
    echo
    echo "subcommands: boot screen screen-raw text line ctrl oa ca key dump snap await settle caps speed kbdelay del oadel thaw"
    exit 1
    ;;
esac
