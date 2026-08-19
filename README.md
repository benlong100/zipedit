# ZipEdit

An 80-column, full-screen **Markdown editor for the Enhanced Apple //e**,
written in 6502 assembly. Files are drafted on the //e and moved back to a Mac
for publishing.

Note the distinction: this is a text editor *implemented in* assembly, not an
editor *for* assembly source. It is aimed at prose — hard wrap on entry, no
soft wrap, and Markdown-aware emphasis shortcuts.

The editor is 9,010 bytes and leaves about 46K free for your writing, which is
roughly seven thousand words.

## Getting it running

Grab [`web/downloads/ZipEdit-1.0.zip`](web/downloads/ZipEdit-1.0.zip) — a
bootable ProDOS 8 disk image, the transfer script, and a manual — or build it
yourself:

```sh
tools/bootstrap.sh     # fetches Merlin32 and AppleCommander
make disk              # assembles, then builds build/ZIPEDIT.po
```

Mount `ZIPEDIT.po` in an emulator and boot it, or write it to a 5.25-inch disk.
A splash screen comes up; press any key and start typing. `Open-Apple-?` shows
two pages of keyboard help.

## What you need

| | |
|---|---|
| Computer | Enhanced Apple //e, 128K (or an emulator) |
| Operating system | ProDOS 8 |
| Display | 80 columns |
| Disk | one 5.25-inch, 143K |

## Getting your writing back out

ZipEdit saves ordinary text files, and the only line breaks in them are the
ones you typed — the wrapping you see on screen is display state, not file
content. What lands on your Mac needs no cleaning up.

```sh
tools/xfer.sh pull build/ZIPEDIT.po ~/Documents   # files off the image
tools/xfer.sh push build/ZIPEDIT.po draft.md      # a file onto it
tools/xfer.sh unwrap old-file.md                  # repair a pre-1.0 file
```

Emulators buffer writes to a mounted image, so eject before pulling. `make
pull` does that for you.

## Building and testing

```
make            assemble with Merlin32
make disk       build the bootable image at build/ZIPEDIT.po
make run        build, boot in Virtual ][, print the screen
make test       run the regression suite
make release    an image with BASIC.SYSTEM, for real hardware
make card VOL=  copy the release image to a mounted card
```

`make test` drives Virtual ][ through AppleScript and asserts against both the
emulated screen and emulated RAM — 233 assertions across 31 sections. A single
section can be run on its own:

```sh
tests/run.sh "hard wrap"
```

## Layout

```
src/        the editor, Merlin syntax, assembled from src/edit.S
tools/      build and emulator scripts; bootstrap.sh reconstructs the toolchain
tests/      the regression suite and its fixtures
docs/       design.md -- memory map, buffer design, keymap
web/        the ZipEdit web page, ready to upload as-is
```

`vendor/` holds the ProDOS and Merlin 8 disk images the build and the dialect
reference depend on. They are **not** in this repository — they are not mine to
redistribute. `tools/bootstrap.sh` fetches what it can; see `docs/design.md`.

## How it works

The text lives in the //e's auxiliary memory (`$0800`–`$BFFF`) as a gap buffer,
so an insertion in the middle of a long document costs the same as one at the
end. Line breaks come in three kinds — a return you typed, a wrap that replaced
a space, and a wrap inside a long word — and only the first is ever written to
a file. That distinction is what makes the exported text clean.

`docs/design.md` has the memory map, the banking rules, and a long list of
things that turned out to be harder than they looked.

## Licence

MIT. See [LICENSE](LICENSE).

ZipEdit is an independent project. It is not affiliated with, authorized by, or
endorsed by Apple Inc.
