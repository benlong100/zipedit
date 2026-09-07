*--------------------------------------
* EDIT_OPS.S -- find, go to line, clipboard, word-aware emphasis
*
* Everything here is built from the buffer primitives rather than reaching into
* the gap directly, so the maintained CURLNO and CCOL stay correct for free.
*--------------------------------------

*--------------------------------------
* KFIND -- ask for a pattern, then search forward (OA-F)
*--------------------------------------
KFIND        lda   #<MSGFIND
             sta   STRPTR
             lda   #>MSGFIND
             sta   STRPTR+1
             jsr   PROMPT
             bcs   :quit
             lda   PLEN
             sta   FINDLEN
             ldx   #$00
:copy        cpx   PLEN
             beq   FINDFIRST
             lda   PBUF,x
             sta   FINDBUF,x
             inx
             bne   :copy
:quit        rts

*--------------------------------------
* FINDFIRST / FINDNEXT -- search for FINDBUF, wrapping at the end
*
* Both walk forward and both wrap. They differ in one thing: whether the
* character UNDER the cursor is a candidate. A fresh pattern (OA-F) has to be
* able to match it, or a document whose first word is the pattern reports NOT
* FOUND with the cursor sitting on it. Find again (OA-G) must not, or it
* re-matches where it stands and the cursor never moves -- which is exactly
* what it used to do, every time, for want of this one byte.
*
* The search is two passes because the gap splits the document in two. Pass
* one is everything after the cursor, contiguous from GAPEND to the top of
* the buffer. Pass two is everything before it, contiguous from the bottom of
* the buffer up to GAPBEG. Between them they cover the document exactly once,
* which is what wrapping means.
*
* A hit in the second pass says " WRAPPED TO THE TOP" on the status row, so a
* cursor that has jumped backwards is explained rather than surprising.
*
* Neither pass sees a match STRADDLING the gap -- one starting before the
* cursor and ending after it. Reaching it would mean testing for a
* discontinuity on every byte of every compare, and it can only arise when
* the cursor has been parked inside an occurrence by hand: a find always
* leaves it on a match's FIRST character, never inside one.
*--------------------------------------
FINDFIRST    lda   #$00
             sta   FSKIP
             beq   FINDGO           ; always taken -- STA leaves Z alone
FINDNEXT     lda   #$01
             sta   FSKIP
FINDGO       lda   FINDLEN
             bne   :tail
             rts

*--- Pass one. Stop where a compare would run past $BFFF: $C000 is the I/O
*    page, and merely READING $C010 there would eat the keyboard strobe. The
*    last legal start is BUFHI*256-FINDLEN, so the limit is one past it. That
*    +1 is not cosmetic -- the text after the cursor always ends at $BFFF, so
*    without it a match lying against the end of the document was unfindable.
:tail        lda   #$00
             sec
             sbc   FINDLEN
             sta   TMPA
             lda   #BUFHI
             sbc   #$00
             sta   TMPB
             inc   TMPA
             bne   :from
             inc   TMPB

:from        lda   GAPEND           ; at the cursor, or one past it
             clc
             adc   FSKIP
             sta   AUXPTR
             lda   GAPEND+1
             adc   #$00
             sta   AUXPTR+1
             jsr   FSCAN
             bcs   :wrap

             lda   FDIST            ; the character we stepped over counts
             clc
             adc   FSKIP
             sta   FDIST
             bcc   :right
             inc   FDIST+1
:right       jmp   FMOVER

*--- Pass two: the text before the cursor. The last start worth trying is the
*    one whose match ends at GAPBEG, so the limit is GAPBEG-FINDLEN+1. If the
*    text before the cursor is shorter than the pattern that lands at or below
*    the buffer base and FSCAN gives up on its first test, which is right.
:wrap        lda   GAPBEG
             sec
             sbc   FINDLEN
             sta   TMPA
             lda   GAPBEG+1
             sbc   #$00
             sta   TMPB
             inc   TMPA
             bne   :top
             inc   TMPB

:top         lda   #$00
             sta   AUXPTR
             lda   #BUFLO
             sta   AUXPTR+1
             jsr   FSCAN
             bcs   :nope

