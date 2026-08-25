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
* CALCCOL -- CCOL = characters between the start of the current line and the
*            cursor, counted the slow way by scanning back through aux.
*
* Off the hot path: CCOL is maintained incrementally by the buffer primitives.
* This is only called when the cursor crosses back onto a previous line, where
* the new column genuinely has to be discovered.
*
* Counts in sixteen bits, and writes CCOL itself rather than returning a byte
* in A. It used to count in one byte and claim to saturate -- but `inc TMPC /
* beq :done` returns ZERO on the 256th character, not $ff, so a line long
* enough to reach here came back as column 1 on the status row and every wrap
* decision taken from it was made on a lie. Nothing could build a line that
* long while the wrap check saw every insert; PASTE can.
*--------------------------------------
CALCCOL      lda   #$00
             sta   CCOL
             sta   CCOL+1
             lda   GAPBEG
             sta   AUXPTR
             lda   GAPBEG+1
             sta   AUXPTR+1
:loop        lda   AUXPTR+1         ; start of buffer?
             cmp   #BUFLO
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
             inc   CCOL
             bne   :loop
             inc   CCOL+1
             jmp   :loop
:done        rts

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
             cmp   #BUFLO
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
DOWRAP       lda   #$00
             sta   DWHARD
             jsr   FINDSPC
             bcs   :hard

             ldx   TMPB             ; step back to just after the space
             dex
             stx   WDIST
             beq   :atspace
:back        lda   KBD              ; DOWRAP steps back to the space
             bpl   *+5
             jsr   KBPOLL
             jsr   GAPLEFT
             dec   WDIST
             bne   :back

:atspace     jsr   DELBACK          ; drop the space
             lda   #SOFTCR          ; a break that stands in for that space,
             jsr   INSCHR           ; and becomes one again when saved

*--- where that break landed, for REFLOWHERE's stability test. INSCHR left
*    GAPBEG one past it, and no bytes were gained or lost, so this offset is
*    directly comparable with one recorded before the reflow started.
             lda   GAPBEG
             sec
             sbc   #$01
             sta   DWBRK
             lda   GAPBEG+1
             sbc   #$00
             sta   DWBRK+1

             ldx   TMPB             ; and return to where we were
             dex
             stx   WDIST
             beq   :done
:fwd         lda   KBD              ; and forward again afterwards
             bpl   *+5
             jsr   KBPOLL
             jsr   GAPRIGHT
             dec   WDIST
             bne   :fwd
:done        rts

*--- a single word longer than the margin: break it where the cursor stands.
*    Nothing was removed to make room, so this one saves as nothing at all --
*    otherwise a long URL would come back with a space through the middle.
:hard        inc   DWHARD           ; this one adds a byte; the caller has to
                                    ; know, or its walk home comes up short
             lda   #$fe             ; a bare break is not byte-preserving, so
             sta   DWBRK            ; nothing below it can be compared. NOT the
             lda   #$ff             ; $ffff REFLOWHERE starts RTBRK at: these
             sta   DWBRK+1          ; two sentinels must never test equal, or a
                                    ; word longer than the margin would read as
                                    ; a break landing back where it was and
                                    ; stop the reflow dead
             lda   #SOFTWD
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
*
* Two things keep that from being the whole remainder. REFLOWHERE stops as
* soon as a break lands back on a byte that already held one, because a line
* wraps according to where the break above it is and nothing else, so from
* there down the paragraph is provably already right. And the walk back uses
* GAPLQ rather than GAPLEFT, since the reflow cannot move the line the cursor
* is on or its column within it: both are saved here and put back, instead of
* being recounted a line at a time on the way home.
*
* What is left is real work. Inserting a character into a filled paragraph
* pushes a word onto the next line, which pushes a word onto the one after,
* and in tightly set prose that cascade genuinely does run to the end of the
* paragraph -- every line below the cursor changes and has to be redrawn.
* Measured worst case at 1MHz: a 2,000 character paragraph costs ~190ms a
* keystroke, against ~30ms where nothing wraps.
*--------------------------------------
*--- RTFWDALL -- the same walk, with the early stop switched off.
*
*    REFLOWHERE normally stops the moment a break lands back on a byte that
*    already held one, because a line wraps according to where the break above
*    it is and nothing else -- so from there down the paragraph is provably
*    already right. That proof depends on everything below being right to begin
*    with, which is exactly what a deferred tidy breaks: several breaks below
*    may be wrong at once, and the first one that happens to land where it was
*    would stop the walk and strand the rest. A burst left "hotel", "india" and
*    "juliet" sitting on lines of their own.
RTFWDALL     lda   #$00
             sta   RTSTOP
             jmp   RTFWDGO

