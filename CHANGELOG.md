# Changelog

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
