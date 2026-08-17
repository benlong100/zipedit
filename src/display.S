*--------------------------------------
* DISPLAY.S -- 80 column screen output
*
* The //e 80-column screen interleaves banks: even screen columns live in
* auxiliary memory, odd columns in main, both at the same offset from the row
* base. With 80STORE on, $C054/$C055 pick which bank a write to $0400-$07FF
* lands in.
*
* Everything draws through LINEBUF, an 80-byte main-memory line of screen
* codes. Callers fill it, then blit it. That lets DRAWLINE set the bank switch
* twice per line instead of once per character, which is the difference
* between a redraw you notice and one you don't.
*
* Screen codes, with ALTCHARSET on:
*   normal  = ascii | $80          ($A0-$FF)
*   inverse = ascii & $3f          for ascii < $60
*           = ascii                for ascii >= $60 (inverse lowercase)
*--------------------------------------

*--------------------------------------
* DISPINIT -- 80 column text mode, screen cleared
*--------------------------------------
DISPINIT     sta   TXTSET
             sta   MIXCLR
             sta   HIRESOFF
             sta   SET80VID
             sta   SET80STORE
             sta   SETALTCHAR
             jsr   CLRSCRN
             rts

*--------------------------------------
* CLRSCRN -- fill both screen halves with spaces
*--------------------------------------
CLRSCRN      ldx   #$00
:loop        lda   #$a0
             sta   MAINWR
             sta   $0400,x
             sta   $0500,x
             sta   $0600,x
             sta   $0700,x
             lda   #$a0
             sta   AUXWR
             sta   $0400,x
             sta   $0500,x
             sta   $0600,x
             sta   $0700,x
             inx
             bne   :loop
             rts

*--------------------------------------
* SETROW -- A = row (0-23) -> SCRPTR = row base address
*--------------------------------------
SETROW       tax
             lda   ROWLO,x
             sta   SCRPTR
             lda   ROWHI,x
             sta   SCRPTR+1
             rts

*--------------------------------------
* CLRBUF -- fill LINEBUF with spaces
*--------------------------------------
CLRBUF       lda   #$a0
             ldx   #SCRW-1
:loop        sta   LINEBUF,x
             dex
             bpl   :loop
             rts

*--------------------------------------
* BUFSTR -- copy a null-terminated high-ASCII string into LINEBUF
*   STRPTR -> string, X = starting column. Clips at the right margin.
*--------------------------------------
BUFSTR       ldy   #$00
:loop        lda   (STRPTR),y
             beq   :done
             cpx   #SCRW
             bcs   :done
             sta   LINEBUF,x
             inx
             iny
             bne   :loop
:done        rts

*--------------------------------------
* INVBUF -- convert LINEBUF from normal to inverse video in place
*--------------------------------------
* Bytes with the high bit clear are raw screen codes deliberately placed in the
* buffer -- MouseText -- and must not be touched. Ordinary text always arrives
* here as high ASCII, so the sign bit tells the two apart.
INVBUF       ldy   #SCRW-1
:loop        lda   LINEBUF,y
             bpl   :raw             ; MouseText: leave as is
             and   #$7f             ; back to plain ASCII
             cmp   #$60
             bcs   :keep            ; lowercase: inverse code == ascii
             and   #$3f
:keep        sta   LINEBUF,y
:raw         dey
             bpl   :loop
             rts

*--------------------------------------
* DRAWLINE -- A = row. Blit LINEBUF to the screen.
*
* Two passes: 40 even columns into aux, then 40 odd columns into main. X walks
* LINEBUF two at a time while Y walks the screen offset, so no self-modifying
* code is needed and the code image stays immutable -- which lets the test
* suite compare emulated RAM against the build artifact byte for byte.
*--------------------------------------
DRAWLINE     jsr   SETROW

             sta   AUXWR            ; even columns -> aux
             ldx   #$00
             ldy   #$00
:l1          lda   LINEBUF,x
             sta   (SCRPTR),y
             inx
             inx
             iny
             cpy   #40
             bne   :l1

             sta   MAINWR           ; odd columns -> main
             ldx   #$01
             ldy   #$00
:l2          lda   LINEBUF,x
             sta   (SCRPTR),y
             inx
             inx
             iny
             cpy   #40
             bne   :l2
             rts

