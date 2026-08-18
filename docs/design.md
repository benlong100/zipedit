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

### MouseText

The help screen's border is MouseText, which the alternate character set maps
onto screen codes `$40-$5F` on an Enhanced //e. The glyph assignments were
**probed, not recalled** — `src/mousetext.S` tiles each candidate eight times so
its shape is unmistakable:

| code | glyph |
|---|---|
| `$4C` | horizontal rule, high in the cell |
| `$53` | horizontal rule, mid cell |
| `$5C` | horizontal rule, low in the cell |
| `$5F` | vertical rule, clean when stacked |
| `$4E` | solid block |
| `$5B` | diamond |

A box uses `$5C` on top and `$4C` on the bottom: the low rule and the high rule
both meet the verticals, so the box closes. Reversing them leaves gaps.

**There are no corner or T-junction glyphs.** `$40-$4A` are the closed and open
apples, a pointer, an hourglass, check marks, a folder, and arrows — so a
corner is simply where a rule meets a vertical. Any chart showing MouseText
corners and T-junctions is for a different character set.

**Confirmed on real hardware.** `make probe` builds a standalone disk that
reports the ROM identification and dumps the glyphs; run on the real Enhanced
//e it gives `$FBB3=$06`, `$FBC0=$E0` and glyphs identical to Virtual ][. The
emulator is therefore a faithful proxy for this machine's character generator.

The Open Apple key is drawn with its own glyph (`$41`) rather than spelt "OA".
That required `INVBUF` to leave bytes with the high bit clear alone: ordinary
text always reaches it as high ASCII, so the sign bit separates text-to-invert
from raw screen codes, and an apple can sit in the inverse status bar without
being mangled into an inverse letter.

