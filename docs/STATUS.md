# Where ZipEdit stands

Written 2026-08-29, picking the project back up after a long detour into
ZipFiler. `docs/design.md` is the design and the reasoning; this is the state.

## Where the version stands

**1.3 is what is public. 1.4 is built, passing, and not yet released.**

| | |
|---|---|
| repository | <https://github.com/benlong100/zipedit> (public) |
| last release | `v1.3` — `ZipEdit-1.3.zip`, 172K, both machines |
| website | <https://trompingmarmots.com/AppSites/ZipEdit/> — still describes 1.3 |
| in the tree | 1.4: any language, Slovenian, and find wraps |
| suite | 311 assertions, 0 failures |

1.4 is the localisation plus the find work — see `CHANGELOG.md`, which has the
whole entry. Releasing it means `make dist`, a tag, and a line on the site.

**`make dist` had quietly stopped working and now does again.** It guards the
release by checking that the splash says the version in the filename, and it
did that by grepping `src/splash.S` — where the string has not lived since
localisation moved it into `lang/<code>.txt`. The guard could no longer find a
version anywhere and would have failed the next release for entirely the wrong
reason. It checks `lang/en.txt` now, and that `lang/sl.txt` carries the same
number, since a Slovenian splash a version behind is its own small lie.

Three builds, all from one source tree:

