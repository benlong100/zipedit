# Changelog

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
