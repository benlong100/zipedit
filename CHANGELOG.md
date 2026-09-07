# Changelog

## 1.4 — 29 August 2026

**Added: the editor can be built in any language, and ships in Slovenian.**

Every word the editor puts on the screen used to live in the source, spelt in
the transliteration this machine needs. Translating meant editing assembly, and
`Poi{~i` is a word nobody can proofread. The strings now live in
`lang/<code>.txt`, one file per language, and `tools/genlang.py` turns them into
assembly on every build. `make` is English and is byte-identical to 1.3;
`make LANG=sl` is Slovenian.

The //e's character generator is a ROM with 96 printable glyphs and no carons
among them, so the six letters Slovenian needs beyond ASCII travel as the codes
YUSCII — the Yugoslav ISO 646 variant — gave them, and `tools/xfer.sh` turns
them back into UTF-8 on the way to the Mac. The screen shows `Razli~ica` and the
file that reaches the Mac says `Različica`. Two letters deviate from YUSCII on
purpose: YUSCII puts `Š` on `[` and `ž` on a backtick, which are Markdown's link
and code markers.

The translation is by Janez Starc, who has had one pass over it. Two strings in
it are still marked TODO because they are not his.

**Added: find wraps round the end of the document.**

A search that reaches the end now starts again at the beginning rather than
stopping. The gap splits the document in two, so this is a second pass: the
first is everything after the cursor, the second everything before it, and
together they cover the document exactly once. A match found by the second pass
says `WRAPPED TO THE TOP` on the status row — a cursor that suddenly jumps
backwards reads as a find that went the wrong way unless the row explains
itself.

A match straddling the gap — one starting before the cursor and ending after it
— is invisible to both passes. Reaching it would mean testing for a
discontinuity on every byte of every compare, and it can only arise when the
cursor has been parked inside an occurrence by hand: a find always leaves it on
a match's first character.

**Added: the help screen carries the web address.**

`https://trompingmarmots.com/AppSites/ZipEdit/`, on the last row of page one,
just above the footer. It costs nothing — that row was already there and blank.