RTFWD        lda   #$01             ; typing: stop as soon as what lies below
             sta   RTSTOP           ; the cursor is provably unchanged

RTFWDGO      lda   GAPBEG
             sta   RTPOS
             lda   GAPBEG+1
             sta   RTPOS+1

*--- The reflow only ever touches breaks below the cursor, so the line the
*    cursor is on and its column within that line both come out of this
*    unchanged. Keeping them means the walk back does not have to recount.
             lda   CCOL
             sta   RTCOL
             lda   CURLNO
             sta   RTLINE
             lda   CURLNO+1
             sta   RTLINE+1

             lda   #$01
             sta   PARTIAL          ; nothing above the cursor can move
             jsr   REFLOWHERE       ; leaves the cursor wherever it settled

:back        lda   GAPBEG           ; walk back to where we started
             cmp   RTPOS
             bne   :step
             lda   GAPBEG+1
             cmp   RTPOS+1
             beq   :put
:step        jsr   GAPLQ            ; no accounting: we know the answer
             jmp   :back

*--- RTCOL is one byte and that is sufficient: RTFWD is only ever entered from
*    WRAPCHECK immediately after DOWRAP, which either breaks at the last space
*    before the cursor or drops a SOFTWD on it, so the column here is always
*    below the margin. The high byte still has to be put back, because the
*    reflow just walked GAPRIGHT over lines long enough to have set it.
:put         lda   RTCOL
             sta   CCOL
             lda   #$00
             sta   CCOL+1
             lda   RTLINE
             sta   CURLNO
             lda   RTLINE+1
             sta   CURLNO+1
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
* RTFAST / RTFASTALL -- reflow forward from the cursor WITHOUT moving it
*
* The same job as RTFWD, done by reading rather than by walking. RTFWD drags
* the gap through the whole paragraph a byte at a time and then drags it all
* the way back, and every one of those steps is a banked aux read AND a banked
* aux write: about four accesses per byte to change perhaps ten of them. At
* 1MHz that is ~360ms on one keystroke in six, which is a word-sized hole in a
* keyboard that latches one key.
*
* But a reflow is byte-preserving in the ordinary case. A SOFTCR stood in for
* a space, so turning it back is a ONE BYTE overwrite; breaking a line at a
* space is another. Neither needs the gap moved at all. So this scans forward
* with AUXPTR, counts columns as it goes, and pokes only the bytes that differ
* -- one read per byte, no write-back, and no walk home, because the cursor
* never moved and CCOL and CURLNO come out untouched.
*
* Two cases are not byte-preserving and hand back to RTFWD: a SOFTWD, which
* stood in for nothing so removing it shifts everything below, and a line with
* no space to break at, which needs one inserted. Both are rare, both are
* already handled correctly by the old path, and the partial work done here
* costs nothing because a reflow is idempotent -- RTFWD simply starts again
* from the same cursor.
*--------------------------------------
RTFASTALL    lda   #$00             ; no early stop: several breaks may be wrong
             sta   RTSTOP
             beq   RTFASTGO         ; always taken

RTFAST       lda   #$01             ; typing: stop once the rest is provably right
             sta   RTSTOP