*--- The hit is at BUFLO*256+FDIST, behind the cursor, so the gap walks back
*    GAPBEG-(BUFLO*256+FDIST) characters to reach it.
             lda   GAPBEG
             sec
             sbc   FDIST
             tax
             lda   GAPBEG+1
             sbc   FDIST+1
             sec                    ; less the buffer base, whose low byte is
             sbc   #BUFLO           ; zero, so this cannot borrow again
             sta   FDIST+1
             stx   FDIST
             jsr   FMOVEL

*--- and say so. Landing somewhere above where the search started looks like a
*    find that went the wrong way unless the row explains itself; SHOWMSG holds
*    the status line until the next keystroke, exactly as NOT FOUND does.
             lda   #<MSGWRAPPED
             sta   STRPTR
             lda   #>MSGWRAPPED
             sta   STRPTR+1
             jmp   SHOWMSG

:nope        lda   #<MSGNOTFND
             sta   STRPTR
             lda   #>MSGNOTFND
             sta   STRPTR+1
             jmp   SHOWMSG

*--------------------------------------
* FSCAN -- look for FINDBUF from AUXPTR up to, but not including, TMPA/TMPB.
*
* Carry clear on a hit, AUXPTR left on its first byte and FDIST holding how
* far that is from where this scan began. Carry set if the region ran out.
* A plain linear scan: within one pass the region is contiguous, so there is
* no gap arithmetic here at all.
*--------------------------------------
FSCAN        lda   #$00
             sta   FDIST
             sta   FDIST+1

:outer       lda   AUXPTR+1         ; past the end of the region?
             cmp   TMPB
             bcc   :try
             bne   :out
             lda   AUXPTR
             cmp   TMPA
             bcs   :out

:try         ldy   #$00
:cmp         cpy   FINDLEN
             beq   :hit
             jsr   AUXRD            ; reads AUXPTR+Y
             sta   TMPC
             lda   FINDBUF,y
             cmp   TMPC
             bne   :step
             iny
             bne   :cmp

:step        inc   AUXPTR
             bne   :dist
             inc   AUXPTR+1
:dist        inc   FDIST
             bne   :outer
             inc   FDIST+1
             jmp   :outer

:hit         clc
             rts
:out         sec
             rts

*--------------------------------------
* FMOVER / FMOVEL -- walk the cursor FDIST characters onto the hit, forwards
* or backwards. Going through the gap movers rather than just setting GAPBEG
* is the point: CURLNO and CCOL are maintained incrementally, so the line and
* column follow for free and the redraw knows where to put the cursor.
*--------------------------------------
FMOVER       lda   FDIST
             ora   FDIST+1
             beq   :done
:step        jsr   GAPRIGHT
             jsr   FDEC
             bne   :step
:done        rts

FMOVEL       lda   FDIST
             ora   FDIST+1
             beq   :done
:step        jsr   GAPLEFT
             jsr   FDEC
             bne   :step
:done        rts

*--- one off FDIST, leaving Z set when it reaches zero. A counter cannot live
*    in X across GAPLEFT or GAPRIGHT -- both TAX the byte they carry over.
FDEC         lda   FDIST
             bne   :lo
             dec   FDIST+1
:lo          dec   FDIST
             lda   FDIST
             ora   FDIST+1
             rts

*--------------------------------------
* KGOTO -- jump to a line number (OA-L)
*--------------------------------------
KGOTO        lda   #<MSGGOTO
             sta   STRPTR
             lda   #>MSGGOTO
             sta   STRPTR+1
             jsr   PROMPT
             bcs   :quit
             jsr   PARSENUM         ; NUMVAL = the number typed
             lda   NUMVAL           ; the user counts from one
             ora   NUMVAL+1
             beq   :zero
             lda   NUMVAL
             bne   :dec
             dec   NUMVAL+1
:dec         dec   NUMVAL
:zero
*--- walk until the maintained line number matches
:loop        lda   CURLNO+1
             cmp   NUMVAL+1
             bcc   :down
             bne   :up
             lda   CURLNO
             cmp   NUMVAL
             beq   :quit
             bcc   :down
