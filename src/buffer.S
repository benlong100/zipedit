*--------------------------------------
* BUFFER.S -- the gap buffer
*
*   BUFLO*256                  GAPBEG      GAPEND            BUFHI*256
*     | text before cursor .......|<<< gap >>>|..... text after cursor |
*
* Insert and delete are O(1) -- move a gap edge. Cursor movement shuffles
* bytes across the gap, costing time proportional to the distance moved, which
* for an editor is almost always a line or less.
*
* Where the buffer lives, and how a byte in it is reached, is not this file's
* business. A memory driver supplies AUXRD, PUTAUX, AUXBLK, AUXFILL, INSTSTUB
* and UNHOOKRAM, and the bounds BUFLO and BUFHI: auxbuf.S puts the buffer in
* the //e's auxiliary bank, mainbuf.S puts it in main memory for a machine
* that has no auxiliary bank at all. Everything below is the same either way.
*--------------------------------------

*--------------------------------------
* BUFINIT -- empty buffer: the gap is the whole of aux $0800-$BFFF
*--------------------------------------
BUFINIT      lda   #$00
             sta   MODFLAG
             sta   CCOL
             sta   CURLNO
             sta   CURLNO+1
             sta   GAPBEG
             sta   GAPEND
             lda   #BUFLO
             sta   GAPBEG+1
             lda   #BUFHI
             sta   GAPEND+1
             rts

*--------------------------------------
* ATSTART -- carry set if the cursor is at the start of the buffer
*--------------------------------------
ATSTART      lda   GAPBEG+1
             cmp   #BUFLO
             bne   :no
             lda   GAPBEG
             bne   :no
             sec
             rts
:no          clc
             rts

*--------------------------------------
* ATEND -- carry set if the cursor is at the end of the buffer
*--------------------------------------
ATEND        lda   GAPEND+1
             cmp   #BUFHI
             bcc   :no
             sec
             rts
:no          clc
             rts

*--------------------------------------
* BUFFULL -- carry set if the gap is exhausted
*--------------------------------------
BUFFULL      lda   GAPBEG
             cmp   GAPEND
             bne   :no
             lda   GAPBEG+1
             cmp   GAPEND+1
             bne   :no
             sec
             rts
:no          clc
             rts

*--------------------------------------
* INSCHR -- insert the byte in A at the cursor. Carry set if the buffer is
*           full and nothing was stored.
*--------------------------------------
INSCHR       pha
             jsr   BUFFULL
             bcc   :ok
             pla
             sec
             rts
:ok          lda   GAPBEG
             sta   AUXPTR
             lda   GAPBEG+1
             sta   AUXPTR+1
             ldy   #$00
             pla
             jsr   PUTAUX
             ldx   #$01             ; mark dirty via X: A still holds the byte
             stx   MODFLAG
             cmp   #TEXTLO          ; inserting any break moves us down a line
             bcs   :samel
             inc   CURLNO
             bne   :col0
             inc   CURLNO+1
:col0        lda   #$00
             sta   CCOL
             beq   :adv
:samel       inc   CCOL
:adv         inc   GAPBEG
             bne   :done
             inc   GAPBEG+1
:done        clc
             rts

*--------------------------------------
* INSSTR -- insert a null-terminated high-ASCII string from STRPTR
*
* Y alone would cap this at 256 bytes, so when it wraps we carry into the high
* byte of STRPTR and keep going. STRPTR is left pointing into the string.
*--------------------------------------
INSSTR       ldy   #$00
:loop        lda   (STRPTR),y
             beq   :done
             sty   TMPC
             jsr   INSCHR
             ldy   TMPC
             bcs   :done            ; buffer full
             iny
             bne   :loop
             inc   STRPTR+1         ; next page of the string
             bne   :loop            ; always taken
:done        rts

*--------------------------------------
* DELBACK -- delete the byte before the cursor (Delete key)
*--------------------------------------
DELBACK      jsr   ATSTART
             bcc   :ok
             rts                    ; carry still set: nothing to delete
