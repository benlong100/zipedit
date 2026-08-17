# Design: an 80-column Markdown editor for the Enhanced Apple //e

A text editor **written in** 6502 assembly, used to **write Markdown**. Files
are drafted on the //e and moved back to a Mac for publishing.

Target: Enhanced Apple //e, 128K, ProDOS 8, 80-column card.
Assembled with Merlin32 on macOS; Merlin 8 v2.48 kept as a dialect reference.

## 1. Goals and non-goals

The editor is for writing prose in Markdown. That shapes several decisions:

- **Prose, not code.** Long paragraphs, not short indented statements. Text is
  entered continuously and re-read as paragraphs.
- **Hard wrap on entry.** The editor inserts a real newline near column 76 as
  you type. Markdown renders a single newline inside a paragraph as a space, so
  hard-wrapped source renders identically to unwrapped source. This keeps one
  logical line equal to one screen row, which keeps the display layer, the
  cursor arithmetic, and the dirty-line redraw scheme all simple.
- **Round-trip fidelity.** Files must survive the trip to the Mac unchanged
  apart from the deliberate encoding conversion (§6). No reformatting on save.
- **The full ASCII punctuation set matters.** Markdown leans on backtick,
  asterisk, underscore, brackets, angle brackets, hash and pipe.

  **Display: confirmed.** `src/charset.S` writes ASCII `$20-$7F` to the
  80-column screen and the character ROM renders every one of them, backtick
  and tilde included. Reference screenshot at
  `tests/snapshots/charset-reference.png`. `$7F` shows as a checkerboard, as
  expected.

  **Keyboard: not yet confirmed on real hardware.** The //e was marketed as a
  full-ASCII keyboard, and Virtual ][ delivers every character, but an emulator
  will happily synthesise codes a physical keyboard cannot produce. Backtick in
  particular is worth checking on the real machine, since fenced code spans
  need it. If it turns out to be missing or awkward, the mitigation is a
  dedicated insert shortcut rather than a change to any other layer.

Not goals: soft wrap, word wrap toggling, multiple windows, proportional
display, undo beyond a single level. Soft wrap is the most likely future
addition and the hard-wrap design deliberately doesn't preclude it.

## 2. Memory map

ProDOS 8 loads a `SYS` file at `$2000` and enters at `$2000`.

### Main memory

| Range | Use |
|---|---|
| `$0000-$00FF` | Zero page. Editor working pointers, shared with ProDOS. |
| `$0100-$01FF` | Stack. |
| `$0200-$02FF` | Scratch / one-line staging buffer for aux transfers. |
| `$0300-$03FF` | Vectors and small routines. |
| `$0400-$07FF` | Text page 1, **main half** (odd screen columns). |
| `$0800-$1FFF` | ProDOS file I/O buffers (1K each, page-aligned). |
| `$2000-$5FFF` | Editor code and tables (~16K budget). |
| `$6000-$7FFF` | Line index (2 bytes per line). |
| `$8000-$B7FF` | Clipboard, find buffer, filename/directory cache. |
| `$B800-$BEFF` | Reserved. |
| `$BF00-$BFFF` | ProDOS 8 global page. MLI entry at `$BF00`. |

### Auxiliary memory

| Range | Use |
|---|---|
| `$0400-$07FF` | Text page 1, **aux half** (even screen columns). Untouchable. |
| `$0800-$BFFF` | **Text buffer.** 47,104 bytes. |

Hard-wrapped prose averages ~60 bytes per line, so the buffer holds roughly
780 lines — about 15 screens, or 8,000 words. Comfortably more than a single
article or chapter, which is the intended unit of work.

### The /RAM problem — solved

On a 128K machine ProDOS 8 automatically installs `/RAM`, a RAM disk that lives
in exactly the auxiliary memory we want for the text buffer. Left alone, `/RAM`
and the editor would silently corrupt each other. This was the biggest risk in
the memory plan.

The live ProDOS 2.4.3 global page, read out of a running machine rather than
recalled from documentation:

```
$BF26/$BF27  driver for slot 3 drive 2  = $FF00   <- /RAM
every unused slot                       = $DEA3   <- "no device connected"
$BF31 DEVCNT = $02                                <- count MINUS ONE
$BF32 DEVLST = $E0 $60 $BF                        <- $BF is /RAM
```

Two details that are easy to get wrong: `DEVCNT` is the device count *minus
one*, and `DEVLST` entries carry device ID bits in the low nibble (`$BF`, not
`$B0`), so slot/drive comparisons must mask with `$F0`.

`UNHOOKRAM` in `src/auxmem.S` points `$BF26` at the no-device routine — read
from slot 0 drive 1, which can never be a real device, rather than hardcoding
`$DEA3`, since it moves between ProDOS versions — then compacts `$BF` out of
`DEVLST` and decrements `DEVCNT`.

**Verified.** After the patch `DEVLST` is `$E0 $60`, and filling aux
`$0800-$BFFF` with a poison byte and dumping all 47,104 bytes back shows every
one intact. The regression suite asserts both, so a future change that
reintroduces `/RAM` fails the build.

## 3. Text representation

A **gap buffer** in auxiliary memory, with the gap at the cursor.

```
aux $0800                    gap start    gap end                  aux $C000
  |  text before cursor .......|<<<< gap >>>>|....... text after cursor  |
```

Insert is O(1): write one byte at the gap start, advance it. Delete is O(1):
move a gap edge. Only cursor movement costs anything, and it costs bytes
proportional to the distance moved — which for an editor is almost always one
line.

### Moving bytes in and out of aux — as built

Reads and writes are **not** symmetric, and this drove the implementation.

**Writing is easy.** `RAMWRT` redirects stores to `$0200-$BFFF` into aux while
instruction fetches follow `RAMRD`, which we leave alone. So an ordinary store
loop in main-memory code lands in aux with no special handling.

**Reading is not.** `RAMRD` redirects loads *and* instruction fetches. Code at
`$2000` that switched `RAMRD` on would fetch its own next instruction out of the
text buffer and die.

The original plan here was firmware `AUXMOVE` at `$C311` staging through main
memory. That was abandoned for something simpler: reads go through a
four-instruction stub copied into the **stack page** at `$0100`.

```
        sta RAMRDON
        lda (AUXPTR),y
        sta RAMRDOFF
        rts
```

`$0000-$01FF` follows `ALTZP`, not `RAMRD`, so a stub living there keeps
executing out of main memory while `RAMRD` points at aux. `$0100` is the last
address the stack would ever reach — the editor nests only a few frames deep.
The stub is position independent (zero page indirect and absolute I/O only), so
it is simply block-copied at startup.

This is both simpler and faster than `AUXMOVE` for the single-byte access that
gap shuffling and rendering actually do: roughly 20 cycles per byte against
about 150 for an `AUXMOVE` call's setup.

**One assumption, documented rather than defended against:** an interrupt taken
between `RAMRD` on and `RAMRD` off would run its handler out of aux. Nothing in
this configuration generates interrupts under ProDOS 8. If that ever changes,
wrap the stub in `PHP`/`SEI` … `PLP`.

`AUXMOVE` remains the right tool if bulk moves are ever needed — a jump to the
end of a large file currently costs one shuffle per byte. Measure before
optimising; the line index below is the better first move.

### Line index

Main memory `$6000-$7FFF` holds a 2-byte offset per line, so any line start is
one lookup rather than a scan. Offsets are buffer-relative; entries after the
gap are biased by the gap size, and the bias is applied at lookup rather than
rewritten on every keystroke. Only the tail of the index past the edit point
needs adjusting when a line is inserted or removed.

## 4. Display

The //e 80-column screen is interleaved: **odd columns live in main memory,
even columns in aux**, both at `$0400-$07FF`. With `80STORE` on (`$C001`),
`$C054`/`$C055` select which half a write lands in.

Row base addresses are the usual non-linear Apple II layout, so a 24-entry
lookup table of row bases is the right call rather than computing them.

Two options for putting characters on screen:

- **Firmware `COUT` through the 80-column card.** Simple, handles scrolling,
  but slow — far too slow for a full-screen redraw on every keystroke.
- **Direct writes to screen memory.** Roughly an order of magnitude faster,
  and we need that for smooth scrolling.

Decision: direct writes, with a dirty-line bitmap so a keystroke redraws only
the line it touched. Full redraws happen only on scroll.

### Scrolling

`SCROLLTOP` is the buffer line drawn on the first text row. `SCROLLFIX` runs
before each redraw: it finds the cursor's line with `CURLINE` and moves the
viewport the minimum needed to keep it visible.

Scrolling deliberately did **not** wait for the line index. `RENDER` already
walks the whole buffer, so skipping the lines above the viewport costs nothing
extra — `VIS` goes true once the walk reaches `SCROLLTOP` and stays true, which
makes it one byte compare per line rather than a 16-bit compare per character.

### 4a. Redraw cost — how it was fixed

Reported from real hardware: the first build was easy to out-type, and Bank
Street Writer III was not. Measured on the same document, sending a 222
character burst and counting what was absorbed in two seconds:

| version | per keystroke | sustained |
|---|---|---|
| original | 125 ms | 8 chars/sec |
| + incremental line number, one-row redraw | 20 ms | 51 chars/sec |
| + incremental column, block copy | 19 ms | 52 chars/sec |

**What actually mattered** was repainting one row instead of 23. The editor
knows the cursor's line without scanning, so ordinary typing rebuilds a single
line and draws a single row. Handlers opt in by setting `FASTDRAW`, and the
main loop takes the fast path only if `CURLNO` and `SCROLLTOP` both held still
— so a wrap, a newline, a scroll or a load all fall back to the full redraw
without anyone having to enumerate the dangerous cases.

**What barely mattered**, against prediction: maintaining the cursor column to
avoid two backward scans, and a block-copy stub that crosses banks once per
line instead of once per byte. Predicted 3-4x, delivered about 5%. Kept because
both remove work that grows with line length, but the honest lesson is that the
first change had already moved the bottleneck somewhere else.

**Caveat on all of these numbers:** they are emulator measurements. Virtual ][
waits for the program to read each key, so it can never drop a keystroke and
cannot reproduce the feel of falling behind on real hardware. The ratios should
hold — a real //e runs at the same 1.02 MHz — but the real machine is the
authority.

### Screen layout

```
row  1-22   text                          (23 when the cheat sheet is hidden)
row  23     cheat sheet   (toggled by Open-Apple-?)
row  24     status: filename, line/col, modified flag, free space
```

The status line is permanent. The cheat sheet is toggled with **Open-Apple-?**
and steals one row from the text area when shown; toggling it forces a full
redraw and a scroll adjustment if the cursor would fall off the bottom.

The cheat sheet is a single static 80-column string:

```
**bold** _italic_ `code` # H1 ## H2 - list 1. num > quote [txt](url) --- rule
```

Because hard wrap means one logical line is always one screen row, scrolling is
a matter of moving a window over the line index — there is no logical-to-visual
position mapping to maintain.

## 5. Keyboard

`$C000` holds the last key with bit 7 set when a key is ready; `$C010` clears
the strobe. The Open-Apple and Closed-Apple keys are **not** in the key byte —
they read as bit 7 of `$C061` and `$C062` respectively, and must be sampled at
the moment the key is read.

Arrow keys arrive as ordinary characters: left `$88`, right `$95`, up `$8B`,
down `$8A`.

### The Tab / Ctrl-I collision

The //e keyboard encoder maps **Tab and Ctrl-I to the same byte** (`$89`).
Software cannot distinguish them. Since Ctrl-I is wanted for italic, `$89` is
dispatched positionally:

- typed within a line's **leading whitespace** → indent two spaces
- typed **anywhere else** → italic

That preserves both behaviours in the contexts where each is actually wanted.

### Keymap

| Key | Action |
|---|---|
| arrows | move by character / line |
| OA-← / OA-→ | word left / word right |
| OA-↑ / OA-↓ | page up / page down |
| OA-< / OA-> | start / end of file |
| Ctrl-A / Ctrl-E | start / end of line |
| Delete | delete char left |
| Ctrl-D | delete char right |
| Ctrl-Y | delete to end of line |
| **Ctrl-B** | **bold** — wrap in `**` |
| **Ctrl-I** | **italic** — wrap in `_` (see collision above) |
| Tab (in leading whitespace) | indent two spaces |
| OA-C / OA-X / OA-V | copy / cut / paste |
| OA-F / OA-G | find / find again |
| OA-L | go to line |
| OA-R | reflow paragraph |
| OA-O / OA-S | open / save |
| OA-? | toggle cheat sheet |
| OA-Q | quit |

Dispatch is a table of (key, modifier mask, handler address) scanned linearly —
the table is short enough that a scan beats any cleverness. Open-Apple letters
are folded to uppercase on read so `OA-q` and `OA-Q` both dispatch.

### Known simplifications

- **No goal column.** Moving down through a short line loses the original
  column, because `KUP`/`KDOWN` recompute the column from wherever they land
  rather than remembering an intent. Every real editor keeps a sticky goal
  column; this one should too, and it is a small change once there is a line
  index to hang it off.
- **Emphasis is not word-aware yet.** `Ctrl-B` and `Ctrl-I` insert the markers
  and place the cursor between them, which is right when reaching for emphasis
  before typing a word but not when wrapping one already written. The
  selection-aware behaviour described above arrives with the editing-operations
  work.
- ~~Full redraw per keystroke.~~ **Fixed.** See §4a.

### Emphasis insertion

`Ctrl-B` and `Ctrl-I` behave the same way with different markers:

1. If there is a selection, wrap it.
2. Otherwise, if the cursor is on or immediately after a word, wrap that word.
3. Otherwise, insert both markers and place the cursor between them.

Applying emphasis to text already wrapped in the same marker removes it.

## 6. File I/O and getting files to the Mac — as built

On the //e: ProDOS TXT files (type `$04`), CR-terminated, high ASCII — the
native Apple II text convention. MLI calls used: `OPEN $C8`, `READ $CA`,
`WRITE $CB`, `CLOSE $CC`, `CREATE $C0`, `GET_FILE_INFO $C4`, `SET_PREFIX $C6`,
`GET_PREFIX $C7`, `ON_LINE $C5`.

An MLI call is `JSR $BF00`, then an inline command byte and a pointer to a
parameter block. Loading reads straight into the aux buffer in 1K chunks with
the gap parked at the end; saving writes out in two runs, before and after the
gap, so no compaction pass is needed.

Parameter blocks live in a dummy section rather than the code image: ProDOS
writes reference numbers and transfer counts into them, which would break the
immutable-image property the test suite relies on. They are initialised at
startup from a template that does live in the image.

Transfers are capped at 255 bytes so a transfer count always fits in one byte.
Next to a floppy seek the lost efficiency is irrelevant, and it removes a pile
of 16-bit arithmetic from the inner loop.

One asymmetry worth remembering: ProDOS pathnames are length-prefixed and
**low** ASCII, while everything else on this machine — screen codes, text
files, the buffer — is high ASCII. The filename prompt strips the high bit on
its way into `FNAME` and keeps it for the on-screen echo.

On the Mac: `make pull` extracts every TXT file from a `.po` image and converts
it to UTF-8 with LF line endings — clearing the high bit and translating CR to
LF. `make push` goes the other way. The same tooling works against real
hardware by `dd`-ing a CFFA CompactFlash card to a `.po` image first, so the
emulator and the real //e share one workflow.

**Virtual ][ buffers writes to a mounted image until it is ejected**, so
`make pull` ejects first. Verified end to end: text typed in the emulator,
saved with OA-S, pulled to the Mac, and read back as clean UTF-8 Markdown.

## 7. Testing

Virtual ][ exposes enough through AppleScript to test this properly, which is
unusual for 6502 work. `tools/vii.sh` wraps it:

```
tools/vii.sh boot build/EDIT.po
tools/vii.sh await "READY"
tools/vii.sh ctrl B                             # Ctrl-B
tools/vii.sh dump 0x0800 0x400 1 /tmp/buf.bin   # read the aux text buffer
tools/vii.sh screen
```

Because `dump memory` takes a bank number, tests assert against the **gap
buffer itself**, not just against what happens to be on screen. That is the
difference between testing an editor and testing a screen.

Display regressions use `snap` plus `same picture` against reference PNGs.

## 7a. Hard wrap — as built

`WRAPCHECK` runs after every printable insert. If the cursor has passed
`WRAPCOL` (76), `DOWRAP` scans back for the last space on the line and turns
that space into a newline, then returns the cursor to the character it was on.
No bytes are gained or lost, and the text either side is untouched. A word
longer than the margin has no space to break at, so it breaks at the cursor.

The wrap is an edit to the buffer, not a decoration on the display: the newline
is a real byte and it is what gets saved.

`REFLOW` (OA-R) rejoins and re-wraps the paragraph around the cursor. It walks
forward from `PARASTART`, turning each newline that has prose after it back
into a space, and re-breaking whenever the column passes the margin. A blank
line ends the paragraph, so neighbouring paragraphs and headings are left
alone.

Verified: typing a long run breaks at column 76 on a word boundary, and
reflowing a four-line paragraph reproduces it as 69/72/74-column lines with
the heading above and below untouched.

## 8. Build order

1. Character-set probe — confirm the //e can display and type every character
   Markdown needs. Cheap, and it de-risks everything above.
2. 80-column display layer — direct writes, row table, status line, cheat sheet.
3. Disconnect `/RAM`, prove aux is safe, stand up the gap buffer.
4. Keyboard and dispatch, including the `$89` positional split.
5. Editing operations, hard wrap on entry, reflow.
6. ProDOS file I/O, plus `make pull` / `make push`.
7. Emphasis shortcuts, find, clipboard, go-to-line.
