# a2-editor

An 80-column, full-screen **Markdown** editor for the Enhanced Apple //e
(128K, ProDOS 8), **written in** 6502 assembly in Merlin syntax. Files are
drafted on the //e and moved back to a Mac for publishing.

Note the distinction: this is a text editor *implemented in* assembly, not an
editor *for* assembly source. It is aimed at prose. Hard wrap on entry, no soft
wrap, and Markdown-aware emphasis shortcuts.

See `docs/design.md` for the memory map, buffer design, and keymap.

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
make clean
```

`SRC` defaults to `src/hello.S` (the toolchain spike). Point it at the real
editor source as that comes up: `make SRC=src/edit.S run`.

## Conventions

- **Merlin dialect.** Merlin32 is Merlin 16+ flavoured and is not identical to
  the Merlin 8 on the //e. Stay in the common subset: plain 6502, and the
  directives `ORG EQU DFB DW DS ASC HEX LUP MAC EOM`. Treat Merlin 8 as ground
  truth if the two ever disagree.
- **Case and layout.** Lowercase mnemonics, labels in column 1, opcodes at
  column 14, operands at column 20, comments at column 40 — matching the
  Merlin house style in `src/hello.S`.
- **Local labels** are `:name`, scoped to the enclosing global label.
- **High ASCII.** Anything destined for the screen or for a text file has bit 7
  set. `asc "..."` (double quotes) sets it; single quotes do not.

## Testing

`tests/run.sh` boots the built image in Virtual ][ and asserts against both the
emulated screen and emulated RAM. Prefer RAM assertions — `vii.sh dump <addr>
<len> <bank>` reads the auxiliary bank, so tests can check the text buffer
directly rather than inferring it from the display.

Use `vii.sh await <substring>` rather than fixed delays; it fails loudly on
timeout instead of silently reading a stale screen.

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