:ok          lda   #$01
             sta   MODFLAG
             jsr   PEEKBACK         ; what are we about to remove?
             cmp   #TEXTLO
             bcs   :samel
             lda   CURLNO
             bne   :dn
             dec   CURLNO+1
:dn          dec   CURLNO
             jsr   :shrink
             jsr   CALCCOL          ; joined a line: column must be recounted
             sta   CCOL
             clc
             rts
:samel       dec   CCOL
             jsr   :shrink
             clc
             rts

:shrink      lda   GAPBEG
             bne   :dec
             dec   GAPBEG+1
:dec         dec   GAPBEG
             rts

*--------------------------------------
* DELFWD -- delete the byte at the cursor (Ctrl-D)
*--------------------------------------
DELFWD       jsr   ATEND
             bcc   :ok
             rts
:ok          lda   #$01
             sta   MODFLAG
             inc   GAPEND
             bne   :done
             inc   GAPEND+1
:done        clc
             rts

*--------------------------------------
* GAPRIGHT -- move the cursor one byte right, shuffling a byte across the gap
*--------------------------------------
GAPRIGHT     jsr   ATEND
             bcc   :ok
             rts
:ok          lda   GAPEND           ; read the byte just past the gap
             sta   AUXPTR
             lda   GAPEND+1
             sta   AUXPTR+1
             ldy   #$00
             jsr   AUXRD
             tax
             lda   GAPBEG           ; write it at the gap start
             sta   AUXPTR
             lda   GAPBEG+1
             sta   AUXPTR+1
             txa
             jsr   PUTAUX
             cpx   #TEXTLO          ; stepped over a break: down a line
             bcs   :samel
             inc   CURLNO
             bne   :col0
             inc   CURLNO+1
:col0        lda   #$00
             sta   CCOL
             beq   :1
:samel       inc   CCOL
:1           inc   GAPBEG
             bne   :2
             inc   GAPBEG+1
:2           inc   GAPEND
             bne   :3
             inc   GAPEND+1
:3           clc
             rts

*--------------------------------------
* GAPLEFT -- move the cursor one byte left
*
* GAPLQ underneath it is the same move with none of the line and column
* bookkeeping: X comes back holding the byte, carry set if there was nothing
* to move. A caller that already knows where it will end up -- RTFWD walking
* back over its own reflow -- can use it and skip the accounting, which is not
* a micro-optimisation: the CALCCOL below rescans to the start of the line
* every time one is crossed, so an unaccounted walk back over twenty lines is
* twenty line-length scans shorter.
*--------------------------------------
GAPLEFT      jsr   GAPLQ
             bcs   :none            ; at the start of the buffer already
             cpx   #TEXTLO          ; stepped back over a break: up a line
             bcs   :samel
             lda   CURLNO
             bne   :4
             dec   CURLNO+1
:4           dec   CURLNO
             jsr   CALCCOL          ; back on a previous line: recount
             sta   CCOL
             clc
             rts
:samel       dec   CCOL
             clc
:none        rts

GAPLQ        jsr   ATSTART
             bcc   :ok
             rts                    ; ATSTART left the carry set
:ok          lda   GAPBEG           ; shrink both edges first
             bne   :1
             dec   GAPBEG+1
:1           dec   GAPBEG
             lda   GAPEND
             bne   :2
             dec   GAPEND+1
:2           dec   GAPEND

             lda   GAPBEG           ; read the byte now before the gap
             sta   AUXPTR
             lda   GAPBEG+1
             sta   AUXPTR+1
             ldy   #$00
             jsr   AUXRD
             tax
             lda   GAPEND           ; write it just past the gap
             sta   AUXPTR
             lda   GAPEND+1
             sta   AUXPTR+1
             txa
             jsr   PUTAUX
             clc
             rts

