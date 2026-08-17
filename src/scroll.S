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
* CURLINE -- LINENO = the buffer line the cursor is on, counting from zero.
*            Scans the text before the gap; the gap itself is the cursor.
*--------------------------------------
CURLINE      lda   #$00
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
SCROLLFIX    jsr   CURLINE

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