:up          jsr   KUP
             jsr   ATSTART
             bcs   :quit            ; nowhere further to go
             jmp   :loop
:down        jsr   KDOWN
             jsr   ATEND
             bcs   :quit
             jmp   :loop
:quit        rts

*--------------------------------------
* PARSENUM -- NUMVAL = decimal digits in PBUF. Non-digits end it.
*--------------------------------------
PARSENUM     lda   #$00
             sta   NUMVAL
             sta   NUMVAL+1
             ldx   #$00
:loop        cpx   PLEN
             beq   :done
             lda   PBUF,x
             and   #$7f
             cmp   #'0'
             bcc   :done
             cmp   #'9'+1
             bcs   :done
             sec
             sbc   #'0'
             sta   TMPA
*--- NUMVAL = NUMVAL*10 + digit, via *8 + *2
             lda   NUMVAL
             sta   TMPB
             lda   NUMVAL+1
             sta   TMPC
             asl   NUMVAL           ; *2
             rol   NUMVAL+1
             asl   NUMVAL           ; *4
             rol   NUMVAL+1
             asl   NUMVAL           ; *8
             rol   NUMVAL+1
             asl   TMPB             ; *2 of the original
             rol   TMPC
             lda   NUMVAL
             clc
             adc   TMPB
             sta   NUMVAL
             lda   NUMVAL+1
             adc   TMPC
             sta   NUMVAL+1
             lda   NUMVAL
             clc
             adc   TMPA
             sta   NUMVAL
             bcc   :next
             inc   NUMVAL+1
:next        inx
             bne   :loop
:done        rts

*--------------------------------------
* KCOPY -- copy the cursor's line to the clipboard (OA-C)
*
* Line based rather than selection based: with hard wrap a "line" is a natural
* unit, and it needs no selection UI. Paragraph and mark selection can come
* later without changing the clipboard itself.
*--------------------------------------
KCOPY        jsr   COPYSEL          ; a selection wins over the whole line
             bcs   :line
             lda   #$00
             sta   CLIPLINE
             jsr   SELDONE
             lda   #<MSGCOPIED
             jmp   :say
:line        jsr   GRABLINE
             lda   #$01
             sta   CLIPLINE
             lda   #<MSGCOPIED
:say         sta   STRPTR
             lda   #>MSGCOPIED
             sta   STRPTR+1
             jmp   SHOWMSG

*--------------------------------------
* GRABLINE -- CLIPBUF/CLIPLEN = the cursor's line, without its newline
*--------------------------------------
GRABLINE     lda   #$00
             sta   CLIPLEN

*--- The copy below counts in X, and the clipboard takes 255 characters at
*    most, so the run before the cursor is clamped to that. CCOL is two bytes
*    and X is one: left unclamped, `cpx CCOL` would compare against the low
*    byte alone and take an arbitrary slice out of the middle of a long line.
             lda   CCOL+1
             beq   :precnt
             lda   #$ff             ; longer than the clipboard: take the last
             bne   :setpre          ; 255 characters before the cursor
:precnt      lda   CCOL
:setpre      sta   GRABPRE

*--- the part before the cursor is contiguous, ending at the gap
             lda   GAPBEG
             sec
             sbc   GRABPRE
             sta   AUXPTR
             lda   GAPBEG+1
             sbc   #$00
             sta   AUXPTR+1
             ldx   #$00
:pre         cpx   GRABPRE
             beq   :post
             ldy   #$00
             jsr   AUXRD
             sta   CLIPBUF,x
             inx
             inc   AUXPTR
             bne   :pre
             inc   AUXPTR+1
             jmp   :pre

*--- the rest resumes past the gap, up to the newline
:post        lda   GAPEND
             sta   AUXPTR
             lda   GAPEND+1
             sta   AUXPTR+1
:ploop       cpx   #$ff
             bcs   :done
             lda   AUXPTR+1
             cmp   #BUFHI
             bcs   :done
             ldy   #$00
             jsr   AUXRD
             cmp   #TEXTLO
             bcc   :done
             sta   CLIPBUF,x
             inx
             inc   AUXPTR
             bne   :ploop
             inc   AUXPTR+1
             jmp   :ploop
