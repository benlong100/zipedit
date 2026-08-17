# Apple //e assembly-language text editor -- build system
#
#   make          assemble SRC with Merlin32
#   make disk     build a bootable ProDOS 8 image
#   make run      build, then boot it in Virtual ][
#   make screen   print what's on the emulated screen right now
#   make test     run the AppleScript regression suite
#   make clean

SRC     ?= src/hello.S
NAME    ?= EDIT.SYSTEM
BUILD   := build
TOOLS   := tools

MERLIN  := $(TOOLS)/merlin32
ASMINC  := $(TOOLS)/asminc
AC      := $(TOOLS)/ac
VII     := $(TOOLS)/vii.sh

BIN     := $(BUILD)/$(NAME)
IMAGE   := $(BUILD)/EDIT.po

.PHONY: all disk run screen test clean tools

all: $(BIN)

# Merlin32 writes its object next to the source, named by the `dsk` directive.
$(BIN): $(SRC) | $(BUILD)
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

clean:
	@rm -rf $(BUILD) src/_FileInformation.txt src/$(NAME)
	@echo "cleaned"
