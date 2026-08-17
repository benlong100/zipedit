# Apple //e assembly-language text editor -- build system
#
#   make          assemble SRC with Merlin32
#   make disk     build a bootable ProDOS 8 image
#   make run      build, then boot it in Virtual ][
#   make screen   print what's on the emulated screen right now
#   make test     run the AppleScript regression suite
#   make clean

SRC     ?= src/edit.S
NAME    ?= EDIT.SYSTEM
BUILD   := build
DOCS    ?= notes
TOOLS   := tools

MERLIN  := $(TOOLS)/merlin32
ASMINC  := $(TOOLS)/asminc
AC      := $(TOOLS)/ac
VII     := $(TOOLS)/vii.sh

BIN     := $(BUILD)/$(NAME)
IMAGE   := $(BUILD)/EDIT.po

.PHONY: all disk run screen test clean tools pull push eject release probe

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

$(IMAGE): $(BIN)
	@$(TOOLS)/mkdisk.sh $(IMAGE) $(BIN)

run: $(IMAGE)
	@$(VII) boot $(IMAGE)
	@$(VII) settle 8
	@echo "--- screen ---"
	@$(VII) screen

screen:
	@$(VII) screen

test: $(IMAGE)
	@tests/run.sh

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

# A disk to hand to real hardware: editor + ProDOS + BASIC.SYSTEM, no test files.
release: $(BIN)
	@RELEASE=1 VOL=EDITOR $(TOOLS)/mkdisk.sh $(BUILD)/EDITOR.po $(BIN)
	@echo
	@echo "release image: $(BUILD)/EDITOR.po"

clean:
	@rm -rf $(BUILD) src/_FileInformation.txt src/$(NAME)
	@echo "cleaned"