:done        stx   CLIPLEN
             lda   #$00
             sta   CLIPLEN+1
             rts

*--------------------------------------
* KCUT -- copy the line, then remove it (OA-X)
*--------------------------------------
KCUT         jsr   COPYSEL          ; a selection wins over the whole line
             bcs   :line
             lda   #$00
             sta   CLIPLINE
             jsr   DELSEL
             rts                       ; no message: the text visibly went away

:line        jsr   GRABLINE
             lda   #$01
             sta   CLIPLINE
             jsr   BOL              ; stand at the start of the line
             lda   CLIPLEN
             sta   TMPA
             beq   :nl
:del         jsr   DELFWD
             dec   TMPA
             bne   :del
:nl          jsr   PEEKFWD          ; and take the break with it
             bcs   :done
             cmp   #TEXTLO
             bcs   :done
             jsr   DELFWD
:done        rts                       ; no message: the line visibly went away

*--------------------------------------
* KWORDS -- count the words in the document and report them (OA-W)
*
* A word is a run of non-blank characters, so the count is simply the number of
* blank-to-non-blank transitions. Blank means a space or the carriage return
* that ends a line; nothing else in a Markdown document separates words, and
* Tab inserts spaces rather than a tab byte.
*
* The gap is stepped over exactly as RENDER steps over it -- it is not text.
*
* This deliberately is NOT live in the status row. Typing costs 19 ms because
* the editor stopped walking the whole buffer on every keystroke; a live count
* would put that walk straight back and undo it.
*--------------------------------------
KWORDS       lda   #$00
             sta   WCNT
             sta   WCNT+1
             sta   INWORD
             sta   AUXPTR
             lda   #BUFLO
             sta   AUXPTR+1

:loop        lda   AUXPTR           ; standing at the gap? jump over it
             cmp   GAPBEG
             bne   :notgap
             lda   AUXPTR+1
             cmp   GAPBEG+1
             bne   :notgap
             lda   GAPEND
             sta   AUXPTR
             lda   GAPEND+1
             sta   AUXPTR+1

:notgap      lda   AUXPTR+1         ; ran off the end of the buffer?
             cmp   #BUFHI
             bcs   :count
             ldy   #$00
             jsr   AUXRD
             cmp   #TEXTLO+1        ; a space, or any kind of break
             bcc   :blank

*--- non-blank: a word begins here unless we were already inside one
             lda   INWORD
             bne   :next
             lda   #$01
             sta   INWORD
             inc   WCNT
             bne   :next
             inc   WCNT+1
             jmp   :next

:blank       lda   #$00
             sta   INWORD

:next        inc   AUXPTR
             bne   :back
             inc   AUXPTR+1
:back        jmp   :loop

*--- render the total as decimal, left aligned, into the message buffer.
*    Pick the tail first: the formatter consumes WCNT as it divides, so the
*    total is gone by the time the word itself has to be chosen.
:count       lda   #<WTAIL
             sta   STRPTR
             lda   #>WTAIL
             sta   STRPTR+1
             lda   WCNT+1
             bne   :fmt
             lda   WCNT
             cmp   #$01
             bne   :fmt
             lda   #<WTAIL1         ; exactly one: "WORD", not "WORDS"
             sta   STRPTR
             lda   #>WTAIL1
             sta   STRPTR+1

:fmt         lda   #$a0             ; messages open with a space
             sta   WBUF
             lda   #$01
             sta   WIDX
             lda   #$00
             sta   WLEAD
             ldy   #$00

:pow         lda   #$00
             sta   WDIG
:sub         lda   WCNT             ; how many times does this power fit?
             sec
             sbc   TENLO,y
             sta   TMPA
             lda   WCNT+1
             sbc   TENHI,y
             bcc   :emit
             sta   WCNT+1
             lda   TMPA
             sta   WCNT
             inc   WDIG
             jmp   :sub

:emit        lda   WDIG
             bne   :put
             lda   WLEAD
             bne   :put
             cpy   #$04             ; the units digit shows even as a zero
             beq   :put
             jmp   :nextpow         ; drop this leading zero entirely
