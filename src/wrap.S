*--------------------------------------
* WRAP.S -- hard wrap on entry, and paragraph reflow
*
* Typing past column WRAPCOL breaks the line at the last space before the
* cursor. Because Markdown renders a single newline inside a paragraph as a
* space, the file reads identically to unwrapped prose -- but every logical
* line is one screen row, which is what keeps the display layer simple.
*
* Wrapping is done by editing the buffer, not by decorating the display: the
* newline is a real byte, and it is what gets saved.
*--------------------------------------

*--------------------------------------
* COLUMN -- A = characters between the start of the current line and the
*           cursor. Scans backwards through aux without moving the gap.
*           Saturates at 255, which is well past any column we care about.
*--------------------------------------
COLUMN       lda   #$00
             sta   TMPC
             lda   GAPBEG
             sta   AUXPTR
             lda   GAPBEG+1
             sta   AUXPTR+1
:loop        lda   AUXPTR+1         ; start of buffer?
             cmp   #AUXLO
             bne   :dec
             lda   AUXPTR
             beq   :done
:dec         lda   AUXPTR
             bne   :d1
             dec   AUXPTR+1
:d1          dec   AUXPTR
             ldy   #$00
             jsr   AUXRD
             cmp   #$8d             ; start of line
             beq   :done
             inc   TMPC
             beq   :done            ; saturate rather than wrap round
             jmp   :loop
:done        lda   TMPC
             rts

*--------------------------------------
* FINDSPC -- distance back from the cursor to the last space on this line.
*            Carry clear and TMPB = distance if found; carry set if the line
*            has no space before the cursor (one very long word).
*--------------------------------------
FINDSPC      lda   #$00
             sta   TMPB
             lda   GAPBEG
             sta   AUXPTR
             lda   GAPBEG+1
             sta   AUXPTR+1
:loop        lda   AUXPTR+1
             cmp   #AUXLO
             bne   :dec
             lda   AUXPTR
             beq   :none            ; ran back to the start of the buffer
:dec         lda   AUXPTR
             bne   :d1
             dec   AUXPTR+1
:d1          dec   AUXPTR
             inc   TMPB
             ldy   #$00
             jsr   AUXRD
             cmp   #$8d
             beq   :none            ; reached line start without a space
             cmp   #$a0
             beq   :found
             lda   TMPB
             cmp   #$fe
             bcs   :none
             jmp   :loop
:found       clc
             rts
:none        sec
             rts

*--------------------------------------
* DOWRAP -- break the current line at the last space before the cursor,
*           leaving the cursor on the same character it started on.
*
* The space becomes the newline, so no bytes are gained or lost and the text
* either side is untouched.
*--------------------------------------
DOWRAP       jsr   FINDSPC
             bcs   :hard

             ldx   TMPB             ; step back to just after the space
             dex
             stx   WDIST
             beq   :atspace
:back        jsr   GAPLEFT
             dec   WDIST
             bne   :back

:atspace     jsr   DELBACK          ; drop the space
             lda   #$8d
             jsr   INSCHR           ; put a newline in its place

             ldx   TMPB             ; and return to where we were
             dex
             stx   WDIST
             beq   :done
:fwd         jsr   GAPRIGHT
             dec   WDIST
             bne   :fwd
:done        rts

*--- a single word longer than the margin: break it where the cursor stands
:hard        lda   #$8d
             jmp   INSCHR

*--------------------------------------
* WRAPCHECK -- called after inserting a printable character
*--------------------------------------
WRAPCHECK    jsr   COLUMN
             cmp   #WRAPCOL+1
             bcc   :done
             jmp   DOWRAP
:done        rts

*--------------------------------------
* PEEK2 -- the byte one past the cursor, without moving it.
*          Carry set if there are fewer than two bytes ahead.
*--------------------------------------
PEEK2        lda   GAPEND
             clc
             adc   #$01
             sta   AUXPTR
             lda   GAPEND+1
             adc   #$00
             sta   AUXPTR+1
             cmp   #AUXHI
             bcs   :none
             ldy   #$00
             jsr   AUXRD
             clc
             rts
:none        sec
             rts

*--------------------------------------
* PARASTART -- move the cursor to the first character of this paragraph.
*              A paragraph ends at a blank line or at the buffer edge.
*--------------------------------------
PARASTART    jsr   BOL
             jsr   PEEKBACK
             bcs   :done            ; start of buffer
*--- the byte before a line start is the CR ending the line above
             jsr   GAPLEFT
             jsr   PEEKBACK
             bcs   :after           ; that CR was the first byte in the buffer
             cmp   #$8d
             beq   :after           ; blank line above: paragraph starts below
             jmp   PARASTART        ; previous line is prose, keep going up
:after       jsr   GAPRIGHT         ; step forward over the CR
:done        rts

*--------------------------------------
* REFLOW -- rejoin and re-wrap the paragraph around the cursor (OA-R)
*
* Walks forward from the paragraph start. A newline with prose after it is a
* join, so it becomes a space; the wrap check then breaks the line wherever it
* now needs breaking. A blank line ends the paragraph.
*--------------------------------------
REFLOW       jsr   PARASTART
:loop        jsr   PEEKFWD
             bcs   :done            ; end of buffer
             cmp   #$8d
             bne   :char

*--- a newline: join unless the paragraph ends here
             jsr   PEEK2
             bcs   :done            ; newline is the last byte
             cmp   #$8d
             beq   :done            ; blank line: paragraph ends
             jsr   DELFWD
             lda   #$a0
             jsr   INSCHR
             jmp   :check

:char        jsr   GAPRIGHT

:check       jsr   COLUMN
             cmp   #WRAPCOL+1
             bcc   :loop
             jsr   DOWRAP
             jmp   :loop
:done        rts
