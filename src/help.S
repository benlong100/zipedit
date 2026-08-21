*--------------------------------------
* HELP.S -- the keyboard command screens (OA-? , alias OA-H)
*
* NOT Ctrl-H: the //e keyboard encoder maps Ctrl-H and the left arrow to the
* same $88, exactly as it does Tab and Ctrl-I, so binding help there would cost
* the cursor-left key. Verified on the machine and asserted in the suite.
*
* OA-? opens this. The one-line cheat sheet moved to OA-/, the same physical
* key unshifted, which keeps the two mnemonically paired.
*
* TWO PAGES. One screen held every command at once and had run out of room --
* the selecting and clipboard columns had collided with no gap between them.
* OA-? now opens page one, a key turns to page two, and a key leaves. Both
* pages are the same 21-row box, so turning the page repaints in place and
* leaving needs nothing more than the full redraw the main loop already does.
*
* Page one is what you use while typing: moving, editing, selecting. Page two
* is what you reach for deliberately: markdown, clipboard, search, files and
* the screen toggles. The footer says which page you are on and what a key
* will do next, since nothing else on screen would tell you a second page
* exists.
*
* The border is MouseText, available at screen codes $40-$5F once the alternate
* character set is on. Probed rather than recalled -- and the first reading of
* the probe was wrong in a way only a real screen showed.
*
* $4C is a single stroke at the TOP of its cell. $5C is NOT a second rule at a
* different height: it draws TWO strokes, one at the top of its cell and one at
* the bottom, so a row of it renders as a double line. Using it for the top
* edge is what laid a stray line across the top of the screen, and using it
* under the title put two lines there. Every rule in this box is $4C, which
* sits hard against the row above it so the verticals descend cleanly from it.
*
* $5F is a clean vertical, drawn at the LEFT edge of its cell. Both ends of a
* rule row follow from that. The rule must START at the corner cell, or it
* begins a whole cell right of the vertical and never reaches it. It must END
* one cell short, letting the vertical own that cell, or it runs a whole cell
* past the corner. So a rule row is 63 rules then a vertical, and the closing
* bottom rule -- with nothing below it to carry a vertical -- is 63 rules and
* nothing else.
*
* MouseText has no corner or T-junction glyphs on this ROM -- $40-$4A are
* apples, a pointer, an hourglass, check marks and arrows -- so a corner is
* simply where a rule meets a vertical.
*
* Rows are emitted as raw screen codes, since MouseText cannot come from `asc`.
* The Open Apple key is drawn with its own glyph ($41) rather than spelt "OA",
* which is both truer to the keyboard and a column narrower.
*
* The rows below are GENERATED -- do not hand-edit the hex. Edit the layout in
* tools/genhelp.py and re-run it; it enforces the column stops and fails loudly
* if a description would overrun the border, which is exactly the mistake the
* one-page version shipped with.
*
* The box is 21 rows so it leaves the cheat sheet and status line showing
* underneath. Each row blanks the full screen width and paints the box in the
* middle.
*--------------------------------------
HELPCOL      equ   8
HELPN        equ   21
HELPPAGES    equ   2

*--------------------------------------
* HELPSHOW -- paint a page, wait for a key, then turn or leave
*--------------------------------------
HELPSHOW     lda   #$00
             sta   HELPPG
:page        lda   #$00
             sta   HELPI
:loop        lda   HELPI
             asl
             tay
             ldx   HELPPG
             bne   :two
             lda   HELPTBL1,y
             sta   STRPTR
             lda   HELPTBL1+1,y
             sta   STRPTR+1
             jmp   :draw
:two         lda   HELPTBL2,y
             sta   STRPTR
             lda   HELPTBL2+1,y
             sta   STRPTR+1
:draw        jsr   CLRBUF
             ldx   GHELPCOL
             jsr   BUFSTR
             lda   HELPI
             jsr   DRAWLINE
             inc   HELPI
             lda   HELPI
             cmp   #HELPN
             bne   :loop
             jsr   GETKEY           ; a key turns the page, and then leaves
             inc   HELPPG
             lda   HELPPG
             cmp   #HELPPAGES
             bne   :page
             rts

             dum   $1420
HELPI        ds    1
HELPPG       ds    1                ; which page is on screen, 0 or 1
             dend