*--------------------------------------
* RENDER -- draw the buffer through the viewport
*
* Walks logical bytes, stepping over the gap, breaking lines on CR ($8D).
* Lines before SCROLLTOP are counted but not drawn; VIS goes true once we
* reach the viewport and stays true, so the test costs one byte compare per
* line rather than a 16-bit comparison per character.
*
* Rescanning from the buffer start is what this costs. Every line above the
* viewport is counted, one byte at a time through a banked read, before a
* single character is drawn -- 553ms an arrow key at line 112 against 218ms
* at line 1. See the note in main.S.
*--------------------------------------
RENDER       lda   #$00
             sta   AUXPTR
             sta   CURROW
             sta   CURCOL
             sta   CURSROW
             sta   CURSCOL
             sta   LINENO
             sta   LINENO+1
             sta   RPOS
             sta   RPOS+1
             sta   INSEL
             lda   SELACT
             beq   :nosel
             jsr   SELBOUNDS
:nosel
             lda   #BUFLO
             sta   AUXPTR+1

*--- Where the line at SCROLLTOP begins, if we know it. Counting down to it
*    from byte zero is the single most expensive thing the editor does: every
*    byte above the viewport read through a banked load, before one character
*    is drawn. Remembering the address turns that into nothing.
*
*    Three things have to hold. The remembered line has to be the one being
*    asked for; there must be no selection, whose bounds are logical positions
*    that only come out right if every byte is counted; and the address has to
*    still be behind the gap. That last one is what makes the rest safe --
*    editing happens at the gap, so bytes before it never move, and an address
*    below GAPBEG means the text there is exactly where it was left. Move the
*    cursor above the top line and the bytes shuffle across the gap, GAPBEG
*    drops below the address, and this falls back to counting.
             lda   SELACT
             bne   :count
             lda   TOPOK
             beq   :count
             lda   GAPBEG+1         ; TOPADDR <= GAPBEG?
             cmp   TOPADDR+1
             bcc   :count
             bne   :seek            ; NOT :fast -- the seek below is not
             lda   GAPBEG           ; optional, it is what makes the address
             cmp   TOPADDR          ; mean the line being asked for
             bcc   :count
:seek        jsr   TOPSEEK          ; walk it to the line being asked for
             bcs   :count
             lda   TOPADDR
             sta   AUXPTR
             lda   TOPADDR+1
             sta   AUXPTR+1
             lda   SCROLLTOP        ; and we are already that far down
             sta   LINENO
             lda   SCROLLTOP+1
             sta   LINENO+1
:count

*--- Drawing starts RSKIP rows down the viewport, and the rows above that are
*    counted and not drawn -- the same treatment the lines above SCROLLTOP get,
*    and the same one byte of test per line. RSKIP is normally zero; the typing
*    path sets it to the row the cursor was on, because a wrap rearranges the
*    text below the cursor and cannot touch a line above it.
             lda   SCROLLTOP
             clc
             adc   RSKIP
             sta   VISLINE
             lda   SCROLLTOP+1
             adc   #$00
             sta   VISLINE+1

*--- On the slow path LINENO is zero and this is the old test, "is the
*    viewport at the top". On the fast path the walk has already arrived, and
*    the first row drawn is the first row of the walk.
             lda   #$00
             sta   VIS
             lda   LINENO
             cmp   VISLINE
             bne   :setvis
             lda   LINENO+1
             cmp   VISLINE+1
             bne   :setvis
             lda   #$01
             sta   VIS
             lda   RSKIP
             sta   CURROW
:setvis      jsr   CLRBUF

:loop        lda   AUXPTR           ; standing at the gap? jump over it
             cmp   GAPBEG
             bne   :notgap
             lda   AUXPTR+1
             cmp   GAPBEG+1
             bne   :notgap
*--- the gap is the cursor, so this is where it lands on screen
             lda   CURROW
             sta   CURSROW
             lda   CURCOL
             sta   CURSCOL
             lda   GAPEND
             sta   AUXPTR
             lda   GAPEND+1
             sta   AUXPTR+1

