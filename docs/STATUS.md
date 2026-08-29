# Where ZipEdit stands

Written 2026-08-29, picking the project back up after a long detour into
ZipFiler. `docs/design.md` is the design and the reasoning; this is the state.

## Shipped

**1.3 is public and live.**

| | |
|---|---|
| repository | <https://github.com/benlong100/zipedit> (public) |
| release | `v1.3` — `ZipEdit-1.3.zip`, 172K, both machines |
| website | <https://trompingmarmots.com/AppSites/ZipEdit/> |
| suite | 301 assertions, 0 failures |

1.3 added the backtick key (`OA-'` on the //e, `Esc '` on the ][+), fixed the
][+ splash naming an Open Apple key that machine has never had, and stopped a
backtick drawing as a blank on a ][+.

Three builds, all from one source tree:

| target | source | size |
|---|---|---|
| Enhanced //e, 80 columns | `src/edit.S` | 10,668 |
| Apple ][+, 40 columns | `src/edit2p.S` | 9,728 |
| //e at 40 columns | `src/edit40.S` | 9,644 |

`make SRC=src/edit40.S NAME=ZIPEDIT40.SYSTEM` for that last one — it needs
`NAME` too, and only appears to work without it when nothing needs rebuilding.

## Uncommitted, and this is the first thing to deal with

**The whole Slovenian localisation is sitting in the working tree.** Twenty
modified files, plus `lang/` and `tools/genlang.py` untracked. It is finished
and it passes; it has simply never been committed.

What it consists of:

- `lang/en.txt`, `lang/sl.txt` — every user-visible string, one file per
  language, editable by somebody who does not read assembly
- `tools/genlang.py` → `src/lang.S`, and `tools/genhelp.py --lang` →
  `src/helpdata.S`, both generated on every build and neither committed
- `src/helpdata80.S` and `src/helpdata40.S` **deleted** — they were committed
  generated files, and generating them per build is what retired `checkhelp`
- `tools/xfer.sh` maps the six Slovenian letters to UTF-8 on the way to the Mac
  and back, gated on `XLANG`
- `make LANG=sl` builds it; plain `make` is byte-identical to before

`make` → English, unchanged. `make LANG=sl` → `build/SL-ZIPEDIT.SYSTEM`,
10,703 bytes.

## The Slovenian, specifically

A contributor from a forum asked for it. Ben sent him the disk **and**
`lang/sl.txt`, because the file is the thing he can actually edit.

**The first round of corrections came back on 2026-08-29** as
`lang/sl-edit.txt` and is integrated. That file is kept as Janez Starc's
original; `lang/sl.txt` is the merged result. What the round changed, and what
it cost:

- Roughly twenty wording fixes, all of which fit. `tools/genhelp.py`'s overlap
  check passed every `HELP` line at both widths, including several that grew --
  he abbreviates with a trailing full stop (`kon. vrst.`, `odst.`) to make room,
  which is the right instinct.
- **The status row broke.** `BREZNASLOVA.MD` is three characters longer than
  `BREZIMNO.MD` and went in without giving three spaces back, so `V:` and `S:`
  slid three columns right. `genlang.py` caught it only as a width error; the
  real damage is that the numbers are written OVER the row at the columns in
  `src/geom.S`, so the digits would have landed on the labels. The labels are
  back on 38/45 and 17/23, and `tests/run.sh` now asserts `V:1    S:1` -- each
  label against its own digit, which catches a moved label as what it is.
- **`UNTLEN equ 11` in `src/equates.S` was a latent bug** and this exposed it.
  It is the length `display.S` draws the placeholder from, and `UNTITLED.MD`
  and `BREZIMNO.MD` are both eleven characters, so it had been right by
  coincidence. The status row showed `BREZNASLOVA` with the `.MD` missing. The
  length now comes out of `tools/genlang.py` into the generated `src/lang.S`,
  where it follows the string, and the equate is gone. genlang also validates
  `UNTITLED` now: 14 characters (the cell after it carries the star), a letter
  first, letters digits and full stops only.
- **One edit of mine is in his Slovenian and he has not seen it.** `CHEATTXT`
  came back at 82 characters against an 80-column row, clipping `l)` off
  `(url)`. Shortening `končano` to `konč.` is the two characters. He was
  already fixing this -- the machine translation was 89 and lost nine -- so it
  is a near miss, not a disagreement, but it should go back to him.
- `SPLDATE` now holds `Ben Long, prevod Janez Starc`: he folded the date into
  `SPLVER` and spent the freed line on a credit. It works, because `SPLMID`
  centres at run time. The key name is a small lie in the Slovenian file only.

Corrections come back as edits to `lang/sl.txt` and, `UNTLEN` aside, nothing
else had to change -- which is what the machinery is for.

Three things about it are still worth remembering:

1. **The //e has no glyph for `č š ž Č Š Ž`.** They are stored as the ASCII
   codes YUSCII gives them and turned back into UTF-8 by `xfer.sh`, so the
   screen shows `Razli~ica` and the file on the Mac says `Različica`. Two of
   the six deviate from YUSCII on purpose — `Š` and `ž` would have landed on
   Markdown's `[` and `` ` ``. See `docs/design.md` §10.
2. **`č` is `~`, which no //e keyboard can type.** Same gap that produced
   `OA-'` for the backtick. `\` and `|` are *believed* typeable and have not
   been confirmed on hardware; `make keyprobe` now names all six codes to
   check. This is the one open item that needs Ben's machine.
3. **The word count cannot be right in Slovenian.** It counts in four forms —
   1 beseda, 2 besedi, 3-4 besede, 5+ besed — and the code has two. No string
   fixes it; `src/edit_ops.S` would have to change.

## Known open items

- **Soft wrap** is named in `docs/design.md` §1 as the most likely future
  addition, and the hard-wrap design was built not to preclude it.
- **`OA-up` / `OA-down` cannot be tested.** Virtual ][ cannot send an arrow
  with Open-Apple held. The underlying handlers are covered by the arrow tests;
  the bindings themselves have only ever been checked by hand.
- **The original //e path is untested on hardware.** Virtual ][ offers no
  unenhanced //e, so `make plaindisk` patches an override byte
  (`tools/forceplain.py`) to exercise the drawing. Only the CPU detection
  itself still wants a real machine.
- **The website screenshots predate 1.3.** Nothing on the page shows a version
  number, so nothing is wrong — worth knowing if any get reshot.

## One thing learned elsewhere that lands here

While working on ZipFiler I extracted all 32 MouseText glyphs from this
project's own hardware probe (`tests/snapshots/mousetext-glyphs.png`) and found
that **`tools/genhelp.py`'s comment about corners is wrong**:

> nothing in MouseText closes that notch

There is a corner glyph — `$54`, bottom-left — and, more usefully, **`$5A`
draws a vertical down the RIGHT edge of its cell** where `$5F` draws down the
left. A stroke on a cell edge is a stroke on the boundary between two cells, so
a `$5A` vertical lands exactly where the next cell's `$4C` rule begins.

ZipEdit's help border happens to join correctly as drawn, so nothing is broken.
But the comment is misleading to the next person, and the box could be built
more deliberately. The full glyph table and the construction are written up in
`../a2-filer/docs/mousetext.md`.

## A known flaky test

`reflow while typing` fails roughly one run in three, and it is **the harness,
not the editor**. Seen 298/300 on 2026-08-29; the same tree passed 300/300
earlier and the section passes on its own every time it is re-run.

The diagnosis, so nobody re-derives it: the test types a 285-character
paragraph with `ktext_wrapped`, which is `type text` followed by `settle 4`.
`settle` gives up after 60 iterations of half a second. At the pinned keyboard
delay of 0.2s, injecting 285 characters takes about **57 seconds** — so the
settle loop and the typing finish at almost exactly the same moment, and which
wins is a coin toss.

When settle loses, `WANT` is captured mid-typing and comes out truncated
("...for a v"), while `GOT` after the insert is complete. The failure therefore
reads as *the reflow corrupted the paragraph* when in fact the baseline was
short.

The fix is to wait for a deterministic condition rather than for the screen to
stop moving — `textcount` reaching 285 would do it, the way `ktext` waits for
its string to appear. One or two lines in `tests/run.sh`, not yet done.

## The harness, briefly

`tests/run.sh` drives Virtual ][ through `tools/vii.sh`. Everything in
`CLAUDE.md`'s gotcha list is there because it cost a debugging round. Two to
add from recent work:

- **A mass-storage card in a higher slot changes the boot order.** A //e
  autoboots from the highest-numbered slot, so a SCSI card in slot 7 outranks
  the floppy in slot 6 and every emulator test fails at once while the disk
  image reads perfectly from the Mac. ZipFiler's `vii.sh boot` now types `PR#6`
  when it lands at a BASIC prompt; ZipEdit's has not been given that yet and
  will need it if Ben's machine keeps the card.
- **Do not edit `tests/run.sh` while it is running.** Bash reads a script
  incrementally, and an edit mid-run corrupts the parse.