*--------------------------------------
* SHOWSTR -- draw a string on its own row, space padded
*   STRPTR -> string, A = row
*--------------------------------------
SHOWSTR      sta   TMPA
             jsr   CLRBUF
             ldx   #$00
             jsr   BUFSTR
             lda   TMPA
             jsr   DRAWLINE
             rts

*--------------------------------------
* SHOWSTRINV -- as SHOWSTR, but inverse video
*--------------------------------------
SHOWSTRINV   sta   TMPA
             jsr   CLRBUF
             ldx   #$00
             jsr   BUFSTR
             jsr   INVBUF
             lda   TMPA
             jsr   DRAWLINE
             rts

*--------------------------------------
* DRAWCHEAT -- render the Markdown cheat sheet on CHEATROW
*--------------------------------------
DRAWCHEAT    lda   #<CHEATTXT
             sta   STRPTR
             lda   #>CHEATTXT
             sta   STRPTR+1
             lda   #CHEATROW
             jsr   SHOWSTR
             rts

*--------------------------------------
* CLRCHEAT -- blank CHEATROW (cheat sheet hidden)
*--------------------------------------
CLRCHEAT     jsr   CLRBUF
             lda   #CHEATROW
             jsr   DRAWLINE
             rts

*--------------------------------------
* SETMAXROW -- text area is one row shorter while the cheat sheet shows
*--------------------------------------
SETMAXROW    lda   FLAGS
             and   #FCHEAT
             bne   :short
             lda   #TEXTROWSMAX
             sta   MAXROW
             rts
:short       lda   #TEXTROWS
             sta   MAXROW
             rts

*--------------------------------------
* TOGGLECHEAT -- flip the cheat sheet on or off
*--------------------------------------
TOGGLECHEAT  lda   FLAGS
             eor   #FCHEAT
             sta   FLAGS
             jsr   SETMAXROW
             lda   FLAGS
             and   #FCHEAT
             bne   :on
             jmp   CLRCHEAT
:on          jmp   DRAWCHEAT

*--------------------------------------
* PUTCELL -- write screen code A at column X of the row already in SCRPTR
*--------------------------------------
PUTCELL      pha
             txa
             and   #$01
             beq   :aux
             sta   MAINWR           ; odd column
             jmp   :put
:aux         sta   AUXWR            ; even column
:put         txa
             lsr
             tay
             pla
             sta   (SCRPTR),y
             rts

*--------------------------------------
* PUTNUM -- render NUMV right aligned in PWID cells starting at column X,
*           space padded, in the inverse video the status line uses.
*
* Inverse digits are simply their ASCII codes ($30-$39), since inverse is
* ascii AND $3F for anything below $60. Inverse space is $20.
*--------------------------------------
PUTNUM       stx   PCOL
             lda   #$04
             sec
             sbc   PWID             ; skip the powers we do not need
             sta   PIDX
             lda   #$00
             sta   PLEAD

:digit       ldy   PIDX
             cpy   #$04
             bcs   :done
             lda   #$00
             sta   PDIG
:sub         lda   NUMV             ; count how many times this power fits
             sec
             sbc   POWLO,y
             tax
             lda   NUMV+1
             sbc   POWHI,y
             bcc   :emit
             stx   NUMV
             sta   NUMV+1
             inc   PDIG
             ldy   PIDX
             jmp   :sub

:emit        lda   PDIG
             bne   :show            ; a non-zero digit ends suppression
             lda   PLEAD
             bne   :show
             ldy   PIDX             ; last cell always shows, even if zero
             cpy   #$03
             beq   :show
             lda   #$20             ; inverse space
             jmp   :put
:show        lda   #$01
             sta   PLEAD
             lda   PDIG
             clc
             adc   #$30             ; inverse digit
:put         ldx   PCOL
             jsr   PUTCELL
             inc   PCOL
             inc   PIDX
             jmp   :digit
:done        rts

POWLO        dfb   $e8,$64,$0a,$01
POWHI        dfb   $03,$00,$00,$00

*--------------------------------------
* STATUPD -- refresh the line and column fields, if they changed
*
* Cheap by construction: CURLNO and CCOL are already maintained, and only the
* digit cells are touched -- never the whole row. Skipped entirely while a
* message is on the status line.
*--------------------------------------
STATUPD      lda   MSGSHOWN
             bne   :out
             lda   #STATROW
             jsr   SETROW

             lda   CURLNO
             cmp   LASTLN
             bne   :doline
             lda   CURLNO+1
             cmp   LASTLN+1
             beq   :docol
