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
*--------------------------------------
GAPLEFT      jsr   ATSTART
             bcc   :ok
             rts
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
             rts

*--------------------------------------
* RENDER -- draw the buffer through the viewport
*
* Walks logical bytes, stepping over the gap, breaking lines on CR ($8D).
* Lines before SCROLLTOP are counted but not drawn; VIS goes true once we
* reach the viewport and stays true, so the test costs one byte compare per
* line rather than a 16-bit comparison per character.
*
* Still rescans from the buffer start every time. That is what the line index
* is for -- scrolling did not need it, speed does.
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

*--- already inside the viewport if it starts at line zero
             lda   SCROLLTOP
             ora   SCROLLTOP+1
             beq   :vis
             lda   #$00
             beq   :setvis
:vis         lda   #$01
:setvis      sta   VIS
             jsr   CLRBUF

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
             bcs   :done

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
             cmp   SCROLLTOP
             bne   :next
             lda   LINENO+1
             cmp   SCROLLTOP+1
             bne   :next
             lda   #$01
             sta   VIS

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
:fin         rts
