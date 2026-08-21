# ZipEdit

An 80-column, full-screen **Markdown editor for the Enhanced Apple //e**,
written in 6502 assembly. Files are drafted on the //e and moved back to a Mac
for publishing.

Note the distinction: this is a text editor *implemented in* assembly, not an
editor *for* assembly source. It is aimed at prose — hard wrap on entry, no
soft wrap, and Markdown-aware emphasis shortcuts.

The editor is 9,020 bytes and leaves about 46K free for your writing, which is
roughly seven thousand words.

## Getting it running

Grab [the latest release](https://github.com/benlong100/zipedit/releases/latest)
— a bootable ProDOS 8 disk image, the transfer script, and a manual — or build
it yourself:

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
tools/xfer.sh push build/ZIPEDIT.po ~/drafts      # every .md in a folder
tools/xfer.sh unwrap old-file.md                  # repair a pre-1.0 file
```

Emulators buffer writes to a mounted image, so eject before pulling. `make
pull` does that for you.

## If saving fails

If a save reports an error, or the disk behaves as though it were
write-protected, and you are booting from a Floppy Emu:

- **Check the Emu's display for a padlock.** A padlock means the image is
  read-only — either the file is marked read-only on the SD card, or the
  firmware predates `Apple-II-0.1D-F3`, which is where 5.25-inch write support
  arrived. Nothing on the disk itself causes this: ZipEdit's files are saved
  unlocked (ProDOS access `$E3`), and `.po` is a writable image format, unlike
  `.nib` and `.woz`.
- **No padlock, but writes still fail.** The original 1978 Disk II controller,
  and some early //e controllers, need a pull-up resistor on the `/WRREQ` line
  before a Floppy Emu can write — but only when the Emu is the *sole* drive on
  the chain. Reads work perfectly and writes are silently dropped, which is
  indistinguishable from a write-protected disk. Daisy-chaining a real drive as
  drive 2 changes that condition, and costs nothing to try before buying a
  different controller.

Either way, saving to a different device works: `Open-Apple-A` and give a full
pathname, such as `/CFFA3/DRAFT.MD`. ProDOS does not mind that the write lands
somewhere other than the boot device. Note that `/RAM` is *not* available —
ZipEdit disconnects it at startup, because on a 128K machine ProDOS puts it in
the same auxiliary memory the text buffer uses.

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

## Changes

See [CHANGELOG.md](CHANGELOG.md). If you copied this repository at 1.0, note
that 1.0.1 fixes a wrapping bug affecting the last line of nearly every saved
file, and 1.0.2 fixes uninitialised state that breaks saving after a relaunch.

## Licence

MIT. See [LICENSE](LICENSE).

ZipEdit is an independent project. It is not affiliated with, authorized by, or
endorsed by Apple Inc.