RTFASTGO     lda   #$01
             sta   PARTIAL          ; nothing above the cursor can move
             lda   #$00
             sta   FASTDRAW         ; the paragraph moved: full redraw

*--- start at the first byte past the gap, at the cursor's own column
             lda   GAPEND
             sta   RFP
             lda   GAPEND+1
             sta   RFP+1
             lda   CCOL
             sta   RFCOL
             lda   CCOL+1
             sta   RFCOL+1
             lda   #$ff             ; no space and no consumed break yet. Aux
             sta   RFSP+1           ; runs to $BFFF, so a high byte of $ff can
             sta   RFBRK+1          ; never be a real address
             sta   RFSP
             sta   RFBRK

*--- catch anything struck while this walk runs; the latch holds only one
:loop        lda   KBD
             bpl   :nokey
             jsr   KBPOLL
:nokey       lda   RFP+1
             cmp   #BUFHI
             bcc   *+5              ; ran off the end of the buffer
             jmp   :fin
             jsr   :point
             jsr   AUXRD
             sta   RFB
             cmp   #TEXTLO
             bcs   :text

*--- a break of some kind. A blank line after it ends the paragraph, whichever
*    kind it is.
             jsr   :peek2
             bcc   *+5              ; that break was the last byte
             jmp   :fin
             cmp   #TEXTLO
             bcs   *+5              ; blank line: the paragraph ends here
             jmp   :fin
             lda   RFB
             cmp   #HARDCR
             beq   :hard
             cmp   #SOFTCR
             beq   *+5              ; SOFTWD: changes the length
             jmp   :slow

*--- a soft wrap becomes the space it stood in for, in place
             jsr   :point
             lda   #$a0
             jsr   PUTAUX
             lda   #$01
             sta   MODFLAG
             lda   RFP              ; it counts as a space, and as the break
             sta   RFSP             ; this line used to end at
             sta   RFBRK
             lda   RFP+1
             sta   RFSP+1
             sta   RFBRK+1
             jmp   :count

*--- a return the writer typed ends the line no matter what is above it, so
*    while typing there is nothing below one left to do
:hard        lda   RTSTOP
             beq   *+5
             jmp   :fin
             lda   #$00             ; a full reflow carries on into it
             sta   RFCOL
             sta   RFCOL+1
             lda   #$ff
             sta   RFSP+1
             sta   RFBRK+1
             jmp   :next

:text        cmp   #$a0
             bne   :count
             lda   RFP              ; remember where the space was
             sta   RFSP
             lda   RFP+1
             sta   RFSP+1

:count       inc   RFCOL
             bne   :margin
             inc   RFCOL+1
:margin      lda   RFCOL+1
             bne   :wrap
             lda   RFCOL
             cmp   GWRAP1
             bcc   :next

*--- past the margin: the break belongs at the last space on this line
:wrap        lda   RFSP+1
             cmp   #$ff
             bne   *+5              ; no space to break at: needs a bare break
             jmp   :slow
             lda   RFSP
             sta   AUXPTR
             lda   RFSP+1
             sta   AUXPTR+1
             lda   #SOFTCR
             ldy   #$00
             jsr   PUTAUX
             lda   #$01
             sta   MODFLAG

*--- the new line starts after that space, so the byte just counted stands
*    RFP-RFSP characters into it
             lda   RFP
             sec
             sbc   RFSP
             sta   RFCOL
             lda   RFP+1
             sbc   RFSP+1
             sta   RFCOL+1

*--- did the break land back on the byte that already held one? Then every
*    line below it is already exactly right and there is nothing left to do.
             lda   RTSTOP
             beq   :clear
             lda   RFSP
             cmp   RFBRK
             bne   :clear
             lda   RFSP+1
             cmp   RFBRK+1
             bne   *+5
             jmp   :fin
:clear       lda   #$ff
             sta   RFSP+1
             sta   RFBRK+1

:next        inc   RFP
             bne   *+5              ; both paths end at the jmp below
             inc   RFP+1
             jmp   :loop

:fin         rts