:put         lda   #$01
             sta   WLEAD
             lda   WDIG
             clc
             adc   #$b0             ; high ASCII digit
             ldx   WIDX
             sta   WBUF,x
             inc   WIDX
:nextpow     iny
             cpy   #$05
             bne   :pow

*--- and the word "WORDS" after it, terminator included
             ldx   WIDX
             ldy   #$00
:tail        lda   (STRPTR),y
             sta   WBUF,x
             beq   :show
             inx
             iny
             jmp   :tail

:show        lda   #<WBUF
             sta   STRPTR
             lda   #>WBUF
             sta   STRPTR+1
             jmp   SHOWMSG

TENLO        dfb   $10,$e8,$64,$0a,$01
TENHI        dfb   $27,$03,$00,$00,$00

*--------------------------------------
* KPASTE -- insert the clipboard at the cursor, then a newline (OA-V)
*--------------------------------------
* Paste replaces a selection, and only re-adds a newline when the clipboard
* holds a whole line rather than an arbitrary range.
*
* Then it reflows the paragraph, which is what keeps the hard wrap honest.
* Typing maintains the wrap one character at a time through WRAPCHECK, and
* every other insert is small enough for that to hold; paste is the one path
* that can lay down hundreds of characters between two wrap checks, so the
* line it builds is already far past the margin before anything looks at it.
* The result was text running off the right edge into nowhere -- RENDER clips
* at the margin -- and, once the line passed 255 characters, a column count
* that had wrapped and a cursor the editor could no longer place.
*
* A per-character WRAPCHECK would be the faithful fix and is far too slow: it
* stages the rest of the line out of aux on every call, so a 255-byte paste
* would pay that 255 times. RTFLOW walks the paragraph once instead, and puts
* the cursor back by its offset within the paragraph afterwards.
KPASTE       jsr   DELSEL
             lda   CLIPLEN
             ora   CLIPLEN+1
             beq   :done
             lda   #<CLIPBUF
             sta   CLIPPTR
             lda   #>CLIPBUF
             sta   CLIPPTR+1
             lda   CLIPLEN          ; SELLEN doubles as the counter
             sta   SELLEN
             lda   CLIPLEN+1
             sta   SELLEN+1
:loop        ldy   #$00
             lda   (CLIPPTR),y
             jsr   INSCHR
             inc   CLIPPTR
             bne   :dec
             inc   CLIPPTR+1
:dec         jsr   DECLEN
             bne   :loop
             lda   CLIPLINE
             beq   :flow
             lda   #HARDCR          ; a pasted line ends with a real return
             jsr   INSCHR
:flow        jmp   RTFLOW           ; and re-wrap what we just ran through
:done        rts

*--------------------------------------
* WORDBACK -- TMPB = characters back to the start of the word at the cursor.
*             Carry set if the cursor is not on or just after a word.
*--------------------------------------
WORDBACK     lda   #$00
             sta   TMPB
             lda   GAPBEG
             sta   AUXPTR
             lda   GAPBEG+1
             sta   AUXPTR+1
:loop        lda   AUXPTR+1
             cmp   #BUFLO
             bne   :dec
             lda   AUXPTR
             beq   :stop
:dec         lda   AUXPTR
             bne   :d1
             dec   AUXPTR+1
:d1          dec   AUXPTR
             ldy   #$00
             jsr   AUXRD
             cmp   #TEXTLO+1        ; a space or a break ends the word
             bcc   :stop
             beq   :stop
             inc   TMPB
             lda   TMPB
             cmp   #$50
             bcs   :stop            ; absurdly long, treat as no word
             jmp   :loop
:stop        lda   TMPB
             beq   :none
             clc
             rts
:none        sec
             rts

*--------------------------------------
* EMPHASIS -- wrap the word at the cursor in the marker in A, repeated X times
*
* With no word under the cursor it inserts the markers empty and sits between
* them, which is what you want when reaching for emphasis before typing.
*--------------------------------------
* NOTE: X cannot hold any of these counters. INSCHR reaches PUTAUX, which does
* a TAX, and GAPLEFT/GAPRIGHT do the same -- so every loop here counts in
* memory. This cost an afternoon the first time.
EMPHASIS     sta   EMCHR
             stx   EMCNT

