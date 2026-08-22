*--------------------------------------
* EQUATES.S -- hardware and zero page map
*
* Emits no code; included first so everything below can reference it.
*--------------------------------------

*--- soft switches (write to set, unless noted) ---
CLR80STORE   equ   $c000
SET80STORE   equ   $c001            ; PAGE2 then selects screen half
RAMRDOFF     equ   $c002
RAMRDON      equ   $c003
RAMWRTOFF    equ   $c004
RAMWRTON     equ   $c005
CLR80VID     equ   $c00c
SET80VID     equ   $c00d            ; 80 column video
CLRALTCHAR   equ   $c00e
SETALTCHAR   equ   $c00f            ; alt charset: MouseText + inverse lower
MAINWR       equ   $c054            ; PAGE2 off -> screen writes to MAIN
AUXWR        equ   $c055            ; PAGE2 on  -> screen writes to AUX
TXTSET       equ   $c051
MIXCLR       equ   $c052
HIRESOFF     equ   $c056

*--- keyboard (read) ---
KBD          equ   $c000            ; bit 7 set when a key is waiting
KBDSTRB      equ   $c010
OPNAPPLE     equ   $c061            ; bit 7 = Open-Apple held
CLSAPPLE     equ   $c062            ; bit 7 = Closed-Apple held

*--- firmware ---
AUXMOVE      equ   $c311

*--- ProDOS global page ---
MLI          equ   $bf00
DEVTBL       equ   $bf10            ; driver addresses, indexed by unit>>4
RAMDRV       equ   $bf26            ; slot 3 drive 2 -- where /RAM hooks in
DEVNUM       equ   $bf30
DEVCNT       equ   $bf31            ; device count MINUS ONE
DEVLST       equ   $bf32

*--- The text buffer's bounds, and how a byte in it is reached, are the
*    memory driver's: see auxbuf.S and mainbuf.S.

*--- zero page ---
* $3c-$43 are left alone: AUXMOVE uses them as A1/A2/A4.
SCRPTR       equ   $06              ; 2 bytes, current screen row base
STRPTR       equ   $08              ; 2 bytes, string source
CURROW       equ   $0a
CURCOL       equ   $0b
SAVEY        equ   $0c
TMPA         equ   $0d
TMPB         equ   $0e
FLAGS        equ   $0f
AUXPTR       equ   $10              ; 2 bytes, pointer into the aux buffer
GAPBEG       equ   $12              ; 2 bytes, aux addr of gap start = cursor
GAPEND       equ   $14              ; 2 bytes, aux addr of first byte past gap
TMPC         equ   $16
MAXROW       equ   $17              ; last usable text row + 1
KEYCHR       equ   $18              ; last key read
MODOA        equ   $19              ; $80 if Open-Apple was down with it
MODCA        equ   $1a              ; $80 if Closed-Apple was down with it
JMPVEC       equ   $1b              ; 2 bytes, dispatch trampoline
CURSROW      equ   $1d              ; screen position of the cursor
CURSCOL      equ   $1e
RUNLEN       equ   $1f              ; 2 bytes, bytes left in a file transfer
WDIST        equ   $21              ; wrap: characters to step over
SCROLLTOP    equ   $23              ; 2 bytes, buffer line on the first text row
LINENO       equ   $25              ; 2 bytes, line counter
VIS          equ   $27              ; non-zero once RENDER is inside the viewport
PGCNT        equ   $28              ; page-move counter
CURLNO       equ   $29              ; 2 bytes, line the cursor is on, maintained
                                    ; incrementally rather than rescanned
FASTDRAW     equ   $2b              ; handler opted in to a one-row redraw
OLDLINE      equ   $2c              ; 2 bytes, CURLNO before the keystroke
OLDTOP       equ   $2e              ; 2 bytes, SCROLLTOP before the keystroke
CCOL         equ   $30              ; cursor column, maintained incrementally
DSTPTR       equ   $31              ; 2 bytes, main-memory destination for AUXBLK
BLKLEN       equ   $33              ; bytes for AUXBLK to move
CLIPLEN      equ   $63              ; 2 bytes, bytes in the clipboard
FINDLEN      equ   $35              ; length of the search pattern

*--- selection. $36-$4F are avoided: the monitor keeps A1-A4 there and ProDOS
*    scribbles on $40-$4F during an MLI call.
SELACT       equ   $50              ; non-zero when text is selected
SELMODE      equ   $51              ; non-zero when arrows extend without shift
SELANC       equ   $52              ; 2 bytes, logical offset of the anchor
SELLEN       equ   $54              ; 2 bytes, length of the selection
GOALCOL      equ   $56              ; column vertical movement aims for
LPOS         equ   $57              ; 2 bytes, scratch logical position
INSEL        equ   $59              ; RENDER: inside the selection right now
SELDIR       equ   $5a              ; 0 = selection before the gap, 1 = after
SELLO        equ   $5b              ; 2 bytes, selection bounds as logical
SELHI        equ   $5d              ; 2 bytes, offsets, for RENDER
RPOS         equ   $5f              ; 2 bytes, RENDER's walking position
CLIPPTR      equ   $61              ; 2 bytes, paste cursor
CLIPLINE     equ   $65              ; clipboard holds a whole line, not a range
OLDSEL       equ   $66              ; selection state before the keystroke
VERTMOVE     equ   $67              ; this keystroke moved vertically
WASVERT      equ   $68              ; the previous one did
PARTIAL      equ   $69              ; handler changed nothing above the cursor
RSKIP        equ   $6a              ; rows RENDER counts without drawing
VISLINE      equ   $6b              ; 2 bytes, the first line RENDER draws
CLIPMAX      equ   1024             ; clipboard capacity


*--- FLAGS bits ---
FCHEAT       equ   %00000001        ; cheat sheet visible

*--- screen geometry ---
SCRW         equ   80               ; the WIDEST line we allocate for. The
                                    ; layout reads GSCRW at run time; this is
                                    ; only ever a buffer size. See geom.S.
CHEATROW     equ   22               ; 0-based; row 23 in the design doc
STATROW      equ   23
TEXTROWS     equ   22               ; when the cheat sheet is showing
TEXTROWSMAX  equ   23               ; when it is hidden
WRAPCOL      equ   76               ; hard wrap margin

*--- Line breaks come in three kinds, and which kind it is only matters when
*    the file is written. Everything else in the buffer is text at $a0 or
*    above, so ANY byte below TEXTLO ends a line -- one compare, the same cost
*    as testing for a carriage return, which is what the display path used to
*    do and still needs.
HARDCR       equ   $8d              ; a return the writer typed; saved as a CR
SOFTCR       equ   $8a              ; wrap that replaced a space; saved as one
SOFTWD       equ   $8b              ; wrap inside a word; saved as nothing
TEXTLO       equ   $a0              ; below this is a break, not text
LNDIG        equ   40               ; status column of the line number digits
CLDIG        equ   47               ; status column of the column digits
NAMECOL      equ   1                ; status column of the filename
NAMEW        equ   32               ; columns for it. FNAME holds a whole
                                    ; PATHNAME, not a bare filename, so 16 was
                                    ; too narrow for /VOLUME/FILE.MD and the
                                    ; star fell off the end. The status row is
                                    ; free up to column 37, where L: begins.
UNTLEN       equ   11               ; length of the UNTITLED.MD placeholder
PHINTCOL     equ   66               ; where the prompt shows its escape hint
PMAXLEN      equ   45               ; input length, capped so it cannot run
                                    ; over the hint at PHINTCOL
