# Apple //e assembly-language text editor -- build system
#
#   make          assemble SRC with Merlin32
#   make disk     build a bootable ProDOS 8 image
#   make run      build, then boot it in Virtual ][
#   make screen   print what's on the emulated screen right now
#   make test     run the AppleScript regression suite
#   make clean

VERSION := 1.1
SRC     ?= src/edit.S
NAME    ?= ZIPEDIT.SYSTEM
BUILD   := build
DOCS    ?= notes
TOOLS   := tools

MERLIN  := $(TOOLS)/merlin32
ASMINC  := $(TOOLS)/asminc
AC      := $(TOOLS)/ac
VII     := $(TOOLS)/vii.sh

BIN     := $(BUILD)/$(NAME)
IMAGE   := $(BUILD)/ZIPEDIT.po

# The Apple ][+ build. Same editor, 40 columns, text buffer in main memory,
# no Open-Apple key. It writes its own SYS name, so it can sit beside the //e
# build in build/ and on a card without either being mistaken for the other.
SRC2P   := src/edit2p.S
NAME2P  := ZIPEDIT2P.SYSTEM
BIN2P   := $(BUILD)/$(NAME2P)
IMG2P   := $(BUILD)/ZIPEDIT2P-REL.po
# On the disk it is ZIPEDIT.SYSTEM, as on the //e: it is the same program and
# the machine it is for is not the writer's business. It also has to be --
# a ProDOS filename stops at 15 characters and ZIPEDIT2P.SYSTEM is 16, so it
# lands as ZIPEDIT2P.SYSTE, stops looking like a .SYSTEM file, and the disk
# quietly boots to BASIC instead. The image FILENAME is what tells the two
# builds apart on the card.
SYS2P   := ZIPEDIT.SYSTEM

.PHONY: all disk run screen test clean tools pull push eject release probe card plaindisk checkhelp keyprobe two release2p card2p dist

all: $(BIN)