*--- hand back to the walking version, which handles the length-changing cases
:slow        lda   RTSTOP
             beq   :slowall
             jmp   RTFWD
:slowall     jmp   RTFWDALL

*--- AUXPTR = RFP
:point       lda   RFP
             sta   AUXPTR
             lda   RFP+1
             sta   AUXPTR+1
             ldy   #$00
             rts

*--- A = the byte after RFP, carry set if that is past the end of the buffer
:peek2       lda   RFP
             clc
             adc   #$01
             sta   AUXPTR
             lda   RFP+1
             adc   #$00
             sta   AUXPTR+1
             cmp   #BUFHI
             bcs   :p2end
             ldy   #$00
             jsr   AUXRD
             clc
             rts
:p2end       sec
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
WRAPCHECK    lda   CCOL+1
             bne   :over            ; past column 255, so past the margin too:
             lda   CCOL             ; only PASTE can build a line this long, and
             cmp   GWRAP1           ; the byte compare below cannot see it
             bcc   :look            ; the cursor is still short of the margin
:over        jsr   DOWRAP           ; past it: break behind us, as it always did
             jmp   RTFAST           ; and tidy what follows, same as the other path
:look

*--- room left on this line before the margin
             lda   GWRAP1
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
             lda   #BUFHI
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
:fwd         lda   KBD              ; the walk out to the margin
             bpl   *+5
             jsr   KBPOLL
             lda   WSTEP
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
*--- The walk out to the margin is undone by walking the same distance back --
*    but only if the wrap put no bytes in the way. A break that stands in for a
*    space is one byte for one, so the distance holds; a bare break inside a
*    long word is a byte that was not there before, and one of the steps home
*    gets spent stepping over it. The cursor then comes to rest one character
*    late, and the NEXT character typed goes in one place further along than it
*    should -- so a word longer than the margin, typed into the middle of a
*    paragraph, laid its letters down alternating with the text already there.
*    "jumps" and a run of a's came back from the disk as "jauamaaaaaaaaaaps".
:brk         jsr   DOWRAP
             lda   DWHARD           ; before RTFWD, which wraps on its own
             sta   WSTEP            ; account and would overwrite this

*--- Put the tidy-up off while the writer is still mid-word.
*
*    This is where the time goes. Measured at 1MHz, typing into the middle of a
*    twelve-line paragraph costs 83ms a character; with this RTFWD removed
*    altogether it costs 23ms. The reflow is ~72% of it, about 360ms on the one
*    keystroke in six that actually breaks a line -- and the Apple II keyboard
*    latches exactly ONE key, so everything struck inside that 360ms is lost.
*    That is why a burst into a long paragraph loses whole words: the stall is
*    word-sized.
*
*    The redraw is NOT the problem, though it looks like it: a full RENDER
*    measures 2-3ms here. The 138/214ms figures that suggested otherwise were
*    taken with the arrow keys, which move the cursor a whole line as well as
*    repainting, and the movement is nearly all of it.
*
*    So if the next key is already waiting AND is a printable character, the
*    writer has not finished the word. Leave the paragraph ragged -- a pushed
*    word sitting on a short line of its own -- and tidy at the next pause.
*    Only printable keys defer: a command or an arrow tidies first, so the
*    cursor never moves away from a mess and leaves it behind.
*
*    The text is correct either way, so this cannot reach the file: a reflow
*    only moves breaks about, and SOFTCR saves as the space it replaced while
*    SOFTWD saves as nothing. A document saved mid-burst is byte-identical to
*    one saved after the tidy.
             jsr   KBNEXT
             bcs   :flow            ; nothing waiting: tidy now
             cmp   #TEXTLO
             bcc   :flow            ; a control key or an arrow
             cmp   #$ff             ; Delete
             bcs   :flow
             inc   FLOWOWED         ; count them: one deferred break still
                                    ; leaves everything below it right, and the
                                    ; cheap tidy can be used. Two or more and
                                    ; it cannot -- see the main loop.
