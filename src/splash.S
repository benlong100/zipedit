*--------------------------------------
* SPLASH.S -- the startup screen
*
* Shown once, on a cleared screen, before the document is drawn. Any key
* dismisses it, and that key is consumed here rather than falling through into
* the document -- pressing a letter to get past the splash must not type it.
*
* Each line is placed by hand rather than centred at run time: the strings are
* fixed, so the column is a constant the assembler can hold and there is no
* need to measure a string on a 1 MHz machine. If a line changes, its column
* has to change with it -- (80 - length) / 2.
*
* The Open Apple is the MouseText glyph ($41), the same as the help screen and
* the cheat sheet use, so the key is drawn as it looks on the keyboard.
*--------------------------------------
SPLN         equ   5                ; how many lines the screen has

*--------------------------------------
* SPLASH -- paint it, wait for a key, and hand back a clear screen
*--------------------------------------
SPLASH       jsr   CLRSCRN
             lda   #$00
             sta   SPLI

:loop        lda   SPLI
             asl                    ; two bytes per pointer
             tay
             lda   SPLPTR,y
             sta   STRPTR
             lda   SPLPTR+1,y
             sta   STRPTR+1
             jsr   CLRBUF
             jsr   SPLMID           ; centre it for whatever width this is
             tax                    ; BUFSTR starts at this column
             jsr   BUFSTR
             ldx   SPLI
             lda   SPLROW,x
             jsr   DRAWLINE
             inc   SPLI
             lda   SPLI
             cmp   #SPLN
             bne   :loop

             jsr   GETKEY
             jmp   CLRSCRN          ; leave the screen as we found it

SPLPTR       da    SPLNAME
             da    SPLVER
             da    SPLDATE
             da    SPLHELP
             da    SPLGO

*--------------------------------------
* SPLMID -- the column that centres the string at STRPTR
*
* This used to be a table of columns, measured by hand for an 80 column
* screen. On a 40 column one every line ran off the right edge and wrapped:
* "ZipEdit" came out as "ZipE" on one row and "dit" three rows below, which
* is a memorable way to be told that a layout constant is a layout
* assumption. Measure the string and halve what is left instead, and the
* splash centres itself on any screen the editor can draw on.
*--------------------------------------
SPLMID       ldy   #$00
:count       lda   (STRPTR),y       ; how long is it
             beq   :mid
             iny
             bne   :count
:mid         tya
             sta   SPLLEN
             lda   GSCRW
             sec
             sbc   SPLLEN           ; the space left over
             lsr                    ; half of it, rounding down, which is
             rts                    ; what the hand-measured table did too

*--- row for each line, in the same order as SPLPTR
SPLROW       dfb   10,12,14,20,21

SPLNAME      asc   "ZipEdit"
             dfb   $00
SPLVER       asc   "Version 1.1"
             dfb   $00
SPLDATE      asc   "August, 2026."
             dfb   $00
SPLHELP      dfb   $41,$ad,$bf      ; Open Apple glyph, "-", "?"
             asc   " to get help"
             dfb   $00
SPLGO        asc   "press any key to continue"
             dfb   $00

             dum   $1440            ; $1400-$143F are taken; see design.md
SPLI         ds    1                ; which line is being drawn
             dend

*--- $1441-$1442 are machine.S's and $1443 is file.S's
             dum   $1444
SPLLEN       ds    1                ; length of the line being centred
             dend