# Every source file, not just $(SRC): the rest are pulled in with Merlin's put
# directive, and depending on $(SRC) alone meant edits to them never rebuilt.
SOURCES := $(wildcard src/*.S)

# Merlin32 writes its object next to the source, named by the `dsk` directive.
$(BIN): $(SOURCES) | $(BUILD)
	@$(MERLIN) $(ASMINC) $(SRC) > $(BUILD)/merlin32.log 2>&1 || \
		{ echo "--- Merlin32 failed ---"; cat $(BUILD)/merlin32.log; exit 1; }
	@grep -iE '^\s+(Error|Warning)' $(BUILD)/merlin32.log && exit 1 || true
	@mv $(dir $(SRC))$(NAME) $(BIN)
	@rm -f $(dir $(SRC))_FileInformation.txt
	@echo "assembled $(SRC) -> $(BIN) ($$(stat -f%z $(BIN)) bytes)"

$(BUILD):
	@mkdir -p $(BUILD)

disk: $(IMAGE)

$(IMAGE): $(BIN) tests/sample.md
	@$(TOOLS)/mkdisk.sh $(IMAGE) $(BIN)
	@$(TOOLS)/xfer.sh push $(IMAGE) tests >/dev/null
	@echo "  SAMPLE.MD on the image"

# The editor opens empty, so the demo document lives on the disk. The suite
# opens it too -- that is where all of its text comes from.

run: $(IMAGE)
	@$(VII) boot $(IMAGE)
	@$(VII) settle 8
	@echo "--- screen ---"
	@$(VII) screen

screen:
	@$(VII) screen

# SAMPLE.MD is the suite's fixture and lives on the image, so a test that saves
# can overwrite it. Put a fresh copy back before every run.
test: $(IMAGE) plaindisk checkhelp
	@$(TOOLS)/xfer.sh push $(IMAGE) tests >/dev/null
	@python3 $(TOOLS)/asciifixtures.py $(IMAGE) >/dev/null
	@tests/run.sh $(SECTION)

# src/help.S is generated but committed, so it can fall behind tools/genhelp.py
# without anything noticing -- which is how the OA-Delete row went missing from
# the shipped help screen. This makes that a build failure.
checkhelp:
	@python3 $(TOOLS)/genhelp.py --check src/helpdata80.S
	@python3 $(TOOLS)/genhelp.py --check --40 src/helpdata40.S

# A second image whose editor is patched to draw the original //e's glyphs.
# Virtual ][ has no unenhanced //e, so this is how that path gets tested.
PLAINBIN  := $(BUILD)/ZIPEDIT-PLAIN.SYSTEM
PLAINIMG  := $(BUILD)/ZIPEDIT-PLAIN.po

plaindisk: $(PLAINIMG)

$(PLAINIMG): $(BIN)
	@python3 $(TOOLS)/forceplain.py $(BIN) $(PLAINBIN)
	@VOL=ZIPEDIT SYS=ZIPEDIT.SYSTEM $(TOOLS)/mkdisk.sh $(PLAINIMG) $(PLAINBIN) >/dev/null
	@echo "plain-glyph image: $(PLAINIMG)"

# Virtual ][ buffers image writes until eject, so pull needs a flush first.
eject:
	@osascript -e 'tell application "Virtual ][" to tell (last machine) to eject device "S6D1"' 2>/dev/null || true
	@echo "ejected"

pull: eject
	@$(TOOLS)/xfer.sh pull $(IMAGE) $(DOCS)

push:
	@$(TOOLS)/xfer.sh push $(IMAGE) $(DOCS)

# A standalone probe disk for real hardware: identifies the ROM and dumps the
# $40-$5F glyphs, so the character set can be checked on the actual machine
# rather than inferred from an emulator.
probe: | $(BUILD)
	@$(MERLIN) $(ASMINC) src/charprobe.S > $(BUILD)/probe.log 2>&1 || \
		{ echo "--- Merlin32 failed ---"; cat $(BUILD)/probe.log; exit 1; }
	@mv src/PROBE.SYSTEM $(BUILD)/PROBE.SYSTEM
	@rm -f src/_FileInformation.txt
	@RELEASE=0 VOL=PROBE NAME=PROBE.SYSTEM $(TOOLS)/mkprobe.sh
	@echo "probe disk: $(BUILD)/CHARPROBE.po"

# A disk that answers what a keyboard really sends. Built for one question the
# emulator cannot answer: does Ctrl-J carry $8A on a real ][+?
keyprobe:
	@$(MERLIN) $(ASMINC) src/keyprobe.S > $(BUILD)/keyprobe.log 2>&1 || \
		{ echo "--- Merlin32 failed ---"; cat $(BUILD)/keyprobe.log; exit 1; }
	@mv src/KEYPROBE.SYSTEM $(BUILD)/KEYPROBE.SYSTEM
	@rm -f src/_FileInformation.txt
	@RELEASE=1 VOL=KEYPROBE SYS=KEYPROBE.SYSTEM $(TOOLS)/mkdisk.sh \
		$(BUILD)/KEYPROBE.po $(BUILD)/KEYPROBE.SYSTEM >/dev/null
	@echo "keyboard probe disk: $(BUILD)/KEYPROBE.po"

# A disk to hand to real hardware: editor + ProDOS + BASIC.SYSTEM, no test files.
release: $(BIN)
	@RELEASE=1 VOL=ZIPEDIT $(TOOLS)/mkdisk.sh $(BUILD)/ZIPEDIT-REL.po $(BIN)
	@echo
	@echo "release image: $(BUILD)/ZIPEDIT-REL.po"
	@echo "  built from $(SRC) -> $(NAME), $$(stat -f%z $(BIN)) bytes"
	@echo "  (src/edit.S is the 80-column //e; edit2p.S is the ][+)"

# Copy the release image to a card, cleanly. VOL is the mounted volume name.
card: release
	@$(TOOLS)/tocard.sh "$(VOL)" $(BUILD)/ZIPEDIT-REL.po

# --- the Apple ][+ ------------------------------------------------------
two: $(BIN2P)

$(BIN2P): $(SOURCES) | $(BUILD)
	@$(MERLIN) $(ASMINC) $(SRC2P) > $(BUILD)/merlin32-2p.log 2>&1 || \
		{ echo "--- Merlin32 failed ---"; cat $(BUILD)/merlin32-2p.log; exit 1; }
	@grep -iE '^\s+(Error|Warning)' $(BUILD)/merlin32-2p.log && exit 1 || true
	@mv src/$(NAME2P) $(BIN2P)
	@rm -f src/_FileInformation.txt src/$(NAME2P)_Output.txt
	@echo "assembled $(SRC2P) -> $(BIN2P) ($$(stat -f%z $(BIN2P)) bytes)"

release2p: $(BIN2P)
	@RELEASE=1 VOL=ZIPEDIT2P SYS=$(SYS2P) $(TOOLS)/mkdisk.sh $(IMG2P) $(BIN2P)
	@echo
	@echo "release image: $(IMG2P)"
	@echo "  built from $(SRC2P) -> $(NAME2P), $$(stat -f%z $(BIN2P)) bytes"
	@echo "  (40 columns, main-memory buffer -- the Apple ][+ build)"

card2p: release2p
	@$(TOOLS)/tocard.sh "$(VOL)" $(IMG2P)

# --- what gets uploaded -------------------------------------------------
# Both machines in one archive. The splash screen is checked against VERSION
# rather than trusted: the number lives in three places -- here, splash.S and
# the suite's assertion -- and a release whose About box disagrees with its
# own filename is a bad look that no test would otherwise catch.
DIST    := $(BUILD)/ZipEdit-$(VERSION)
ZIP     := $(BUILD)/ZipEdit-$(VERSION).zip

dist: release release2p
	@grep -q 'asc   "Version $(VERSION)"' src/splash.S || \
		{ echo "src/splash.S does not say Version $(VERSION)" >&2; exit 1; }
	@rm -rf $(DIST) $(ZIP)
	@mkdir -p $(DIST)
	@cp $(BUILD)/ZIPEDIT-REL.po $(DIST)/ZIPEDIT.po
	@cp $(IMG2P) $(DIST)/ZIPEDIT2P.po
	@cp $(TOOLS)/xfer.sh LICENSE $(DIST)/
	@sed 's/@VERSION@/$(VERSION)/g' docs/release-README.txt > $(DIST)/README.txt
	@cd $(BUILD) && zip -qr ZipEdit-$(VERSION).zip ZipEdit-$(VERSION)
	@rm -rf $(DIST)
	@echo
	@echo "release archive: $(ZIP) ($$(du -h $(ZIP) | cut -f1))"
	@unzip -l $(ZIP) | sed -n '4,$$p'

clean:
	@rm -rf $(BUILD) src/_FileInformation.txt src/$(NAME)
	@echo "cleaned"