It is on the 80-column screen only. The ][+ page one is already eighteen rows
of content in an eighteen-row space, and that screen folds case: lowercase
draws as plain capitals and a capital draws inverse, so `/AppSites/` reads
correctly only to somebody who knows the convention.

**Fixed: find again never advanced.**

`OA-G` re-found the match the cursor was already sitting on, every time, for
every pattern. The scan began at `GAPEND`, which is not one past the cursor but
the character *under* it, so the first comparison it made was against the match
it had just landed on and the cursor never moved.

`OA-F` and `OA-G` now differ by one byte. A fresh pattern may match the
character under the cursor — otherwise a document whose first word is the
pattern reports `NOT FOUND` with the cursor sitting on it — and a repeat may
not.

The suite had a find test and it passed throughout, because it only ever
checked that `OA-F` lands on a match and that a missing pattern says so. It
never pressed `OA-G` twice.

**Fixed: a match lying against the end of the document could not be found.**

The text after the cursor always runs to `$BFFF`, so the last place a pattern
can start is `$C000` minus its length. The scan stopped one byte short of it,
which made the final characters of a document unsearchable. Confirmed by
building 1.3 and watching it report `NOT FOUND` for a pattern 1.4 finds.

**Fixed: the untitled document's name was cut short in another language.**

The length the status row drew it from was an assembly-time constant of 11,
which is right for `UNTITLED.MD` and was right for the first Slovenian name by
coincidence. A fourteen-character name showed as `BREZNASLOVA` with the `.MD`
missing. The length is generated with the string now, and the generator checks
the name besides: fourteen characters, because the cell after it carries the
unsaved-changes star, and ProDOS's own rules on top, because it becomes a real
filename the moment somebody saves without naming the document.

## 1.3 — 26 August 2026

**Added: a key for the backtick, which no Apple II keyboard can send.**

Markdown marks code with a backtick, and there is no grave-accent key on an
Enhanced //e. There is none on a ][+ either. The character arrived with the
IIgs, and every machine this editor targets predates it.

The gap was invisible from the Mac, because Virtual ][ delivers every character
whether or not the keyboard it emulates has a key for it — the design notes had
flagged the backtick as needing a check on real hardware for exactly that
reason, and the check found it missing.

Nothing else about the character was broken. The buffer holds it, files carry
it, the //e draws it, and the cheat sheet has displayed `` `code` `` since it
was written. Only the way in was missing, so the fix is a key rather than a
translation on the way to disk:

| machine | key |
|---|---|
| Enhanced //e | `OA-'` |
| Apple ][+ | `Esc '` |

The apostrophe is the key that most looks like what it produces, and it was the
only one still unbound on both machines. It **inserts one character** rather
than wrapping the word the way `Ctrl-B` and `Ctrl-I` do, so that three presses
open a fenced block and a lone marker stays possible.

The alternative was typing `''` and swapping it for a backtick when saving.
That was rejected because the buffer is the truth here — wrap, reflow, `CCOL`,
find and the word count all read it, and a save-time swap puts the file out of
step with everything the editor measured. A hard wrap bakes the breaks in, so a
line arranged against the margin would ship a character short for every `''` on
it. Loading is worse: translate back, and a genuine `''` in a file this editor
did not write becomes a backtick the next time you save.

**Fixed: the ][+ splash screen named a key that machine has never had.**

The 40-column splash offered `OA-?` for help. The ][+ has no Open Apple key, so
it advertised something unreachable — and drew the glyph as a bare `A`, since
that machine has no MouseText either. It now reads `Esc-?`, which is bound
there, alongside the single-keystroke `Ctrl-P`.

`splash.S` is shared by every build, which is how a key name written into it
became a claim about a keyboard the reader might not own. The hint now lives
with the keymap, in `keysiie.S` and `keys2p.S`. That split is by keymap and not
by screen width on purpose: the 40-column //e build is 40 columns and still a
//e, and takes the Open Apple form.

**Fixed: a backtick was invisible on a ][+.**

That character generator holds 64 shapes and a grave accent is not among them,
so `$E0` drew as a blank: a code span read as " code " with nothing marking
either end. This affected **any file containing a backtick**, not only text
typed on that machine. `FOLDCASE` now draws it as an apostrophe — the nearest
shape the ROM has, and the key the writer pressed to get it.

**Also:** both 40-column help pages were already at their 18-row limit, so the
two delete rows merged into `ctrl-z d — delete left/right`, matching how the
other paired keys were already written.

The regression suite is 287 assertions, up from 281, and now boots the
40-column build to read its splash — nothing had ever looked at that build's
screen, which is why the wrong key shipped in the first place.

## 1.2 — 24 August 2026

**Fixed: pasting at the end of a line left text unwrapped, and past 255
characters it corrupted the cursor.**

Reported from a real Enhanced //e: type a paragraph, copy a line, move to the
end of the line and paste, and the pasted text runs off the first line with the
cursor stranded partway down the screen. `OA-R` puts it right, which is what
made it look cosmetic.

It was not. Hard wrap on entry rests on `WRAPCHECK`, which runs after every
printable insert — and holds only because every insert passes it one character
at a time. Paste does not: `KPASTE` lays down a whole clipboard, up to 1,024
bytes, between one wrap check and the next, and nothing re-wrapped afterwards.
`RENDER` clips at the margin, so the overflow sat in the buffer and never
reached the screen at all.

Past 255 characters it stopped being cosmetic. `CCOL` was one byte, on the
reasoning written into `HOMECURSOR`'s own comment — that a line that long
"cannot happen while editing, since nothing survives longer than the wrap
margin". Paste is the counter-example. Three pastes onto one line, and the
editor reported the cursor at **column 1 of a 292-character line**; `OA-R` then
broke the paragraph after its first character, `**History Duel**` opening as
`*` — the same signature as the unwrapped-file bug fixed in 1.1, arrived at
from the opposite direction.

`CALCCOL` made it worse by lying about it. Its comment claimed to "saturate
rather than wrap round", but `inc TMPC / beq :done` leaves the loop *on* the
wrap and returns **zero**, not `$ff`. So the column did not merely overflow, it
came back as 1.

Paste now reflows the paragraph once when it is done, through `RTFLOW` — which
was already written, and which nothing had ever called. A `WRAPCHECK` per
pasted character would be the faithful fix and is far too slow: it stages the
rest of the line out of aux on every call, so a 255-byte paste would pay that
255 times over.

`CCOL` is two bytes now and `CALCCOL` counts in sixteen. Every margin test
reads the high byte first, so none of them can be fooled by a wrapped count
again.

**Faster: typing into the middle of a paragraph no longer loses whole words.**

Reported from a real Enhanced //e: inserting text in the middle of a six-line
paragraph drops the occasional character, and in a twelve- or twenty-line one
it drops whole words.

Not a uniform slowdown. Roughly one keystroke in six fills the line and has to
break it, and that keystroke pays for reflowing everything below it to the end
of the paragraph. The Apple II keyboard latches exactly ONE key, so anything
struck during that is not delayed, it is gone — and the stall was word-sized,
so what went missing was a word.

Measured at 1MHz, typing mid-paragraph:

| | before | after |
|---|---|---|
| twelve-line paragraph | 83 ms/char | 40.5 |
| twenty-line paragraph | 132.5 ms/char | 61 |
| where nothing wraps at all | 21 ms/char | 21 |

**The redraw was never the problem**, though for two releases it looked like
it. A full `RENDER` measures 2-3ms. Every figure suggesting otherwise — the
table in 1.1 among them — was taken with the arrow keys, and an arrow press
moves the cursor a whole line as well as repainting; the movement is nearly all
of it. Benchmark the repaint with a key that repaints and does nothing else: an
unbound one, which `DISPATCH` ignores while the main loop still draws.

What it actually cost was transport. A reflow's real work is tiny — a `SOFTCR`
stood in for a space, so turning it back is a ONE BYTE overwrite, and breaking
a line at a space is another. But `REFLOWHERE` dragged the gap through the
whole paragraph a byte at a time and `RTFWD` dragged it all the way back, each
step a banked aux read AND a banked aux write: some 1,400 accesses to change
about ten bytes.

`RTFAST` does the same job by reading. It scans forward with `AUXPTR`, counts
columns as it goes, and pokes only the bytes that differ — one read per byte,
no write-back, and no walk home, because the gap never moves and `CCOL` and
`CURLNO` come out untouched. Two cases are not byte-preserving and hand back to
the old walking `RTFWD`: a `SOFTWD`, which stood in for nothing so removing it
shifts everything below it, and a line with no space to break at. Both are
rare — zero fallbacks over a thirty-character burst — and the walking version
stays as the proven answer for them.

**And the keyboard is buffered**, which is what actually stops the losses.
Making the reflow faster has a floor: hard wrap means inserting a character
genuinely shifts every line below it, so the cost is proportional to what
follows the cursor no matter how tight the loop. A survey of what the machine's
own word processors did settles the question — Apple Writer II and Cut & Paste
never drop a character and both let the redraw fall behind instead. So: catch
the keystroke first, and let the screen catch up.

`KBPOLL` runs inside the reflow and puts any waiting key into a sixteen-deep
ring; `GETKEY` drains the ring before it looks at the hardware. During a
thirty-character burst into a twenty-line paragraph, **eighteen keys were
caught mid-reflow** — the eighteen that used to be thrown away. When the ring
is full the key stays in the latch, which is exactly where it would have been
lost before, so a full ring is never worse than none.

Two details that were not optional. The Open-Apple state is a soft switch
rather than part of the character, so it is only true at the instant the key
arrives: each ring entry carries its own modifier, or an `OA-S` struck during a
reflow would come back as a literal `S` in the document. And the capture is
machine-specific, because `$C061` is a floating paddle button on a ][+ and
reads as permanently pressed — the trap already documented in `keys2p.S`.

`KBNEXT` reports the key `GETKEY` will hand over next, ring or latch, without
consuming it. Anything asking "is the writer still typing?" has to come through
it: once something else is emptying the latch, a bare `lda KBD` finds nothing
waiting even mid-burst.

**And the tidy waits while you are mid-word.** If a key is already waiting and
it is a printable character, the pushed word is left on a short line and the
reflow happens at the next pause — or before the next key that is not
printable, so an arrow can never carry the cursor away and strand the mess. A
document therefore cannot be saved ragged, and nothing reaches the file
differently in any case: a reflow only moves breaks about.

Which walk finishes a deferred tidy depends on how many breaks are owed.
`RTFWD` stops as soon as a break lands back where one already was, which proves
the rest of the paragraph is right — but only if it was right to begin with.
One deferred break leaves everything below it untouched, so that still holds;
two or more and it does not, and the early stop strands the rest. `RTFWDALL` is
the same walk without the early stop.

Two approaches were measured and thrown away, which is worth recording so they
are not tried again. Coalescing the redraw saved nothing, because the redraw
was never the cost. Interrupting the reflow when a key arrives measured 179ms a
character against 83 for doing nothing at all: stopping works, but the walk
restarts from the cursor every time, so it re-covers its own ground and the
whole thing turns quadratic.

**Fixed: a long line could overrun `LINEBUF` and write into page 3.**

Found while fixing the above, and reachable the same way. `RENDERROW` stages
the row through `LINEBUF`, which is exactly one screen wide at `$0200`, copying
`CCOL` bytes into it from before the gap and `GSCRW - CCOL` from after. Once
the cursor sits further along the line than the screen is wide, the first copy
runs past the end of the buffer and the second underflows: at column 100 it
copies 228 bytes to `$0264` and runs through page 2 into page 3. Arrowing right
along a pasted line was enough to do it.

The one-row redraw is only entered while the cursor's column fits on the
screen now. Anything longer takes the full redraw, which clips.

**Smaller things.**

- `GRABLINE` clamps the run it copies before the cursor to the 255 characters
  the clipboard holds. It counts in `X`, so against a two-byte `CCOL` it would
  otherwise have compared the low byte alone and taken a slice out of the
  middle of a long line.
- The goal column clamps rather than truncating to the low byte, so a vertical
  move from a long line aims at the end of it instead of somewhere arbitrary.
- `DSTPTR` moves to `$6d` to give `CCOL` a contiguous pair at `$30-$31`.

A `paste keeps the wrap` section in the suite, asserting against RAM rather
than the screen — a line running past the margin is precisely what the screen
cannot show. It fails 4 of 9 against 1.1 and passes against this one. 281
assertions across 38 sections. The editor is 10,632 bytes, or 9,728 on a ][+.

None of the typing work is something the suite can prove. Virtual ][ hands keys
over as the program reads them, so a key is almost never waiting while the
editor is busy — the emulator is structurally unable to reproduce a dropped
keystroke, or to exercise the paths that prevent one. The timings above were
taken at 1MHz by forcing the condition in scratch builds; that the losses have
actually stopped is a question only real hardware answers, and it did.

## 1.1 — 22 August 2026

Two machines this time. The editor that shipped as 1.0 needed an Enhanced
//e with 128K; 1.1 also runs on an Apple ][+ and on an unenhanced //e, and
the version numbers are held in step so that a splash screen tells you what
you have without qualification.

**New: ZipEdit runs on an Apple ][+.**

A separate image, `ZIPEDIT2P.po`, because the machine is different enough to
warrant it: 40 columns instead of 80, the text buffer in main memory because
there is no auxiliary bank, and a keyboard with no Open-Apple key, no Delete,
and no up or down arrows. Roughly three thousand words rather than seven, which
is the whole price of running on hardware four years older than the aux card.

The commands are the same commands, reached differently. Where the //e uses
Open-Apple, this uses Ctrl and Esc: `Ctrl-O` opens, `Ctrl-S` saves, `Esc Ctrl-S`
is save-as, `Esc ?` is the help screen. `Ctrl-J` and `Ctrl-K` move down and up.

Case is Apple Writer's answer, because a ][+ character generator holds 64
glyphs and none of them is a lowercase letter. You type in lower case and it
draws as ordinary capitals; press `Esc` before a letter and you get a capital,
drawn inverse so that it stands out. The file on the disk has the case you
meant, whatever the screen was able to show you.

**Confirmed: the unenhanced //e.**

1.0.3 shipped MouseText detection marked *preliminary, unverified* — it had
never been run on a machine without an Enhanced ROM. It has now, by beta
testers on real hardware, and it draws correctly.

**Fixed: a word longer than the margin, typed into a paragraph, corrupted the
text.**

Not the screen. The file. `jumps` and a run of `a`s came back off the disk as
`jauamaaaaaaaaaaps` — the new word laid down alternating with the text already
there, one character at a time.

The wrap check tests whether a line has grown too long by walking out to the
margin, breaking there, and walking the same distance back. That holds while a
break is byte-preserving: normally it replaces the space it breaks at, one byte
for one. A word with no space in it has nothing to replace, so the break is a
byte that was not there before — one of the steps home gets spent stepping over
it, the cursor comes to rest one character late, and every character after that
lands one place further along than the last.

Present in 1.0 and every release since. It needs a long word — a URL, a file
path, a long hyphenless term — typed *into* existing text; typing one at the
end of a document was always fine, which is why three releases went by.

**Fixed: a paragraph longer than 255 characters opened broken at its first
character.**

A file whose lines are whole unwrapped paragraphs — anything written on a Mac
and not hard-wrapped — arrived with the column count already wrapped around
past the margin, so the first wrap broke the line at its opening character.
`**History Duel**` opened as `*`, then `*History Duel**` on the line below.

**Faster: the redraw no longer counts from the start of the buffer.**

Every full redraw walked the buffer from byte zero, counting lines until it
reached the top of the screen, reading each byte through a banked load before
drawing a single character. The cost was therefore proportional to how far into
the document you had got — and on a real Apple, whose keyboard has no buffer,
anything typed during a redraw is not delayed but *lost*. Writers reported
having to type slowly to avoid dropping whole words.

Timed at 1MHz on a 6K document, with the arrow keys, which force a redraw on
every press:

| cursor at | 1.0.3 | 1.1 |
|---|---|---|
| line 1 | 218ms | 218ms |
| line 66 | 398ms | 168ms |
| line 131 | 553ms | 162ms |

The editor now remembers where the line at the top of the screen begins and
starts there, stepping that address along as the screen scrolls. Depth costs
nothing now: the curve is flat.

**Smaller things.**

- A soft wrap's space is held back where nothing follows it, so a saved file
  has no trailing space on the last line of a paragraph.
- `xfer.sh` runs under `sh` as well as `bash`; it used to fail with a syntax
  error before doing anything.
- `tocard.sh` checks the card is FAT before blaming the disk image, and lists
  every image on the card rather than only the one it wrote — an older build
  under a previous name still boots, and that is worth saying out loud.
- `mkdisk.sh` refuses a system-file name longer than the 15 characters ProDOS
  allows, instead of truncating it into something that no longer ends in
  `.SYSTEM` and silently boots to BASIC.
- `make release` names the source file it assembled from, since the three
  builds produce a `ZIPEDIT.SYSTEM` that looks identical on the disk.

## 1.0.3 — 20 August 2026

**Fixed: a text file the editor did not write came up as a blank screen.**

The buffer holds high ASCII, and the line-end test is a single compare against
`$A0` — so anything below that ends a line. Fine for a file ZipEdit wrote; a
disaster for one it did not. A `.txt` from a Mac or a PC is low ASCII
throughout, so **every byte** read as a line break and the document came up as
thousands of empty lines, which on screen looks exactly like nothing at all.

Reported from a //c under MAME: a 6.5K text file, a blank screen. It only ever
worked because every file tested had come through `xfer.sh push`, which sets
bit 7 on the way in — so the editor whose whole point is carrying drafts to and
from a Mac could not open what the Mac wrote.

The loader normalises now instead of trusting the file:

| in the file | what happens |
|---|---|
| CR, LF or CRLF | one line break, however the file spells its endings |
| tab | two spaces, matching what the Tab key inserts |
| `$20`–`$7E` | the same character with bit 7 set |
| high ASCII | untouched, so existing files load exactly as before |
| other control bytes | dropped, before they can punch phantom breaks |

**Fixed: the help screen was missing a command.**

`OA-Delete` — delete the previous word — went into the help layout when the
feature was added, but `src/help.S` was never regenerated. Every build since
has shipped a help screen with a blank line where that command belongs. It is
documented at last, and `genhelp.py --check` now runs in `make test` so the
generated file cannot fall behind its layout again.

**Also here:**

- `genhelp.py` rejects help rows whose columns collide, not merely ones that
  overrun the border. Reported from an Italian translation: English
  descriptions never grew long enough to reach the next column and Italian
  ones do, and an over-long one was silently overwritten rather than failing.
- `PUTAUX` no longer saves the accumulator across a soft-switch write. `STA`
  never disturbs it, so the round trip did nothing — two bytes, and four
  cycles off every write into the text buffer. Asked by someone reading the
  source on GitHub.
- The manual's `xfer.sh push` example was wrong: `push` takes a folder, not a
  file, and moves every `.md` in it.
- **Preliminary, unverified:** the editor now detects an original (unenhanced)
  //e and draws solid blocks where MouseText would be, instead of the rows of
  letters those codes produce there. Every emulator available offers only an
  Enhanced //e, so the detection has not yet run on the machine it is for.
  Enhanced machines are unaffected and byte-for-byte identical.

261 assertions across 36 sections. The editor is 9,218 bytes.

## 1.0.2 — 19 August 2026

**Fixed: quitting and relaunching left the editor with a garbage filename and
unable to save.**

Every buffer and flag the editor keeps lives in a `dum` block or on zero page,
neither of which puts bytes in the loaded file — so none of it starts at a
known value. A cold boot leaves that memory zero and the launch path looked
correct by luck. Quit to the ProDOS selector and relaunch, and it holds
whatever the selector left behind.

`FNAME`'s first byte is the filename length, where zero means *never named*.
After a relaunch it read as some other number, so the editor believed the
document was already named, printed the garbage where the filename goes, and
`OA-S` saved to it and returned `PRODOS ERROR $40`. Rebooting cleared it,
which is what made it look like a memory problem rather than a missing
initialisation.

`OA-N` had cleared `FNAME` all along, with the comment "length 0, so OA-S asks
for a name". Only the launch path never did the same.

The same reasoning applies to everything else assumed empty at startup, so
`CLIPLEN`, `CLIPLINE`, `FINDLEN` and `PLEN` are cleared too. Nobody had hit
those yet, but after a relaunch `OA-V` would have pasted from an untouched
clipboard buffer and `OA-G` would have searched for a garbage pattern.

Costs 16 bytes. The editor is 9,020 bytes.

Also here:

- A `relaunch after quit` section in the suite, which quits to the selector,
  relaunches, and checks both halves. It fails 0 of 3 against 1.0.1 and passes
  against this one. 241 assertions across 34 sections.

## 1.0.1 — 19 August 2026

**Fixed: a last line that fitted was wrapped anyway.**

`WRAPCHECK` reads ahead from the cursor looking for a line end. Not finding one
within the room left before the margin means the line is too long, so it breaks
it. But that read-ahead is also capped at the end of the buffer, so the scan
could stop for either of two opposite reasons — out of margin, meaning wrap, or
out of document, meaning leave it alone — and both arrived at the same place.

So a final line with no trailing break was wrapped, then reflowed, and the
cursor was walked back to the wrong position. Typing after that scattered
characters through the line.

This is not really about one-line documents, which is only where it is
unmissable, being true from the first keystroke. It is the **last line of any
document that does not end in a break** — and since ZipEdit writes only the
returns you typed, that is nearly every file it saves. In a longer document you
meet it when you go back to edit the final line.

*If you copied or forked this repository at 1.0, take `src/wrap.S` from this
release.* The fix is a few instructions in `WRAPCHECK`: answer before scanning,
because if fewer bytes remain in the buffer than there is room on the line, the
document runs out before the margin does and the line cannot be too long.

Also here:

- The splash screen reads Version 1.0.1, re-centred for the longer string.
- A `short last line` section in the suite, which fails against the 1.0 binary
  and passes against this one. 239 assertions across 32 sections.
- The README says what to do when saving fails on a Floppy Emu: the original
  Disk II controller needs a pull-up on `/WRREQ` before the Emu can write when
  it is the only drive on the chain, which presents exactly as a
  write-protected disk.

## 1.0 — 18 August 2026

First release. An 80-column, full-screen Markdown editor for the Enhanced Apple
//e, in 6502 assembly, on a bootable ProDOS 8 disk.

- Gap buffer in auxiliary memory, leaving about 46K for your writing
- Hard wrap on entry at column 76, reflow a paragraph on demand
- Selection, cut, copy, paste, find, go to line, word count
- Two pages of keyboard help, and a one-line Markdown cheat sheet
- Files are saved as plain text carrying only the line breaks you typed, so
  what reaches the Mac needs no cleaning up
