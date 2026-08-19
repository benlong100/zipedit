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
* RTFLOW -- reflow the paragraph around the cursor, leaving the cursor put
*
* Used to tidy up after a burst of typing, not on every keystroke: reflowing
* per character measured 3 chars/sec, which is slower than the editor was
* before any of the redraw work.
*
* The cursor is restored by byte offset. Reflow is byte-count preserving: a
* SOFTCR becomes the space it stood in for, one byte for one byte, and a wrap
* takes a space back the same way.
*
* FASTDRAW has to go -- the whole paragraph has moved, and the one-row path
* would leave all of it stale.
*--------------------------------------
*--------------------------------------
* RTFWD -- reflow from the cursor to the end of the paragraph, cursor preserved
*
* The cheap tidy, used while typing. Everything behind the cursor is already
* right, so this walks forward once to reflow and back once to return -- over
* the remainder of the paragraph, not the whole of it.
*--------------------------------------
RTFWD        lda   GAPBEG
             sta   RTPOS
             lda   GAPBEG+1
             sta   RTPOS+1

             jsr   REFLOWHERE       ; leaves the cursor at the paragraph end

:back        lda   GAPBEG           ; walk back to where we started
             cmp   RTPOS
             bne   :step
             lda   GAPBEG+1
             cmp   RTPOS+1
             beq   :done
:step        jsr   GAPLEFT
             jmp   :back
:done        lda   #$00
             sta   FASTDRAW
             rts

*--------------------------------------
* RTFLOW -- reflow the whole paragraph around the cursor, cursor preserved
*--------------------------------------
RTFLOW       lda   GAPBEG
             sta   RTPOS
             lda   GAPBEG+1
             sta   RTPOS+1

             jsr   PARASTART
             lda   RTPOS
             sec
             sbc   GAPBEG
             sta   RTN
             lda   RTPOS+1
             sbc   GAPBEG+1
             sta   RTN+1

             jsr   REFLOW
             jsr   PARASTART

:fwd         lda   RTN
             ora   RTN+1
             beq   :done
             jsr   GAPRIGHT
             lda   RTN
             bne   :dec
             dec   RTN+1
:dec         dec   RTN
             jmp   :fwd
:done        lda   #$00
             sta   FASTDRAW
             rts

*--------------------------------------
* WRAPCHECK -- called after inserting a printable character
*
* The cursor's own column is not enough to go on. Insert into the middle of a
* line and the cursor sits far short of the margin while the LINE runs past it,
* and RENDER drops everything beyond column 80 -- so text simply disappears off
* the right edge until something reflows it.
*
* So look ahead down the rest of the line as well. The look-ahead only reads
* past the gap; it never moves the cursor, which is what keeps this cheap and
* keeps it clear of the gap-buffer bookkeeping. The cursor is only moved when
* the line really is too long, which is the rare case.
*
* Overflow is pushed onto a new line rather than flowed into the line below:
* that is what makes this affordable, and it is why OA-R exists.
*--------------------------------------
WRAPCHECK    lda   CCOL
             cmp   #WRAPCOL+1
             bcc   :look            ; the cursor is still short of the margin
             jsr   DOWRAP           ; past it: break behind us, as it always did
             jmp   RTFWD            ; and tidy what follows, same as the other path
:look

*--- room left on this line before the margin
             lda   #WRAPCOL+1
             sec
             sbc   CCOL
             sta   WLOOK
             sta   WBACK            ; the same distance, for the return trip

*--- how much text is left in the buffer at all. The scan below reads ahead
*    looking for a line end, and must not read past the end of the buffer: the
*    poison beyond it reads as text and every line near the end looks too long.
             lda   #$00
             sec
             sbc   GAPEND
             sta   WTMP
             lda   #AUXHI
             sbc   GAPEND+1
             bne   :room            ; 256+ bytes left, more than any look needs
             lda   WTMP             ; fewer than 256 bytes left
             cmp   WLOOK
             bcs   :room            ; still enough to scan the whole look
*--- Fewer bytes remain than there is room on the line, so the document runs
*    out before the margin does and this line CANNOT be too long. It used to
*    cap the look here and scan anyway -- but then a last line with no trailing
*    break reached the end of the look without meeting a line end, which is the
*    same condition as running out of margin, and it wrapped a line that fit.
*    A one-line document is the case you notice: every keystroke wrapped it.
             rts

*--- one block copy rather than a read per byte: about a third of the cost, and
*    this runs on every keystroke
:room        lda   GAPEND
             sta   AUXPTR
             lda   GAPEND+1
             sta   AUXPTR+1
             lda   WLOOK
             sta   BLKLEN
             lda   #<WSCAN
             sta   DSTPTR
             lda   #>WSCAN
             sta   DSTPTR+1
             ldy   #$00
             jsr   AUXBLK

             ldx   #$00
:scan        cpx   WLOOK
             bcs   :toolong         ; ran out of room without a line end
             lda   WSCAN,x
             cmp   #TEXTLO
             bcc   :done            ; met the line end: the line fits
             inx
             bne   :scan

*--- too long. Step out to the margin, break there, and step back. DOWRAP puts
*    the cursor back where it was called from, so the only distance to undo is
*    the one we walked out.
:toolong     lda   WBACK
             sta   WSTEP
:fwd         lda   WSTEP
             beq   :brk
             jsr   GAPRIGHT
             dec   WSTEP
             jmp   :fwd
*--- A break below the cursor leaves CURLNO untouched, so the main loop would
*    take the one-row path and never repaint the rows underneath: the text is
*    fine but the screen goes stale. The old wrap always moved the cursor onto
*    the new line, which changed CURLNO and forced the full redraw for free.
*--- A break leaves the pushed word on a stub line of its own, and another with
*    every further word. Tidying it later is no good: the mess is on screen for
*    the whole time you are typing, which is exactly when you are looking at it.
*    So reflow now -- but only here, on the keystroke that actually broke a
*    line, not on every character. Reflowing per character measured 3 chars/sec.
:brk         jsr   DOWRAP
             jsr   RTFWD            ; forward only: what is behind is already right
:back        lda   WBACK
             beq   :done
             jsr   GAPLEFT
             dec   WBACK
             jmp   :back
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

*--- REFLOWHERE: the same loop, entered from wherever the cursor is. Everything
*    behind the cursor is already wrapped correctly, so tidying after an insert
*    only has to deal with what lies ahead of it.
REFLOWHERE
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

             dum   $1450            ; $1400-$1441 are taken; see design.md
WLOOK        ds    1                ; WRAPCHECK: characters still to look at
WSTEP        ds    1                ; steps out to the margin
WBACK        ds    1                ; and the same number back
WTMP         ds    1                ; bytes left before the end of the buffer
WSCAN        ds    80               ; the rest of the line, staged in main
RTPOS        ds    2                ; RTFLOW: cursor offset before the reflow
RTN          ds    2                ; RTFLOW: how far into the paragraph it was
             dend
