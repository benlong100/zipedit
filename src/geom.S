*--------------------------------------
* GEOM.S -- screen geometry as data, rather than as assumptions
*
* Every column in the layout used to be an equate compiled into whatever code
* read it: the wrap margin, the status row's digit columns, the width of the
* filename field, where the prompt puts its escape hint. That is fine while
* there is one screen width and hopeless the moment there are two. A
* 40-column machine wants none of those numbers, and hunting them down by
* hand is how a layout ends up right in five places and wrong in the sixth.
*
* So they live in a record filled in at startup from one of the tables below.
* Adding a width means adding a table and choosing it in GEOMINIT. It does not
* mean auditing the code that draws.
*
* Rows are deliberately NOT here. A 40-column screen has the same 24 rows as
* an 80-column one, so CHEATROW, STATROW and TEXTROWS stay equates.
*
* The cost is a memory read where there used to be an immediate -- one or two
* cycles, at sites that run once a keystroke or once a row, never once a
* character. The hot inner loops read a loop bound, not a per-byte value.
*--------------------------------------

*--------------------------------------
* GEOMINIT -- fill the record in. The one place a width is chosen.
*--------------------------------------
GEOMINIT     ldx   #GEOMN-1         ; GEOMTBL is named by the screen driver
:loop        lda   GEOMTBL,x
             sta   GEOM,x
             dex
             bpl   :loop
             rts

*--- 80 columns: the //e, and whatever else can manage it. These are exactly
*    the values that were equates, so nothing about this machine changes.
GEOM80       dfb   80               ; GSCRW     screen width
             dfb   79               ; GSCRWM1   its last column
             dfb   77               ; GWRAP1    first column PAST the margin,
                                    ;           which is what every test wants
             dfb   40               ; GLNDIG    status row: line number digits
             dfb   47               ; GCLDIG    status row: column digits
             dfb   32               ; GNAMEW    status row: filename field
             dfb   31               ; GNAMEWM1  ... and its last column
             dfb   66               ; GPHINT    prompt: the escape hint
             dfb   45               ; GPMAX     prompt: longest input accepted
             dfb   8                ; GHELPCOL  help box: left edge
             dfb   <STATTXT         ; GSTATLO   the static status row text,
             dfb   >STATTXT         ; GSTATHI   which is a layout, not a string
             dfb   <MSGUNSAVED      ; GUNSVLO   and the unsaved-changes
             dfb   >MSGUNSAVED      ; GUNSVHI   question, which is a width
GEOMN        equ   *-GEOM80

*--- 40 columns, for an Apple ][+. Nothing selects this yet: the display and
*    keymap for that machine do not exist. It is here because a table with one
*    entry proves nothing, and because these numbers are the layout decisions
*    written down where the next person will look for them.
*
*    The status row loses the free-memory readout and the help hint -- at 40
*    columns the filename and the position are what you look at constantly and
*    the other two almost never. The cheat sheet does not survive the trip at
*    all; its material belongs in the help screen there.
GEOM40       dfb   40               ; GSCRW
             dfb   39               ; GSCRWM1
             dfb   37               ; GWRAP1    a 36 column margin
             dfb   19               ; GLNDIG    " NAME*    L:12  C:34"
             dfb   25               ; GCLDIG
             dfb   15               ; GNAMEW    the filename field, and its
             dfb   14               ; GNAMEWM1  star, in what is left
             dfb   28               ; GPHINT    prompt hint, shortened there
             dfb   20               ; GPMAX     input, capped short of it
             dfb   0                ; GHELPCOL  no box at all: the border is
                                    ;           MouseText, which this machine
                                    ;           cannot draw
             dfb   <STATTXT40       ; GSTATLO
             dfb   >STATTXT40       ; GSTATHI
             dfb   <MSGUNSV40       ; GUNSVLO
             dfb   >MSGUNSV40       ; GUNSVHI

*--- The record the layout actually reads. $1450-$14A7 is wrap's.
             dum   $14a8
GEOM
GSCRW        ds    1
GSCRWM1      ds    1
GWRAP1       ds    1
GLNDIG       ds    1
GCLDIG       ds    1
GNAMEW       ds    1
GNAMEWM1     ds    1
GPHINT       ds    1
GPMAX        ds    1
GHELPCOL     ds    1
GSTATLO      ds    1
GSTATHI      ds    1
GUNSVLO      ds    1
GUNSVHI      ds    1
             dend