:doline      lda   CURLNO
             sta   LASTLN
             clc
             adc   #$01
             sta   NUMV
             lda   CURLNO+1
             sta   LASTLN+1
             adc   #$00
             sta   NUMV+1
             lda   #$04
             sta   PWID
             ldx   #LNDIG
             jsr   PUTNUM

:docol       lda   CCOL
             cmp   LASTCOL
             beq   :out
             sta   LASTCOL
             clc
             adc   #$01
             sta   NUMV
             lda   #$00
             adc   #$00
             sta   NUMV+1
             lda   #$03
             sta   PWID
             ldx   #CLDIG
             jsr   PUTNUM
:out         rts

*--------------------------------------
* RESTORESTAT -- retire whatever owns the status row and repaint it
*--------------------------------------
RESTORESTAT  lda   #$00
             sta   MSGSHOWN
             jsr   DRAWSTATUS
             jmp   STATUPD

*--------------------------------------
* SHOWCURSOR -- invert the character cell the cursor sits on
*
* With 80STORE on, PAGE2 selects which bank $0400-$07FF reaches for reads as
* well as writes, so the same switch serves the read-modify-write.
*--------------------------------------
SHOWCURSOR   lda   CURSROW
             cmp   MAXROW
             bcs   :skip            ; cursor scrolled off the text area
             jsr   SETROW
             lda   CURSCOL
             and   #$01
             beq   :aux
             sta   MAINWR           ; odd column
             jmp   :rd
:aux         sta   AUXWR            ; even column
:rd          lda   CURSCOL
             lsr
             tay
             lda   (SCRPTR),y
             and   #$7f             ; strip to plain ASCII
             cmp   #$60
             bcs   :put             ; lowercase inverts to itself
             and   #$3f
:put         sta   (SCRPTR),y
:skip        rts

*--------------------------------------
* DRAWSTATUS -- render the status line, inverse video
*--------------------------------------
DRAWSTATUS   lda   #<STATTXT
             sta   STRPTR
             lda   #>STATTXT
             sta   STRPTR+1
             lda   #STATROW
             jsr   SHOWSTRINV
             lda   #$ff             ; force the digits to repaint
             sta   LASTCOL
             sta   LASTLN
             sta   LASTLN+1
             rts

*--------------------------------------
* Data
*--------------------------------------
CHEATTXT     asc   "**bold** _italic_ `code` # H1 ## H2 - list 1. num > quote [txt](url) --- rule"
             dfb   $00

* Placeholder until the buffer and file layers can supply real values.
STATTXT
             hex   A0D5CED4C9D4CCC5C4AECDC4A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A0A0A0A0CCA0A0A0A0A0A0C3A0A0A0A0A0A0B4B6CBA0C6D2C5C5A0A0A0A0
             hex   41ADBFA0C8C5CCD0A0A0A0A0A0A0A0A0
             dfb   $00

*--- screen row base addresses (the usual non-linear Apple II layout) ---
ROWLO        dfb   $00,$80,$00,$80,$00,$80,$00,$80
             dfb   $28,$a8,$28,$a8,$28,$a8,$28,$a8
             dfb   $50,$d0,$50,$d0,$50,$d0,$50,$d0
ROWHI        dfb   $04,$04,$05,$05,$06,$06,$07,$07
             dfb   $04,$04,$05,$05,$06,$06,$07,$07
             dfb   $04,$04,$05,$05,$06,$06,$07,$07

*--- mutable storage, declared but not emitted ---
* Keeping writable data out of the code image means emulated RAM at $2000
* stays byte-identical to the build artifact for as long as the program runs.
             dum   $0200
LINEBUF      ds    SCRW             ; one screen line of screen codes
             dend

             dum   $1430
NUMV         ds    2                ; value being rendered by PUTNUM
PWID         ds    1
PIDX         ds    1
PCOL         ds    1
PDIG         ds    1
PLEAD        ds    1                ; non-zero once a digit has been emitted
LASTLN       ds    2                ; last values painted, to skip redundant work
LASTCOL      ds    1
MSGSHOWN     ds    1                ; a message owns the status line
             dend
