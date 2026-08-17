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

### The /RAM problem

**This is the one thing that can sink the whole memory plan.** On a 128K
machine ProDOS 8 automatically installs `/RAM`, a RAM disk that lives in
exactly the auxiliary memory we want for the text buffer. If we start writing
text into aux without dealing with this, `/RAM` and the editor will corrupt
each other.

The fix is to disconnect `/RAM` at startup: remove its entry from the ProDOS
device driver table in the global page, decrement the device count, and remove
it from the device list. The exact global-page offsets must be taken from the
ProDOS 8 Technical Reference rather than from memory — and then verified
empirically, which is cheap here:

```
tools/vii.sh dump 0xBF00 0x100 0 /tmp/globals.bin   # before
tools/vii.sh dump 0xBF00 0x100 0 /tmp/globals2.bin  # after our patch
```

Until that is confirmed working, treat the aux buffer as unproven. It is the
first thing to build after the display layer.

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

### Moving bytes in and out of aux

The complication: when `RAMRD` is switched to auxiliary memory, instruction
fetches from `$0200-$BFFF` also come from aux, so a copy loop living in main
memory cannot simply switch banks around itself.

The plan of record is to use the //e firmware `AUXMOVE` routine at `$C311`,
staging through the main-memory buffer at `$0200`. An aux-to-aux move becomes
aux → main → aux in chunks. `AUXMOVE` takes source start/end and destination in
`A1`/`A2`/`A4`, with the carry flag selecting direction.

If gap moves prove too slow, the escalation is a copy loop resident in the
language card at `$D000+`, which is banked by different soft switches and so
keeps executing while `RAMRD`/`RAMWRT` point at aux. That is faster but has to
coexist with ProDOS, which also lives there. Start simple; measure before
reaching for it.

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
the table is short enough that a scan beats any cleverness.

### Emphasis insertion

`Ctrl-B` and `Ctrl-I` behave the same way with different markers:

1. If there is a selection, wrap it.
2. Otherwise, if the cursor is on or immediately after a word, wrap that word.
3. Otherwise, insert both markers and place the cursor between them.

Applying emphasis to text already wrapped in the same marker removes it.

## 6. File I/O and getting files to the Mac

On the //e: ProDOS TXT files (type `$04`), CR-terminated, high ASCII — the
native Apple II text convention. MLI calls used: `OPEN $C8`, `READ $CA`,
`WRITE $CB`, `CLOSE $CC`, `CREATE $C0`, `GET_FILE_INFO $C4`, `SET_PREFIX $C6`,
`GET_PREFIX $C7`, `ON_LINE $C5`.

An MLI call is `JSR $BF00`, then an inline command byte and a pointer to a
parameter block. Loading reads straight into the aux buffer in 1K chunks with
the gap parked at the end; saving writes out in two runs, before and after the
gap, so no compaction pass is needed.

On the Mac: `make pull` extracts every TXT file from a `.po` image and converts
it to UTF-8 with LF line endings — clearing the high bit and translating CR to
LF. `make push` goes the other way. The same tooling works against real
hardware by `dd`-ing a CFFA CompactFlash card to a `.po` image first, so the
emulator and the real //e share one workflow.

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

## 8. Build order

1. Character-set probe — confirm the //e can display and type every character
   Markdown needs. Cheap, and it de-risks everything above.
2. 80-column display layer — direct writes, row table, status line, cheat sheet.
3. Disconnect `/RAM`, prove aux is safe, stand up the gap buffer.
4. Keyboard and dispatch, including the `$89` positional split.
5. Editing operations, hard wrap on entry, reflow.
6. ProDOS file I/O, plus `make pull` / `make push`.
7. Emphasis shortcuts, find, clipboard, go-to-line.
