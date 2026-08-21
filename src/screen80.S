*--------------------------------------
* SCREEN80.S -- the //e's 80 column screen
*
* The three routines that know what the hardware is. Everything else that
* draws goes through LINEBUF and DRAWLINE and does not care: SETROW works
* unchanged at either width because the row base addresses are the same, and
* the LINEBUF routines read GSCRW.
*
* The //e 80-column screen interleaves banks: even screen columns live in
* auxiliary memory, odd columns in main, both at the same offset from the row
* base. With 80STORE on, $C054/$C055 pick which bank a write to $0400-$07FF
* lands in.
*
* Screen codes, with ALTCHARSET on:
*   normal  = ascii | $80          ($A0-$FF)
*   inverse = ascii & $3f          for ascii < $60
*           = ascii                for ascii >= $60 (inverse lowercase)
*--------------------------------------

*--- Which geometry this screen implies. The display picks it, because the
*    width of the screen is a property of the screen and not of the editor.
GEOMTBL      equ   GEOM80

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
