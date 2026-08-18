# a2-editor

An 80-column, full-screen **Markdown** editor for the Enhanced Apple //e
(128K, ProDOS 8), **written in** 6502 assembly in Merlin syntax. Files are
drafted on the //e and moved back to a Mac for publishing.

Note the distinction: this is a text editor *implemented in* assembly, not an
editor *for* assembly source. It is aimed at prose. Hard wrap on entry, no soft
wrap, and Markdown-aware emphasis shortcuts.

See `docs/design.md` for the memory map, buffer design, and keymap.

A splash screen shows at startup and waits for a key, so anything driving the
editor has to get past it before the document appears — `reboot` in the suite
does that.

## Toolchain

Source lives here on the Mac and is cross-assembled; the //e never sees a
source file we didn't generate.

- **Merlin32** (`tools/merlin32`) — primary assembler. Built from
  `apple2accumulator/merlin32`.
- **AppleCommander 13.2** (`tools/ac`) — builds ProDOS disk images. Native
  arm64 binary, so no JRE is required.
- **Virtual ][ 11.4** — emulator, driven through AppleScript by `tools/vii.sh`.
- **Merlin 8 v2.48 (DOS 3.3)** — `vendor/`, the user's original assembler. Kept
  as the dialect reference, not used in the build.

`tools/bootstrap.sh` reconstructs all of it on a fresh clone.

## Commands

```
make            assemble $(SRC) with Merlin32
make disk       build a bootable ProDOS 8 image at build/EDIT.po
make run        build, boot in Virtual ][, print the screen
make test       run the regression suite
make pull       eject, then extract Markdown from the image into notes/
make push       convert notes/*.md back onto the image as ProDOS TXT
make eject      flush the mounted image to disk
make clean
```

`SRC` defaults to `src/edit.S`, the editor itself. The spikes are still
buildable and worth keeping: `make SRC=src/charset.S run` re-runs the character
generator probe, `src/hello.S` is the minimal toolchain check.

## Conventions

- **Merlin dialect.** Merlin32 is Merlin 16+ flavoured and is not identical to
  the Merlin 8 on the //e. Stay in the common subset: plain 6502, and the
  directives `ORG EQU DFB DW DS ASC HEX LUP MAC EOM`. Treat Merlin 8 as ground
  truth if the two ever disagree.
- **Case and layout.** Lowercase mnemonics, labels in column 1, opcodes at
  column 14, operands at column 20, comments at column 40 — matching the
  Merlin house style in `src/hello.S`.
- **Local labels** are `:name`, scoped to the enclosing global label.
- **Never hand-edit the help screen hex.** `src/help.S` holds 42 rows of raw
  screen codes and they are generated: edit the layout in `tools/genhelp.py`
  and re-run it. It enforces the column stops, so a description that would
  overrun the border fails there instead of shipping mangled.
- **High ASCII.** Anything destined for the screen or for a text file has bit 7
  set. `asc "..."` (double quotes) sets it; single quotes do not.

## Keymap

Arrows move by character and line. OA-up/OA-down page, OA-`<`/OA-`>` jump to
the start and end of the document. Ctrl-A/Ctrl-E line ends, Ctrl-B bold (`**`),
Ctrl-I italic (`*`), Ctrl-D delete forward. OA-R reflow, OA-S save, OA-O open,
OA-C/OA-X/OA-V copy, cut and paste a line. OA-F find, OA-G find again, OA-L go
to line, OA-W word count. OA-N starts a new document and OA-Q quits, both asking first if the document
is modified. OA-S saves to the document's own file and only prompts when it has
no name yet; OA-A is save as, which always prompts and adopts the new name. OA-? (or OA-H) opens the keyboard help,
which is two pages -- a key turns to page two, another leaves. OA-/ toggles the
one-line cheat sheet, OA-Q quits. `$89` is both Tab and Ctrl-I and dispatches on
position -- see `docs/design.md`.

## Testing

`tests/run.sh` boots the built image in Virtual ][ and asserts against both the
emulated screen and emulated RAM. Prefer RAM assertions — `vii.sh dump <addr>
<len> <bank>` reads the auxiliary bank, so tests can check the text buffer
directly rather than inferring it from the display.

Use `vii.sh await <substring>` rather than fixed delays; it fails loudly on
timeout instead of silently reading a stale screen.

## Selection

OA-Space latches selection mode, the arrows paint, Esc cancels. Because the gap
is at the cursor, a selection is always contiguous in aux — before the gap or
after it, never split.

**Do not try shift-arrow again.** `$C063` is widely documented as the //e's
shift-key input but does not track the shift key on real hardware, and Virtual
][ reads it as permanently held.

## MouseText

The help border and the Open Apple glyph come from MouseText, at screen codes
`$40-$5F` with the alternate character set on. `make probe` builds a standalone
disk that identifies the ROM and dumps the glyphs on real hardware; it confirmed
Virtual ][ matches an Enhanced //e exactly, so glyph questions can be settled in
the emulator. Useful codes: `$4C`/`$53`/`$5C` horizontal rules at three heights,
`$5F` vertical, `$4E` solid block, `$5B` diamond, `$40`/`$41` solid and open
apple. There are **no** corner or T-junction glyphs.

Virtual ][ reads these codes back as the ASCII characters sharing their value,
so tests assert `\` for `$5C`, `L` for `$4C`, `_` for `$5F` and `A` for `$41`.

## Gotchas discovered the hard way

- `reset` in AppleScript is a *warm* reset and will not reboot from disk. Use
  `restart` for a cold boot.
- `tools/mkdisk.sh` clones the verified ProDOS image rather than formatting a
  fresh volume, so the boot blocks are known-good. It strips the disk to just
  `PRODOS` plus our `EDIT.SYSTEM`, and ProDOS auto-launches the only `.SYSTEM`
  file present.
- Never use `close every machine` in AppleScript — it would kill a Merlin
  session the user has open. `vii.sh` only ever touches `last machine`.
- ProDOS 8 puts `/RAM` in auxiliary memory on a 128K machine, which collides
  with the text buffer. It has to be disconnected at startup. See `docs/design.md`.
- `releases.prodos8.com` serves a GitHub Pages `*.github.io` certificate, so
  HTTPS fails name validation. `bootstrap.sh` fetches over HTTP and verifies by
  SHA-256 instead.
- **Virtual ][ buffers writes to a mounted image until the disk is ejected.**
  A file saved inside the emulator will not appear in the `.po` on disk until
  then, so `make pull` ejects first.
- **The Apple II keyboard has no buffer.** A ProDOS disk operation takes
  seconds of emulated time, and anything typed while it runs is dropped
  entirely. Tests must wait for an observable change rather than sleeping a
  fixed interval -- this cost two false test failures. Where an operation still
  prints a message, `vii.sh await` it; where it deliberately says nothing (a
  successful save or load, a cut), wait for the status row to return or for the
  text itself to change, and `vii.sh settle` before asserting.
- ProDOS pathnames are length-prefixed and **low** ASCII, unlike everything
  else on this machine, which is high ASCII.
- **Virtual ][ cannot send an arrow key with Open-Apple held.** `type open
  Apple` takes characters only, and ASCII 10 does not reach the machine as a
  down arrow. OA-up/OA-down are therefore not verifiable from the suite; the
  page handlers are `KUP`/`KDOWN` repeated, which the arrow tests do cover, but
  the bindings themselves need checking by hand.
- **`X` cannot hold a loop counter across `INSCHR`, `GAPLEFT` or `GAPRIGHT`.**
  All of them reach a `TAX`. Count in memory.
- **The Makefile must depend on all of `src/*.S`, not just `$(SRC)`.** The rest
  are pulled in with `put`, and depending on `$(SRC)` alone meant edits to them
  silently did not rebuild — which produced a stale binary that looked like a
  runaway bug in new code.
- **Virtual ][ can leave a machine frozen**, after which every AppleScript
  command fails with "Cannot perform this command while the machine is frozen"
  and the screen reads back stale. `vii.sh boot` now thaws first; `vii.sh thaw`
  does it on demand. A whole round of measurements was invalid before I spotted
  this.
- **Pin `keyboard delay`, not the speed.** It is a machine property -- seconds
  Virtual ][ waits between AppleScript key presses -- and it defaults to `0.0`,
  which injects keys faster than the editor can read them. The surplus queues
  up, and that queue **survives `restart`**: reboot, send nothing at all, and
  the cursor still walks across the screen on its own. One backlog took 33
  seconds to drain, dribbling into later sections and failing tests that never
  touched the code under test. `vii.sh boot` pins it to 0.2, which makes a
  burst of 20 arrows land exactly on target with no shell sleeps at all, even
  at `maximum`. Override with `VII_KEYDELAY` / `VII_SPEED`.
- **`restart` resets both `speed` and `keyboard delay`** to the machine's saved
  defaults, so pin them *after* the restart. Setting either first looks like it
  worked and silently does nothing. At `maximum` a held key also auto-repeats,
  so one `type key` can land as two or three keystrokes -- the keyboard delay
  fixes that; dropping to `regular` does not.
- **A scattered failure set means the harness, not the code.** Four runs of one
  unchanged tree gave 1, 29, 10 and 31 failures across unrelated sections. The
  31-failure run looked exactly like an editor regression and was not: every
  one was a stale machine or a keystroke backlog. Drain to a known state and
  re-run before believing any of it.
- Typing costs a fixed ~100 ms plus ~0.035 ms per buffer byte, so tests must
  never sleep a fixed interval for a multi-character string. Use `ktext`, which
  waits for the text to appear.
