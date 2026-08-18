*--------------------------------------
* SELECT.S -- text selection
*
* The selection runs between an anchor and the cursor. Because the gap sits at
* the cursor, the selected text is ALWAYS contiguous in auxiliary memory: it is
* either the bytes immediately before the gap, or the bytes immediately after
* it. Nothing here has to cope with a range split across the gap.
*
* The anchor is kept as a logical offset -- a position in the text, ignoring
* the gap -- because an aux address stops meaning the same byte as soon as the
* gap moves past it.
*
* Two ways in. Shift with an arrow reads the //e's shift key at $C063, and
* OA-Space latches a selection mode for keyboards or emulators where that is
* not available.
*--------------------------------------

*--------------------------------------
* SELINIT -- zero page holds no guarantees at startup, and a stray non-zero
*            SELACT would render garbage inverse and force a full redraw on
*            every keystroke.
*--------------------------------------
* Shift detection is calibrated rather than assumed. $C063 is documented as the
* //e's shift key, but its polarity is not something to take on trust, and an
* emulator may not implement it at all -- Virtual ][ reads it as permanently
* held, which would make every arrow key select. So sample it once at startup,
* when shift is presumably up, and treat any later difference as pressed. Wrong
* polarity self-corrects; a dead switch simply never fires, leaving OA-Space.
SELINIT      lda   SHIFTKEY
             and   #$80
             sta   SHIFTIDLE
             lda   #$00
             sta   MODSHIFT
             sta   SELACT
             sta   SELMODE
             sta   SELANC
             sta   SELANC+1
             sta   CLIPLEN
             sta   CLIPLEN+1
             sta   CLIPLINE
             rts

*--------------------------------------
* GETPOS -- LPOS = the cursor's logical offset
*--------------------------------------
GETPOS       lda   GAPBEG
             sta   LPOS
             lda   GAPBEG+1
             sec
             sbc   #AUXLO
             sta   LPOS+1
             rts

*--------------------------------------
* SELCLR -- drop the selection, staying in selection mode if it is latched
*--------------------------------------
SELCLR       lda   #$00
             sta   SELACT
             rts

*--------------------------------------
* SELDONE -- the selection has been consumed: drop it AND leave the mode.
*
* Without this, replacing or cutting a selection leaves the mode latched, so
* the very next arrow key starts selecting again instead of just moving.
*--------------------------------------
SELDONE      lda   #$00
             sta   SELACT
             sta   SELMODE
             rts

*--------------------------------------
* SELUPD -- called by the arrow keys before they move.
*           Starts a selection if a modifier is held, drops it otherwise.
*--------------------------------------
SELUPD       lda   MODSHIFT
             ora   SELMODE
             beq   SELCLR
             lda   SELACT
             bne   :done            ; already selecting: moving extends it
             jsr   GETPOS
             lda   LPOS
             sta   SELANC
             lda   LPOS+1
             sta   SELANC+1
             lda   #$01
             sta   SELACT
:done        rts

*--------------------------------------
* SELTOGGLE -- OA-Space latches selection mode
*--------------------------------------
SELTOGGLE    lda   SELMODE
             beq   :on
             jmp   SELDONE          ; leaving the mode drops the selection
:on          lda   #$01
             sta   SELMODE
             jsr   GETPOS           ; entering it anchors here
             lda   LPOS
             sta   SELANC
             lda   LPOS+1
             sta   SELANC+1
             lda   #$01
             sta   SELACT
             rts

*--------------------------------------
* SELESC -- Esc outside a prompt cancels selecting altogether
*--------------------------------------
SELESC       lda   #$00
             sta   SELMODE
             jmp   SELCLR

*--------------------------------------
* SELRANGE -- SELLEN = size of the selection, SELDIR = which side of the gap
*--------------------------------------
SELRANGE     jsr   GETPOS
             lda   SELANC+1
             cmp   LPOS+1
             bcc   :below
             bne   :above
             lda   SELANC
             cmp   LPOS
             bcc   :below
             beq   :empty

*--- anchor past the cursor: the selection sits after the gap
:above       lda   #$01
             sta   SELDIR
             lda   SELANC
             sec
             sbc   LPOS
             sta   SELLEN
             lda   SELANC+1
             sbc   LPOS+1
             sta   SELLEN+1
             rts

*--- anchor behind the cursor: the selection sits before the gap
:below       lda   #$00
             sta   SELDIR
             lda   LPOS
             sec
             sbc   SELANC
             sta   SELLEN
             lda   LPOS+1
             sbc   SELANC+1
             sta   SELLEN+1
             rts

:empty       lda   #$00
             sta   SELDIR
             sta   SELLEN
             sta   SELLEN+1
             rts

*--------------------------------------
* SELBOUNDS -- SELLO/SELHI = the selection as logical offsets, for RENDER
*--------------------------------------
SELBOUNDS    jsr   SELRANGE
             jsr   GETPOS
             lda   SELDIR
             bne   :after
             lda   LPOS             ; before the gap: [cursor-len, cursor)
             sec
             sbc   SELLEN
             sta   SELLO
             lda   LPOS+1
             sbc   SELLEN+1
             sta   SELLO+1
             lda   LPOS
             sta   SELHI
             lda   LPOS+1
             sta   SELHI+1
             rts
:after       lda   LPOS             ; after the gap: [cursor, cursor+len)
             sta   SELLO
             lda   LPOS+1
             sta   SELLO+1
             lda   LPOS
             clc
             adc   SELLEN
             sta   SELHI
             lda   LPOS+1
             adc   SELLEN+1
             sta   SELHI+1
             rts

*--------------------------------------
* DECLEN -- 16-bit decrement of SELLEN, Z set when it reaches zero
*--------------------------------------
DECLEN       lda   SELLEN
             bne   :lo
             dec   SELLEN+1
:lo          dec   SELLEN
             lda   SELLEN
             ora   SELLEN+1
             rts

*--------------------------------------
* DELSEL -- remove the selected text. Carry set if there was none.
*
* Built from DELBACK/DELFWD rather than by moving the gap edges directly, so
* CURLNO and CCOL stay maintained even when the selection spans newlines.
*--------------------------------------
DELSEL       lda   SELACT
             bne   :go
             sec
             rts
:go          jsr   SELRANGE
             lda   SELLEN
             ora   SELLEN+1
             beq   :clr
             lda   SELDIR
             bne   :fwd
:back        jsr   DELBACK
             jsr   DECLEN
             bne   :back
             beq   :clr
:fwd         jsr   DELFWD
             jsr   DECLEN
             bne   :fwd
:clr         jsr   SELDONE
             clc
             rts

*--------------------------------------
* COPYSEL -- selected text into the clipboard. Carry set if there was none.
*--------------------------------------
COPYSEL      lda   SELACT
             bne   :go
             sec
             rts
:go          jsr   SELRANGE
             lda   SELLEN
             ora   SELLEN+1
             bne   :size
             sec
             rts

*--- clamp to the clipboard
:size        lda   SELLEN+1
             cmp   #>CLIPMAX
             bcc   :fits
             bne   :clamp
             lda   SELLEN
             cmp   #<CLIPMAX
             bcc   :fits
:clamp       lda   #<CLIPMAX
             sta   SELLEN
             lda   #>CLIPMAX
             sta   SELLEN+1
:fits        lda   SELLEN
             sta   CLIPLEN
             lda   SELLEN+1
             sta   CLIPLEN+1

*--- the selection is contiguous, so this is one run either side of the gap
             lda   SELDIR
             bne   :after
             lda   GAPBEG
             sec
             sbc   SELLEN
             sta   AUXPTR
             lda   GAPBEG+1
             sbc   SELLEN+1
             sta   AUXPTR+1
             jmp   :run
:after       lda   GAPEND
             sta   AUXPTR
             lda   GAPEND+1
             sta   AUXPTR+1

:run         lda   #<CLIPBUF
             sta   DSTPTR
             lda   #>CLIPBUF
             sta   DSTPTR+1
:chunk       lda   SELLEN
             ora   SELLEN+1
             beq   :done
             lda   SELLEN+1         ; up to 255 bytes at a time
             beq   :small
             lda   #$ff
             jmp   :have
:small       lda   SELLEN
:have        sta   BLKLEN
             ldy   #$00
             jsr   AUXBLK
             lda   AUXPTR           ; advance both pointers
             clc
             adc   BLKLEN
             sta   AUXPTR
             bcc   :d1
             inc   AUXPTR+1
:d1          lda   DSTPTR
             clc
             adc   BLKLEN
             sta   DSTPTR
             bcc   :d2
             inc   DSTPTR+1
:d2          lda   SELLEN           ; and shrink what is left
             sec
             sbc   BLKLEN
             sta   SELLEN
             bcs   :chunk
             dec   SELLEN+1
             jmp   :chunk
:done        clc
             rts

*--------------------------------------
* SELTEST -- update INSEL for the logical position in RPOS
*
* Called once per byte from RENDER, so it tests for equality with the two
* boundaries rather than comparing magnitudes: the walk only ever moves
* forwards, and a low-byte mismatch settles it in four cycles.
*--------------------------------------
SELTEST      lda   RPOS
             cmp   SELLO
             bne   :hi
             lda   RPOS+1
             cmp   SELLO+1
             bne   :hi
             lda   #$01
             sta   INSEL
:hi          lda   RPOS
             cmp   SELHI
             bne   :done
             lda   RPOS+1
             cmp   SELHI+1
             bne   :done
             lda   #$00
             sta   INSEL
:done        rts