*--- The break DOWRAP just made sits below the cursor, which leaves CURLNO
*    untouched -- so without this the main loop would take the one-row path and
*    never repaint the rows underneath, and the ragged text would be invisible
*    until something else forced a full redraw.
             lda   #$00
             sta   FASTDRAW
             beq   :hop             ; always taken
:flow        jsr   RTFAST           ; forward only: what is behind is already right
:hop         lda   WSTEP
             beq   :back
             jsr   GAPLEFT          ; one more, for the byte the break added
:back        lda   KBD              ; and the walk home from it
             bpl   *+5
             jsr   KBPOLL
             lda   WBACK
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
             cmp   #BUFHI
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
             lda   CCOL+1
             bne   :over
             lda   CCOL
             cmp   GWRAP1
             bcc   :loop
:over        jsr   DOWRAP           ; breaks behind us and returns the cursor
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
REFLOW       lda   #$00             ; OA-R rewraps whatever state the
             sta   RTSTOP           ; paragraph is in, so it never stops short
             jsr   PARASTART

*--- REFLOWHERE: the same loop, entered from wherever the cursor is. Everything
*    behind the cursor is already wrapped correctly, so tidying after an insert
*    only has to deal with what lies ahead of it.
REFLOWHERE   lda   #$ff             ; no break removed yet to compare against
             sta   RTBRK
             sta   RTBRK+1

*--- the walking fallback watches the keyboard too
:loop        lda   KBD
             bpl   :nok
             jsr   KBPOLL
:nok         jsr   PEEKFWD
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
             beq   :hardcr          ; the writer put this one here; keep it
             cmp   #SOFTCR
             bne   :bare            ; SOFTWD replaced nothing

*--- remember which byte this break sat on. A line wraps according to where
*    the break above it is and nothing else, so if the rewrap puts one back on
*    this same byte, every line below is already exactly right.
             lda   GAPBEG
             sta   RTBRK
             lda   GAPBEG+1
             sta   RTBRK+1
             jsr   DELFWD
             lda   #$a0             ; SOFTCR replaced a space; give it back
             jsr   INSCHR
             jmp   :check

*--- a bare break stood in for nothing, so removing it shifts every byte below
*    it up by one and no recorded offset means anything any more.
:bare        lda   #$ff
             sta   RTBRK
             sta   RTBRK+1
             jsr   DELFWD
             jmp   :check

*--- a return the writer typed ends the line no matter what is above it, so
*    while typing there is nothing below one left to do.
:hardcr      lda   RTSTOP
             beq   :char
             rts

:char        jsr   GAPRIGHT
:check       lda   CCOL+1
             bne   :over
             lda   CCOL
             cmp   GWRAP1
             bcc   :loop
:over        jsr   DOWRAP
             lda   RTSTOP
             beq   :loop            ; a full reflow carries on regardless
             lda   DWBRK            ; did the break land back where it was?
             cmp   RTBRK
             bne   :loop
             lda   DWBRK+1
             cmp   RTBRK+1
             bne   :loop
             rts                    ; then the rest of the paragraph stands

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

*--- $14a8-$14b5 is geom.S's; above that is free
             dum   $14b6
RFP          ds    2                ; RTFAST: where the scan has reached
RFCOL        ds    2                ; the column of the byte there
RFSP         ds    2                ; last space on this line, $ffxx if none
RFBRK        ds    2                ; the break this line used to end at
RFB          ds    1                ; the byte just read
             dend

             dum   $1447            ; $1446 is file.S's PENDSP
RTBRK        ds    2                ; REFLOWHERE: the break it last removed
DWBRK        ds    2                ; DOWRAP: where it last put one
RTSTOP       ds    1                ; reflow may stop once it is provably done
RTCOL        ds    1                ; RTFWD: the cursor's column across a reflow
RTLINE       ds    2                ; RTFWD: and the line it is on
DWHARD       ds    1                ; DOWRAP: that wrap added a byte
             dend
