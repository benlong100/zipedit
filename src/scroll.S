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
             lda   #AUXLO
             sta   AUXPTR+1
:loop        lda   AUXPTR
             cmp   GAPBEG
             bne   :rd
             lda   AUXPTR+1
             cmp   GAPBEG+1
             beq   :done
:rd          ldy   #$00
             jsr   AUXRD
             cmp   #$8d
             bne   :next
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

*--- walk back to the start of the line, counting what is behind the cursor
             lda   GAPBEG
             sta   AUXPTR
             lda   GAPBEG+1
             sta   AUXPTR+1
             lda   #$00
             sta   TMPC
:back        lda   AUXPTR+1
             cmp   #AUXLO
             bne   :step
             lda   AUXPTR
             beq   :atstart
:step        lda   AUXPTR
             bne   :s1
             dec   AUXPTR+1
:s1          dec   AUXPTR
             ldy   #$00
             jsr   AUXRD
             cmp   #$8d
             bne   :count
             inc   AUXPTR           ; stand just past the newline
             bne   :atstart
             inc   AUXPTR+1
             jmp   :atstart
:count       inc   TMPC
             lda   TMPC
             cmp   #SCRW
             bcc   :back            ; clamp at the screen width

:atstart     lda   TMPC
             sta   CURSCOL

*--- everything on this line before the cursor is contiguous before the gap
             ldx   #$00
:pre         cpx   TMPC
             beq   :post
             ldy   #$00
             jsr   AUXRD
             sta   LINEBUF,x
             inx
             inc   AUXPTR
             bne   :pre
             inc   AUXPTR+1
             jmp   :pre

*--- the rest of the line resumes after the gap
:post        lda   GAPEND
             sta   AUXPTR
             lda   GAPEND+1
             sta   AUXPTR+1
:ploop       cpx   #SCRW
             bcs   :draw
             lda   AUXPTR+1
             cmp   #AUXHI
             bcs   :draw
             ldy   #$00
             jsr   AUXRD
             cmp   #$8d
             beq   :draw
             sta   LINEBUF,x
             inx
             inc   AUXPTR
             bne   :ploop
             inc   AUXPTR+1
             jmp   :ploop

*--- CURLNO - SCROLLTOP is the screen row; both fit a byte once on screen
:draw        lda   CURLNO
             sec
             sbc   SCROLLTOP
             sta   CURSROW
             cmp   MAXROW
             bcs   :done
             jsr   DRAWLINE
             jmp   SHOWCURSOR
:done        rts