MouseText cannot be produced by `asc`, so help rows are emitted as raw screen
codes. Note also that Virtual ][ reads these codes back as the ASCII characters
sharing their value: `$5C` as backslash, `$4C` as `L`, `$5F` as underscore.
Tests assert against those.

The two rules are not what the first reading of the probe assumed. `$4C` is a
single stroke at the top of its cell. `$5C` is not a second rule at a different
height -- it draws **two** strokes, top and bottom of the same cell, so a row of
it renders as a double line. Building the box out of `$5C` laid a stray line
across the top of the screen; removing that row moved the pair under the title
instead. Every rule is `$4C` now. `$5F` draws its vertical at the left edge of
its cell, which is why the bottom rule is 63 cells rather than 64 -- a 64th runs
a whole cell past the right-hand vertical.

None of this was visible to the tests, which asserted that row N contained some
text. That stays true whether a rule doubles or overhangs. It took looking at
the screen, and the assertions now check the glyphs and the rule width directly.

**The help screen is two pages**, because one screen held every command and had
run out of room -- the selecting and clipboard columns had grown into each
other with no gap left between them. `OA-?` opens page one, a key turns to page
two, and a key leaves. Page one is what you need while typing (moving, editing,
selecting); page two is what you reach for deliberately (markdown, clipboard,
search, files, screen). Both pages are the same 21-row box, so turning the page
repaints in place, and the footer names the page and says what a key does next
-- otherwise nothing on screen would reveal that a second page exists.

The rows are generated by `tools/genhelp.py`, not hand-written. The layout is
text there and the screen codes fall out of it, with the column stops enforced:
a description that would overrun the border fails the generator rather than
shipping a mangled row, which is the mistake the one-page version made.

### Screen layout

```
row  1-22   text                          (23 when the cheat sheet is hidden)
row  23     cheat sheet   (toggled by Open-Apple-?)
row  24     status: filename, line/col, modified flag, free space
```

The status line shows the filename, a `MOD` indicator when the document has
the current filename, unsaved edits, the cursor's line and column, free space
and the help key. Line and column update live at no measurable cost: `CURLNO`
and `CCOL` are already maintained incrementally, so only the digit **cells**
are written -- never the whole row -- and the line digits are skipped when the
line has not changed. Measured 19.0 ms per keystroke against 19.2 ms without,
i.e. inside the noise.

A message (`PRODOS ERROR $46`) takes the row over and sets
`MSGSHOWN`, which suppresses digit updates; the next keystroke retires the
message and repaints the row.

**Disk operations show a busy notice.** Before `SAVEFILE` or `LOADFILE` runs,
`SHOWBUSY` takes the whole status row for a centred, inverse `-- SAVING --` or
`-- LOADING --`. On a floppy the drive is audible, but on a CompactFlash card
nothing moves and nothing sounds, so a silent multi-second pause is
indistinguishable from a hang.

This is hard to verify in the emulator: Virtual ][ completes a save in well
under one screen poll (~130 ms), so the notice is drawn and replaced between
samples. It was verified on real hardware instead, where a CompactFlash write
is long enough to read.

Because the notice is itself the feedback, a successful save or load says
nothing afterwards — it simply hands the status row back, which shows the
current line and column. Only failures produce a message.

Cutting follows the same rule for the same reason: the line visibly goes away,
so `OA-X` says nothing either. Copying still announces itself, because nothing
visible happens when a line goes to the clipboard — a message is the only sign
it worked.

The filename field is painted by `SHOWNAME` rather than baked into the status
template, which is what it used to be -- so the row went on reading
`UNTITLED.MD` after a save. It shows `FNAME`, whatever the last save or load
used, and falls back to the `UNTITLED.MD` placeholder while the document has no
name. `OA-N` clears `FNAME`, so a fresh document reads as untitled again. The
field is 12 columns, blanked past the end of the name so no tail of a longer
previous name survives.

**Prompts are different.** A prompt hands the status row back the moment it
ends, accepted or cancelled, rather than waiting for the next keystroke to
retire it. Otherwise the prompt text sits there until you press something
unrelated, and after a find or go-to you never see where you landed. Prompts
also show `ESC CANCELS` at column 66; input is capped at 45 characters so it
cannot run over the hint.

The status line is permanent. The cheat sheet is toggled with **Open-Apple-?**
and steals one row from the text area when shown; toggling it forces a full
redraw and a scroll adjustment if the cursor would fall off the bottom.

The cheat sheet is hidden by default and toggled with **OA-/**. It is a single
static string:

```
`code` # H1 ## H2 - list 1. num - [ ] todo - [x] done > quote [link](url) ---
```

Bold and italic are deliberately absent: they have dedicated keys (Ctrl-B and
Ctrl-I), so the space is better spent on syntax you have to type by hand — task
lists especially.

While the sheet is hidden, row 22 belongs to the document, so `REDRAW` must not
blank it. `TOGGLECHEAT` clears the row once when switching off, and after that
the text layer owns it.

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
| **Ctrl-I** | **italic** — wrap in `*` (see collision above) |
| Tab (in leading whitespace) | indent two spaces |
| OA-C / OA-X / OA-V | copy line / cut line / paste |
| OA-F / OA-G | find / find again |
| OA-L | go to line |
| OA-R | reflow paragraph |
| OA-N | new document — asks first if there are unsaved changes |
| OA-O / OA-S | open / save |
| OA-? | keyboard help, two pages -- a key turns, a key leaves |
| OA-/ | toggle cheat sheet |
| OA-Q | quit — asks first if the document has unsaved changes |

`OA-N` and `OA-Q` both discard the document outright, so they share one
guard, `ASKUNSAVED`. It returns carry set to go ahead and clear to stay put,
and the `S` branch only proceeds when the save actually cleared `MODFLAG` --
so a cancelled filename prompt or a write error keeps the document. Sharing
it is deliberate: a guard that only one of the two used would be the one you
found out about the hard way.

New resets what `START` sets up, minus the sample text. Nothing clears the
screen: `BLANKTAIL` already wipes text rows past the end of the buffer, and
an empty buffer means all of them.

Dispatch is a table of (key, modifier mask, handler address) scanned linearly —
the table is short enough that a scan beats any cleverness. Open-Apple letters
are folded to uppercase on read so `OA-q` and `OA-Q` both dispatch.

### Goal column

`KUP` and `KDOWN` aim for `GOALCOL`, captured the first time a run of vertical
moves begins and then left alone. Passing through a short line clamps the
cursor but not the goal, so the column comes back on the next long line. Any
other command ends the run and the next vertical move re-captures.

Two flags carry the run: `VERTMOVE` covers repeats inside a single keystroke,
since `KPGUP` calls `KUP` many times, and `WASVERT` carries it across
keystrokes.

Because `CCOL` is maintained incrementally, neither handler counts columns any
more — `BOL` plus a step over the newline is the whole journey, where the
original walked backwards through the line to measure it.

`RENDER` draws a line when it meets a carriage return, so a final line without
one is flushed separately at `:done`. That flush must advance `CURROW`:
`BLANKTAIL` clears from `CURROW` down, so leaving it pointing at the row just
drawn erased the line immediately. The symptom was a document losing its last
line on every full redraw and getting it back from the one-row path at the next
keystroke, which made it look like whatever had triggered the redraw was at
fault. Found on real hardware, reported as a help screen bug.

### Known simplifications

- **The clipboard is line based, not selection based.** With hard wrap a line
  is a natural unit and it needs no selection UI at all. Mark-and-region
  selection can be added later without changing the clipboard itself.
- **Emphasis does not toggle off.** Applying `Ctrl-B` to already-bold text
  wraps it again rather than unwrapping it.
- ~~Full redraw per keystroke.~~ **Fixed.** See §4a.

### Emphasis insertion — as built

`Ctrl-B` (`**`) and `Ctrl-I` (`*`) share one routine:

1. If the cursor is inside a word, run to the end of it first, so emphasis
   takes the whole word rather than the half behind the cursor.
2. Walk back to the start of that word, insert the opening marker, walk forward
   over the word, insert the closing marker.
3. With no word under the cursor, insert both markers and sit between them —
   which is what you want when reaching for emphasis before typing.

Marker characters count as word characters, so applying italic to `**bold**`
produces `***bold***` rather than something malformed — bold and italic share
the asterisk, and three is the correct Markdown for both.

**A trap worth recording:** none of these loops can count in `X`. `INSCHR`
reaches `PUTAUX`, which does a `TAX`, and `GAPLEFT`/`GAPRIGHT` do the same, so
any counter in `X` is destroyed on the first iteration. They all count in
memory.

### Unsaved changes

`MODFLAG` is raised by every operation that alters the text — `INSCHR`,
`DELBACK`, `DELFWD` — and cleared by a successful save or load. The startup
sample clears it too: a document the user did not write is not unsaved work.

OA-Q sits next to OA-S and OA-O, so a slip is easy and costs the whole
document. If `MODFLAG` is set, quitting asks first: **S** saves then quits,
**D** discards and quits, **Esc** returns to editing. Cancelling the filename
prompt does not quit either, since `KSAVE` clears `MODFLAG` only on a real
save, and the quit path re-checks it.

The flag is stored, never incremented — an `INC` would wrap to zero after 255
edits and read clean again.

This work also fixed a latent bug in `SAVEFILE`: a failed `WRITERUN` jumped
straight to the close-and-return-success path, so a write error reported
success. That mattered little when the result was only a status message; it
matters a great deal when quitting depends on it.

## 5a. Selection

The selection runs between an anchor and the cursor. Because the gap sits at
the cursor, **the selected text is always contiguous in auxiliary memory** —
either the bytes immediately before the gap or the bytes immediately after it.
Nothing has to cope with a range split across the gap, which makes copy a
single block move.

The anchor is a *logical offset*, not an aux address: an address stops meaning
the same byte as soon as the gap moves past it.

`DELSEL` is built from repeated `DELBACK`/`DELFWD` rather than by moving a gap
edge directly. Moving the edge would be O(1), but `CURLNO` and `CCOL` are
maintained incrementally and a selection may span newlines, so letting the
primitives do their own bookkeeping is worth the loop.

Selected text renders inverse. `SELTEST` runs for **every** byte the renderer
walks, including ones above the viewport that are never drawn, because the
boundaries are logical positions and `INSEL` has to flip at the right one. A
selection also forces a full redraw: it spans rows, so the one-row fast path
cannot be used while one is up.

### Why not shift-arrow

Shift-arrow was the obvious gesture and was built first. `$C063` is widely
documented as the //e's shift-key input, but **on real hardware it does not
change with the shift key**, so there is nothing to read. Virtual ][ meanwhile
reads it as permanently held, which made every arrow key select and broke
ordinary cursor movement.

Detection was calibrated against a startup sample rather than trusting the
documented polarity, and that is the only reason the attempt degraded to "never
fires" rather than "every arrow selects". The code is gone now; OA-Space is the
way in, which is one key and needs no modifier at all.

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