:notgap      lda   AUXPTR+1         ; ran off the end of the buffer?
             cmp   #BUFHI
             bcc   :inbuf
             jmp   :done            ; :done is out of branch range from here
:inbuf

             ldy   #$00
             jsr   AUXRD
             sta   TMPA             ; keep it; the VIS test needs A

*--- the selection boundaries are logical positions, so this must run for
*    every byte, including ones above the viewport that are never drawn
             lda   SELACT
             beq   :notsel
             jsr   SELTEST
:notsel      lda   TMPA
             cmp   #TEXTLO          ; any break ends the line
             bcc   :eol

             ldx   CURCOL
             cpx   GSCRW
             bcs   :next            ; past the right margin, drop it
             lda   VIS
             beq   :bump            ; above the viewport: count, do not draw
             lda   INSEL
             beq   :plain
             lda   TMPA             ; selected: draw it inverse, in whatever
             jsr   INVCHR           ; way this character generator manages
             jmp   :store
:plain       lda   TMPA
:store       sta   LINEBUF,x
:bump        inc   CURCOL
             jmp   :next

*--- end of line
:eol         lda   VIS
             beq   :skipped
             lda   CURROW
             jsr   DRAWLINE
             inc   CURROW
             lda   CURROW
             cmp   MAXROW
             bcs   :fin             ; text area full
             jsr   CLRBUF
:skipped     lda   #$00
             sta   CURCOL
             inc   LINENO
             bne   :chkvis
             inc   LINENO+1

*--- have we just reached the first visible line?
:chkvis      lda   VIS
             bne   :next
             lda   LINENO
             cmp   VISLINE
             bne   :next
             lda   LINENO+1
             cmp   VISLINE+1
             bne   :next
             lda   #$01
             sta   VIS
             lda   RSKIP            ; the first row drawn is the first row NOT
             sta   CURROW           ; skipped, not the top of the screen

*--- Reaching the viewport the slow way is what teaches us where it starts, so
*    that the next render need not. Only with RSKIP zero, since only then is
*    the line just reached SCROLLTOP's own. AUXPTR still sits on the break
*    that ended the line above, and the line begins one past it.
             lda   RSKIP
             bne   :nocache
             lda   AUXPTR
             clc
             adc   #$01
             sta   TOPADDR
             lda   AUXPTR+1
             adc   #$00
             sta   TOPADDR+1
             lda   SCROLLTOP
             sta   TOPLINE
             lda   SCROLLTOP+1
             sta   TOPLINE+1
             lda   #$01
             sta   TOPOK
:nocache

:next        inc   RPOS             ; one more logical byte consumed
             bne   :rp
             inc   RPOS+1
:rp          inc   AUXPTR
             bne   :back            ; :loop is out of branch range now
             inc   AUXPTR+1
:back        jmp   :loop

:done        lda   VIS              ; flush a partial final line
             beq   :fin
             lda   CURCOL
             beq   :fin
             lda   CURROW
             cmp   MAXROW
             bcs   :fin
             lda   CURROW
             jsr   DRAWLINE

*--- that row is now spoken for. Without this, BLANKTAIL starts at CURROW and
*    erases the line RENDER just drew: a document whose last line has no
*    trailing return would lose it on every full redraw, and only get it back
*    from the one-row path the next time a key was pressed.
             inc   CURROW
:fin         lda   #$00             ; spent: the next render draws the lot
             sta   RSKIP
             rts

