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
* CALCCOL -- A = characters between the start of the current line and the
*            cursor, counted the slow way by scanning back through aux.
*
* Off the hot path: CCOL is maintained incrementally by the buffer primitives.
* This is only called when the cursor crosses back onto a previous line, where
* the new column genuinely has to be discovered.
*--------------------------------------
CALCCOL       lda   #$00
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
             cmp   #TEXTLO          ; start of line
             bcc   :done
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
             cmp   #TEXTLO
             bcc   :none            ; reached line start without a space
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
             lda   #SOFTCR          ; a break that stands in for that space,
             jsr   INSCHR           ; and becomes one again when saved

             ldx   TMPB             ; and return to where we were
             dex
             stx   WDIST
             beq   :done
:fwd         jsr   GAPRIGHT
             dec   WDIST
             bne   :fwd
:done        rts

*--- a single word longer than the margin: break it where the cursor stands.
*    Nothing was removed to make room, so this one saves as nothing at all --
*    otherwise a long URL would come back with a space through the middle.
:hard        lda   #SOFTWD
             jmp   INSCHR

*--------------------------------------
* WRAPCHECK -- called after inserting a printable character
*--------------------------------------
WRAPCHECK    lda   CCOL
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
             bcs   :after           ; that break was the first byte in the buffer
             cmp   #TEXTLO
             bcc   :after           ; blank line above: paragraph starts below
             jmp   PARASTART        ; previous line is prose, keep going up
:after       jsr   GAPRIGHT         ; step forward over the CR
:done        rts

*--------------------------------------
* WRAPALL -- wrap the whole buffer to the margin, as if it had been typed
*
* A file on disk holds only the writer's returns, so every paragraph arrives as
* one long line. Walking the cursor forward and calling the same DOWRAP that
* the typing path calls puts our breaks back, marked as ours -- so a document
* is wrapped for the screen without the file ever having been.
*
* This is also what makes `make push` useful: an ordinary Markdown file written
* on the Mac now arrives here properly wrapped instead of as 400-column lines.
*--------------------------------------
WRAPALL      jsr   HOMECURSOR
:loop        jsr   PEEKFWD
             bcs   :done            ; end of buffer
             jsr   GAPRIGHT
             lda   CCOL
             cmp   #WRAPCOL+1
             bcc   :loop
             jsr   DOWRAP           ; breaks behind us and returns the cursor
             jmp   :loop
:done        jmp   HOMECURSOR

*--------------------------------------
* REFLOW -- rejoin and re-wrap the paragraph around the cursor (OA-R)
*
* Walks forward from the paragraph start, undoing our own wraps and letting the
* wrap check put them back where they now belong. A blank line ends it.
*
* Returns the writer typed are stepped over untouched. Reflow used to flatten
* every break in the paragraph, which was fine when they were all ours; now
* that we can tell them apart, an intentional line break survives a reflow.
*
* A SOFTCR stood in for a space and becomes one again. A SOFTWD stood in for
* nothing and simply goes.
*--------------------------------------
REFLOW       jsr   PARASTART
:loop        jsr   PEEKFWD
             bcs   :done            ; end of buffer
             cmp   #TEXTLO
             bcs   :char            ; ordinary text: walk on

*--- a break. Whatever kind it is, a blank line after it ends the paragraph.
             pha
             jsr   PEEK2
             bcs   :enddrop         ; the break is the last byte
             cmp   #TEXTLO
             bcc   :enddrop         ; blank line: the paragraph ends here
             pla

             cmp   #HARDCR
             beq   :char            ; the writer put this one here; keep it
             cmp   #SOFTCR
             bne   :bare            ; SOFTWD replaced nothing
             jsr   DELFWD
             lda   #$a0             ; SOFTCR replaced a space; give it back
             jsr   INSCHR
             jmp   :check
:bare        jsr   DELFWD
             jmp   :check

:char        jsr   GAPRIGHT
:check       lda   CCOL
             cmp   #WRAPCOL+1
             bcc   :loop
             jsr   DOWRAP
             jmp   :loop

:enddrop     pla
:done        rts
