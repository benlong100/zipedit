*--------------------------------------
* BUFFER.S -- gap buffer in auxiliary memory
*
*   aux $0800                  GAPBEG      GAPEND               aux $C000
*     | text before cursor .......|<<< gap >>>|..... text after cursor |
*
* Insert and delete are O(1) -- move a gap edge. Cursor movement shuffles
* bytes across the gap, costing time proportional to the distance moved, which
* for an editor is almost always a line or less.
*
* Reading and writing aux are NOT symmetric:
*
*   writes  RAMWRT redirects stores to $0200-$BFFF into aux while instruction
*           fetches (which follow RAMRD) stay in main. An ordinary store loop
*           works inline.
*
*   reads   RAMRD redirects loads AND instruction fetches. Code at $2000 would
*           fetch its own next instruction out of the text buffer and die. So
*           reads go through AUXRD, a four-instruction stub copied into the
*           stack page, which RAMRD does not control.
*
* AUXRD assumes interrupts are not in play: an IRQ taken between RAMRD on and
* RAMRD off would run its handler out of aux. Nothing in this configuration
* generates interrupts under ProDOS 8 -- revisit if that changes.
*--------------------------------------

*--------------------------------------
* INSTSTUB -- copy the aux read stub into the stack page
*--------------------------------------
INSTSTUB     ldx   #STUBEND-STUBSRC-1
:loop        lda   STUBSRC,x
             sta   AUXRD,x
             dex
             bpl   :loop
             ldx   #BLKEND-BLKSRC-1
:loop2       lda   BLKSRC,x
             sta   AUXBLK,x
             dex
             bpl   :loop2
             rts

* Position independent: zero page indirect and absolute I/O only.
* On entry AUXPTR -> aux address, Y = index. On exit A = byte, flags set from
* it (STA does not disturb them).
STUBSRC      sta   RAMRDON
             lda   (AUXPTR),y
             sta   RAMRDOFF
             rts
STUBEND

* Block copy aux -> main with a single bank switch, rather than one per byte.
* Reads follow RAMRD and land in aux; writes follow RAMWRT, which stays off, so
* they land in main. Zero page follows ALTZP and is untouched, so both pointers
* stay readable. Entry: AUXPTR source, DSTPTR destination, BLKLEN count (1-255),
* Y = 0. About 15 cycles a byte against roughly 49 through AUXRD.
BLKSRC       sta   RAMRDON
:loop        lda   (AUXPTR),y
             sta   (DSTPTR),y
             iny
             cpy   BLKLEN
             bne   :loop
             sta   RAMRDOFF
             rts
BLKEND

*--------------------------------------
* PUTAUX -- store the byte in A at aux address AUXPTR,Y
*--------------------------------------
PUTAUX       tax
             sta   RAMWRTON         ; value in A is irrelevant to the switch
             txa
             sta   (AUXPTR),y
             sta   RAMWRTOFF
             rts

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
             lda   #AUXLO
             sta   GAPBEG+1
             lda   #AUXHI
             sta   GAPEND+1
             rts

*--------------------------------------
* ATSTART -- carry set if the cursor is at the start of the buffer
*--------------------------------------
ATSTART      lda   GAPBEG+1
             cmp   #AUXLO
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
             cmp   #AUXHI
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
             lda   #AUXLO
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
             cmp   #AUXHI
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
             cpx   #SCRW
             bcs   :next            ; past the right margin, drop it
             lda   VIS
             beq   :bump            ; above the viewport: count, do not draw
             lda   INSEL
             beq   :plain
             lda   TMPA             ; selected: draw it inverse
             and   #$7f
             cmp   #$60
             bcs   :store
             and   #$3f
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