*--------------------------------------
* TOPSEEK -- bring TOPADDR from TOPLINE to SCROLLTOP. Carry clear if it got
*            there; set if the caller should count from the buffer start.
*
* Scrolling is what makes the remembered address worth keeping. Moving the
* cursor down a line at the foot of the screen moves the viewport with it, so
* SCROLLTOP changes on every keypress -- and a cache that only answered for
* the exact line it recorded was wrong every single time, which measured as no
* improvement whatsoever. One line down is fifty bytes of scanning; counting
* from the start of a six thousand byte document is six thousand.
*
* A long jump -- a page, or OA-> to the end -- costs one full count, and every
* keypress after it is a step from there.
*--------------------------------------
TOPSEEK      lda   SCROLLTOP
             sec
             sbc   TOPLINE
             sta   TSN
             lda   SCROLLTOP+1
             sbc   TOPLINE+1
             bmi   :back
             bne   :no              ; 256 lines or more: just count
             lda   TSN
             beq   :ok              ; already the line we want
             cmp   #65              ; further than this and counting wins
             bcs   :no
:fwd         jsr   TOPNEXT
             bcs   :no
             dec   TSN
             bne   :fwd
             beq   :ok

*--- SCROLLTOP is above the line we remember, so walk back to it. Everything
*    below TOPADDR is behind the gap and contiguous -- the caller checked --
*    so this needs no gap handling at all.
:back        lda   TOPLINE
             sec
             sbc   SCROLLTOP
             sta   TSN
             lda   TOPLINE+1
             sbc   SCROLLTOP+1
             bne   :no
             lda   TSN
             cmp   #65
             bcs   :no
:bk          jsr   TOPPREV
             bcs   :no
             dec   TSN
             bne   :bk

:ok          lda   SCROLLTOP
             sta   TOPLINE
             lda   SCROLLTOP+1
             sta   TOPLINE+1
             clc
             rts
:no          sec
             rts

*--------------------------------------
* TOPNEXT -- TOPADDR to the first byte of the following line
*--------------------------------------
TOPNEXT      ldy   #$00
:loop        lda   TOPADDR          ; standing at the gap? step over it
             cmp   GAPBEG
             bne   :rd
             lda   TOPADDR+1
             cmp   GAPBEG+1
             bne   :rd
             lda   GAPEND
             sta   TOPADDR
             lda   GAPEND+1
             sta   TOPADDR+1
:rd          lda   TOPADDR+1
             cmp   #BUFHI
             bcs   :end
             lda   TOPADDR
             sta   AUXPTR
             lda   TOPADDR+1
             sta   AUXPTR+1
             jsr   AUXRD
             pha
             inc   TOPADDR
             bne   :1
             inc   TOPADDR+1
:1           pla
             cmp   #TEXTLO
             bcs   :loop            ; ordinary text: keep going
             clc                    ; that was the break, and TOPADDR is now
             rts                    ; the first byte after it
:end         sec
             rts

*--------------------------------------
* TOPPREV -- TOPADDR back to the first byte of the preceding line
*--------------------------------------
TOPPREV      jsr   TOPDEC           ; onto the break that ended the line above
             bcs   :none
             ldy   #$00
:scan        jsr   TOPDEC           ; and back across that line
             bcs   :done            ; the buffer start IS a line start
             lda   TOPADDR
             sta   AUXPTR
             lda   TOPADDR+1
             sta   AUXPTR+1
             jsr   AUXRD
             cmp   #TEXTLO
             bcs   :scan
             inc   TOPADDR          ; the line starts one past that break
             bne   :done
             inc   TOPADDR+1
:done        clc
             rts
:none        sec
             rts

*--------------------------------------
* TOPDEC -- TOPADDR down one, carry set if it was already at the buffer start
*--------------------------------------
TOPDEC       lda   TOPADDR
             bne   :dec
             lda   TOPADDR+1
             cmp   #BUFLO
             beq   :none
             dec   TOPADDR+1
:dec         dec   TOPADDR
             clc
             rts
:none        sec
             rts

             dum   $1422            ; $1420-$1421 are help.S's
TOPADDR      ds    2                ; where the line at TOPLINE begins
TOPLINE      ds    2                ; which line that is
TOPOK        ds    1                ; and whether either means anything yet
TSN          ds    1                ; TOPSEEK: lines still to walk
             dend