| target | source | 1.3 | 1.4 |
|---|---|---|---|
| Enhanced //e, 80 columns | `src/edit.S` | 10,668 | 10,827 |
| Apple ][+, 40 columns | `src/edit2p.S` | 9,728 | 9,984 |
| //e at 40 columns | `src/edit40.S` | 9,644 | 9,803 |

`make SRC=src/edit40.S NAME=ZIPEDIT40.SYSTEM` for that last one — it needs
`NAME` too, and only appears to work without it when nothing needs rebuilding.

The ][+ figure moves in steps of a page: `ds \` in `src/edit2p.S` pads to a
page boundary so `mainbuf.S` can take the high byte, so that build's size is
always a multiple of 256 and small changes do not show up in it at all.

## The localisation, committed

`0683beb` — 26 files, +1243/-607. What had been sitting uncommitted for weeks:

- `lang/en.txt`, `lang/sl.txt` — every user-visible string, one file per
  language, editable by somebody who does not read assembly
- `tools/genlang.py` → `src/lang.S`, and `tools/genhelp.py --lang` →
  `src/helpdata.S`, both generated on every build and neither committed
- `src/helpdata80.S` and `src/helpdata40.S` **deleted** — they were committed
  generated files, and generating them per build is what retired `checkhelp`
- `tools/xfer.sh` maps the six Slovenian letters to UTF-8 on the way to the Mac
  and back, gated on `XLANG`

`make` → English, byte-identical to 1.3. `make LANG=sl` → Slovenian.

`lang/sl-edit.txt` is committed beside `lang/sl.txt` on purpose: it is what
Janez Starc actually sent, so the diff between the two files is exactly the set
of changes he has not seen. There is one — see below.

## 1.4, committed and unreleased

`16834ce` — twelve files. Committed 2026-09-06; **not pushed, and not tagged or
released.** The tree is clean apart from `slovenian accents.png`, which is
untracked and has been left out of two commits now: it looks like a reference
image rather than source, and Ben has not said either way.

Four things are in it: **find wraps**, the **wrap notice** as a localisable
string, the **1.4 version bump**, and the **web address on the help screen**.

### The help screen carries the URL

`https://trompingmarmots.com/AppSites/ZipEdit/`, on the last content row of
page one so it reads just above the footer. It costs nothing — that row was
already there and blank, and the binary did not change size.

Deliberately **not** through `T()`: a URL is identical in every language, and
putting it in the language files would invite somebody to translate a path
that has to match the server exactly.

**80 columns only.** The 40-column page one is already eighteen content rows in
an eighteen-row space, and that screen folds case — lowercase draws as plain
capitals, a capital draws inverse — so `/AppSites/` reads correctly only to
somebody who knows the convention. `trompingmarmots.com/AppSites/ZipEdit/` is
37 characters and would fit the width if it is ever wanted there; finding it a
row is the problem, not the width.

### Find wraps


Ben asked for wrap-around on find. Two bugs turned up, both older than the
request and neither visible to the suite, which only ever checked that OA-F
lands on a match and that a missing pattern says so:

1. **OA-G never advanced at all.** The scan began at `GAPEND`, which is not one
   past the cursor but the character *under* it, so after a hit it re-matched
   at distance zero and the cursor stood still. Every pattern, every time.
   `FINDFIRST` (OA-F) and `FINDNEXT` (OA-G) now differ by one byte, `FSKIP`:
   a fresh pattern may match the character under the cursor — otherwise a
   document whose first word is the pattern reports NOT FOUND with the cursor
   sitting on it — and a repeat may not.
2. **A match lying against the end of the document was unfindable.** The text
   after the cursor always runs to `$BFFF`, so the last legal start is
   `BUFHI*256-FINDLEN`, and the limit was one short of it. Confirmed by
   building the committed version and watching it report NOT FOUND for a
   pattern the new one finds.

The wrap itself is a second pass. The gap splits the document in two, so pass
one is everything after the cursor (contiguous, `GAPEND` up) and pass two is
everything before it (contiguous, buffer base up to `GAPBEG`). Together they
cover the document exactly once.

Two things worth knowing about it:

- **A match straddling the gap is invisible to both passes** — one starting
  before the cursor and ending after it. Reaching it would mean testing for a
  discontinuity on every byte of every compare. It can only arise when the
  cursor has been parked inside an occurrence by hand, because a find always
  leaves it on a match's first character.
- **Wrapping backwards costs what OA-`<` costs.** `FMOVEL` walks the gap one
  character at a time, which is exactly what `KTOP` in `src/scroll.S` does, so
  a wrap to the top of a long document is as slow as jumping there — no worse,
  but no better.

+128 bytes on the //e build. The ][+ build did not change size at all: `ds \`
in `src/edit2p.S` pads to a page boundary and there was slack in the last page.

A hit in the second pass says " WRAPPED TO THE TOP" on the status row —
`MSGWRAPPED`, a proper localisable string in both language files. Without it a
cursor that jumps backwards reads as a find that went the wrong way. The
Slovenian is `" NADALJEVANO Z VRHA"` ("continued from the top") and is **my
guess, checked by nobody** — it is marked TODO in `lang/sl.txt` with a note
saying what sense is wanted, and it is the second thing to go back to Janez
alongside the `konč.` edit.

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
- **A second Slovenian review round went to Janez Starc on 2026-08-29** —
  `lang/sl.txt` plus `docs/note-to-janez.md` as the covering note, sent by Ben.
  **Awaiting his reply.** `lang/sl.txt`'s own header lists the same three
  things. Two are strings nobody who speaks Slovenian has
  seen — the `konč.` abbreviation made to get `CHEATTXT` down to 80 characters,
  and `MSGWRAPPED`, guessed outright — and the third is the word count, which
  the file cannot fix.

  Two questions go with it. **The discard key**: he flagged that `D = ZAVRZI`
  carries no mnemonic in Slovenian, and the letters are read by the program but
  are not fixed — binding `Z` for *zavrzi* is a small code change if he wants
  it. **His credit line**, which he wrote himself and which now sits on the
  splash screen.

  Two stale comments in `lang/sl.txt` were corrected before it goes back: the
  header still said "TRANSLATED BY A MACHINE AND NOT YET BY A SPEAKER", and a
  TODO still asked for a better idiom than `paint`, which he had already fixed
  to `razširi izbor` in both places. Sending a file that tells a contributor
  his work has not been looked at is worth avoiding.

  The file he has says `Različica 1.4`, so a long turnaround means his copy
  and the tree can drift apart on the version line.
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