*--- if the cursor sits inside a word, run to the end of it first, so that
*    emphasis takes the whole word rather than the half behind the cursor
:toend       jsr   PEEKFWD
             bcs   :atend
             cmp   #TEXTLO+1
             bcc   :atend
             cmp   #$a0
             beq   :atend
             jsr   GAPRIGHT
             jmp   :toend

:atend       jsr   WORDBACK
             bcs   :empty

*--- step back over the word, open it, then step forward over it and close
             lda   TMPB
             sta   EMDIST
             sta   EMWORD
:back        jsr   GAPLEFT
             dec   EMDIST
             bne   :back

             jsr   PUTMARK

             lda   EMWORD
             sta   EMDIST
:fwd         jsr   GAPRIGHT
             dec   EMDIST
             bne   :fwd

             jmp   PUTMARK

*--- no word under the cursor: open and close, then sit between them
:empty       jsr   PUTMARK
             jsr   PUTMARK
             lda   EMCNT
             sta   EMN
:e3          jsr   GAPLEFT
             dec   EMN
             bne   :e3
             rts

*--------------------------------------
* PUTMARK -- insert EMCNT copies of EMCHR
*--------------------------------------
PUTMARK      lda   EMCNT
             sta   EMN
:loop        lda   EMCHR
             jsr   INSCHR
             dec   EMN
             bne   :loop
             rts

*--------------------------------------
* Key handlers for emphasis
*--------------------------------------
KBOLD        lda   #$aa             ; '*'
             ldx   #$02
             jmp   EMPHASIS

KITALIC      lda   #$aa             ; '*' -- one for italic, two for bold
             ldx   #$01
             jmp   EMPHASIS


             dum   $1400
NUMVAL       ds    2                ; parsed line number
FDIST        ds    2                ; distance from cursor to a search hit
FSKIP        ds    1                ; 0 = the character under the cursor is a
                                    ; candidate (OA-F), 1 = step over it (OA-G)
EMCHR        ds    1
EMCNT        ds    1
EMDIST       ds    1
EMWORD       ds    1
EMN          ds    1
WCNT         ds    2                ; KWORDS: running total
INWORD       ds    1                ; non-zero while inside a word
WDIG         ds    1                ; KWORDS: digit being emitted
WLEAD        ds    1                ; non-zero once a digit has been emitted
WIDX         ds    1                ; write position in WBUF
WBUF         ds    16               ; " 1234 WORDS" and its terminator
GRABPRE      ds    1                ; GRABLINE: characters taken before the gap
             dend

*--------------------------------------
* KDELEOL -- delete from the cursor to the end of the line (Ctrl-Y)
*--------------------------------------
KDELEOL      jsr   PEEKFWD
             bcs   :done
             cmp   #TEXTLO
             bcc   :done
             jsr   DELFWD
             jmp   KDELEOL
:done        rts

*--------------------------------------
* KWORDL -- cursor back one word (OA-left)
*--------------------------------------
KWORDL       jsr   PEEKBACK
             bcs   :done
             cmp   #TEXTLO          ; at a line start: step onto the line above
             bcs   :sp
             jsr   GAPLEFT
             jmp   KWORDL
:sp          jsr   PEEKBACK         ; back over any spaces
             bcs   :done
             cmp   #$a0
             bne   :word
             jsr   GAPLEFT
             jmp   :sp
:word        jsr   PEEKBACK         ; then over the word itself
             bcs   :done
             cmp   #TEXTLO+1        ; a space or a break stops us
             bcc   :done
             jsr   GAPLEFT
             jmp   :word
:done        rts

*--------------------------------------
* KWORDR -- cursor forward one word (OA-right)
*--------------------------------------
KWORDR       jsr   PEEKFWD          ; forward over the current word
             bcs   :done
             cmp   #TEXTLO+1
             bcc   :sp
             jsr   GAPRIGHT
             jmp   KWORDR
:sp          jsr   PEEKFWD          ; then over the gap between words
             bcs   :done
             cmp   #TEXTLO+1
             bcs   :done
             jsr   GAPRIGHT
             jmp   :sp
:done        rts
