*--------------------------------------
* SCROLL.S -- viewport tracking and long-range navigation
*
* SCROLLTOP is the buffer line drawn on the first text row. RENDER walks the
* whole buffer either way, so skipping the lines above the viewport costs
* nothing extra -- no line index is needed to scroll, only to make the walk
* cheaper. That is a separate job.
*
* Line numbers are 16-bit: the buffer holds roughly 780 lines of wrapped prose,
* comfortably past what a byte can count.
*--------------------------------------

*--------------------------------------
* CALCLINE -- LINENO = the cursor's line, counted the slow way by scanning all
*             the text before the gap.
*
* No longer on the redraw path: CURLNO is maintained incrementally by the
* buffer primitives, since every operation that crosses a newline already has
* that byte in hand. Kept as the authority for resynchronising after bulk
* changes, and as the reference an incremental counter can drift from.
*--------------------------------------
CALCLINE     lda   #$00
             sta   LINENO
             sta   LINENO+1
             sta   AUXPTR
             lda   #BUFLO
             sta   AUXPTR+1
:loop        lda   AUXPTR
             cmp   GAPBEG
             bne   :rd
             lda   AUXPTR+1
             cmp   GAPBEG+1
             beq   :done
:rd          ldy   #$00
             jsr   AUXRD
             cmp   #TEXTLO
             bcs   :next
             inc   LINENO
             bne   :next
             inc   LINENO+1
:next        inc   AUXPTR
             bne   :loop
             inc   AUXPTR+1
             jmp   :loop
:done        rts

*--------------------------------------
* SCROLLFIX -- move the viewport the minimum needed to keep the cursor on
*              screen. Called before every redraw.
*--------------------------------------
SCROLLFIX    lda   CURLNO
             sta   LINENO
             lda   CURLNO+1
             sta   LINENO+1

*--- cursor above the viewport? pull the viewport up to it
             lda   LINENO+1
             cmp   SCROLLTOP+1
             bcc   :up
             bne   :below
             lda   LINENO
             cmp   SCROLLTOP
             bcc   :up

*--- cursor at or past the bottom? push the viewport down
:below       lda   SCROLLTOP        ; last visible line + 1
             clc
             adc   MAXROW
             sta   TMPA
             lda   SCROLLTOP+1
             adc   #$00
             sta   TMPB

             lda   LINENO+1
             cmp   TMPB
             bcc   :done
             bne   :down
             lda   LINENO
             cmp   TMPA
             bcc   :done

:down        lda   LINENO           ; SCROLLTOP = LINENO - MAXROW + 1
             sec
             sbc   MAXROW
             sta   SCROLLTOP
             lda   LINENO+1
             sbc   #$00
             sta   SCROLLTOP+1
             inc   SCROLLTOP
             bne   :done
             inc   SCROLLTOP+1
:done        rts

:up          lda   LINENO
             sta   SCROLLTOP
             lda   LINENO+1
             sta   SCROLLTOP+1
             rts

*--------------------------------------
* KTOP / KEND -- start and end of the document (OA-< and OA->)
*--------------------------------------
KTOP         jsr   GAPLEFT
             bcc   KTOP
             rts

KEND         jsr   GAPRIGHT
             bcc   KEND
             rts

*--------------------------------------
* KPGUP / KPGDN -- a screenful at a time (OA-up and OA-down)
*
* Built on the single-line movers rather than on the line index, which does not
* exist yet. Slow but correct, and it will get faster for free when it does.
*--------------------------------------
KPGUP        lda   MAXROW
             sta   PGCNT
:loop        jsr   KUP
             dec   PGCNT
             bne   :loop
             rts

KPGDN        lda   MAXROW
             sta   PGCNT
:loop        jsr   KDOWN
             dec   PGCNT
             bne   :loop
             rts

*--------------------------------------
* RENDERROW -- repaint only the line the cursor is on
*
* The whole point of the exercise: ordinary typing changes exactly one screen
* row, but RENDER repaints all 23, and measurement showed that repaint -- not
* the buffer walk -- is what costs ~100 ms per keystroke.
*
* Safe only when the line structure and the viewport are both unchanged, which
* the caller checks. Handlers opt in by setting FASTDRAW; anything that might
* alter more than one row simply does not, and gets the full redraw.
*--------------------------------------
RENDERROW    jsr   CLRBUF

*--- the line begins exactly CCOL bytes before the cursor, so there is nothing
*    to search for; that scan used to cost as much as the drawing did
             lda   GAPBEG
             sec
             sbc   CCOL
             sta   AUXPTR
             lda   GAPBEG+1
             sbc   #$00
             sta   AUXPTR+1

             lda   CCOL
             sta   CURSCOL
             beq   :post
             sta   BLKLEN
             lda   #<LINEBUF
             sta   DSTPTR
             lda   #>LINEBUF
             sta   DSTPTR+1
             ldy   #$00
             jsr   AUXBLK           ; one bank switch for the whole run

*--- the rest of the line resumes past the gap
:post        lda   GSCRW
             sec
             sbc   CCOL
             sta   BLKLEN
             beq   :draw

*--- do not read past the end of the buffer
             lda   #$00
             sec
             sbc   GAPEND
             sta   TMPA
             lda   #BUFHI
             sbc   GAPEND+1
             bne   :room            ; 256+ bytes left, the cap already fits
             lda   TMPA
             cmp   BLKLEN
             bcs   :room
             sta   BLKLEN
:room        lda   BLKLEN
             beq   :draw

             lda   GAPEND
             sta   AUXPTR
             lda   GAPEND+1
             sta   AUXPTR+1
             lda   #<LINEBUF
             clc
             adc   CCOL
             sta   DSTPTR
             lda   #>LINEBUF
             adc   #$00
             sta   DSTPTR+1
             ldy   #$00
             jsr   AUXBLK

*--- that copy ran past the end of the line, so blank from the newline on.
*    Scanning main memory costs nothing next to reading aux a byte at a time.
             ldx   CCOL
:scan        cpx   GSCRW
             bcs   :draw
             lda   LINEBUF,x        ; buffer bytes, so any break ends the row
             cmp   #TEXTLO
             bcc   :blank
             inx
             bne   :scan
:blank       lda   #$a0
:bl          sta   LINEBUF,x
             inx
             cpx   GSCRW
             bcc   :bl

:draw        lda   CURLNO
             sec
             sbc   SCROLLTOP
             sta   CURSROW
             cmp   MAXROW
             bcs   :done
             jsr   DRAWLINE
             jmp   SHOWCURSOR
:done        rts
