*--------------------------------------
* SCREEN40.S -- a 40 column screen, for the Apple ][+
*
* The same three routines screen80.S provides, for a machine with no
* auxiliary bank and no 80-column hardware. Everything else that draws is
* shared and does not know the difference: SETROW works unchanged because the
* row base addresses are identical at both widths, and the LINEBUF routines
* read GSCRW.
*
* This is simpler than the //e version, not harder. Forty columns is main
* memory at $0400-$07FF with no bank switching at all, so DRAWLINE is one
* copy instead of two and CLRSCRN fills one screen instead of two halves.
*
* Nothing here touches a soft switch the ][+ does not have. TXTSET, MIXCLR
* and HIRESOFF exist on every machine in the family; 80STORE, 80VID and
* ALTCHARSET do not, and are deliberately not written even to turn them off.
*
* No ALTCHARSET means no MouseText and no inverse lowercase, which is correct
* here: a ][+ character generator has neither. Text at $A0 and above draws as
* capitals whatever case it was, because that is all the ROM has. Everything
* the editor puts on screen is legible; it is simply all in capitals.
*--------------------------------------

*--- Which geometry this screen implies.
GEOMTBL      equ   GEOM40

*--------------------------------------
* DISPINIT -- 40 column text mode, screen cleared
*--------------------------------------
DISPINIT     sta   TXTSET
             sta   MIXCLR
             sta   HIRESOFF
             jsr   CLRSCRN
             rts

*--------------------------------------
* CLRSCRN -- fill the screen with spaces
*
* $0400-$07FF is 1K, and the 24 rows are scattered through it in the Apple's
* usual order with holes between them. Filling the lot is simpler than
* walking the rows and costs nothing: the holes are not displayed.
*--------------------------------------
CLRSCRN      ldx   #$00
             lda   #$a0
:loop        sta   $0400,x
             sta   $0500,x
             sta   $0600,x
             sta   $0700,x
             inx
             bne   :loop
             rts

*--------------------------------------
* DRAWLINE -- A = row. Blit LINEBUF to the screen.
*
* One pass, one bank. X and Y walk together, unlike the //e's two passes over
* alternating columns, and the loop bound comes from the geometry record so
* this stays honest if a 40-column machine ever turns out to be 32 or 64.
*--------------------------------------
DRAWLINE     jsr   SETROW
             ldy   #$00
:loop        lda   LINEBUF,y
             jsr   FOLDCASE
             sta   (SCRPTR),y
             iny
             cpy   GSCRW
             bne   :loop
             rts

*--------------------------------------
* PUTCELL -- put the character in A at column X of the row SCRPTR points at
*
* One bank, so the column IS the offset. The //e version halves the column and
* picks a bank by its parity, which at 40 columns quietly sent every other
* character into auxiliary memory where nothing displays it -- "SAMPLE.MD"
* came out as "SML.D", which is a good way to be reminded that a routine
* touching a soft switch belongs to the screen and not to the layout.
*--------------------------------------
PUTCELL      jsr   FOLDCASE
             pha
             txa
             tay
             pla
             sta   (SCRPTR),y
             rts

*--------------------------------------
* FOLDCASE -- lowercase to uppercase, on the way to the screen
*
* This character generator holds 64 glyphs, so $E0-$FF repeats $A0-$BF: a
* lowercase 'a' does not come out as a capital A, it comes out as an
* exclamation mark. A splash screen in mixed case reads as gibberish, which
* is how this was found -- on the hardware, since every emulator to hand
* draws lowercase perfectly well.
*
* Folding here rather than in the strings means everything is covered at
* once: the splash, the help screen, the prompts, and the writer's own text.
* The buffer keeps the case that was typed; only the screen loses it.
*--------------------------------------
FOLDCASE     cmp   #$40
             bcc   :done            ; $00-$3F is already inverse, and that is
                                    ; the one thing this ROM does properly
             cmp   #$80
             bcs   :high
             clc
             adc   #$80             ; $40-$7F flashes here. The //e keeps
                                    ; MouseText and the open apple there and
                                    ; they would blink at the reader.

*--- One alphabet, two cases to show. Apple Writer's answer, and it is still
*    the right one: a lowercase letter draws as an ordinary capital, and a
*    CAPITAL draws inverse. So text reads normally and the capitals you asked
*    for are the ones that stand out -- which is exactly backwards from how it
*    looks written down, and exactly right on the screen.
:high        cmp   #$e1             ; 'a'
             bcc   :upper
             cmp   #$fb             ; past 'z'
             bcs   :sym
             sec
             sbc   #$20             ; lowercase -> a plain capital
             rts
:upper       cmp   #$c1             ; 'A'
             bcc   :done
             cmp   #$db             ; past 'Z'
             bcs   :done
             and   #$3f             ; CAPITAL -> inverse capital
             rts
:sym         sec
             sbc   #$20             ; the few symbols above 'z'
:done        rts

*--------------------------------------
* SHOWCURSOR -- invert the character cell the cursor sits on
*
* One bank, so the column is the offset and the read-modify-write needs no
* switch at all. The inversion itself is shared knowledge about screen codes
* rather than about hardware: strip to plain ASCII, and anything below $60
* inverts by dropping to $00-$3F. Above that would be inverse lowercase, which
* this machine's character generator does not have -- it draws as capitals
* either way, so the cell still visibly inverts.
*--------------------------------------
SHOWCURSOR   lda   CURSROW
             cmp   MAXROW
             bcs   :skip            ; cursor scrolled off the text area
             jsr   SETROW
             ldy   CURSCOL
             lda   (SCRPTR),y
             and   #$7f             ; strip to plain ASCII
             cmp   #$60
             bcs   :put             ; lowercase inverts to itself
             and   #$3f
:put         sta   (SCRPTR),y
:skip        rts

*--------------------------------------
* INVCHR -- the inverse of the character in A
*
* There is no inverse lowercase on this machine, so the //e's rule -- leave
* $60-$7F alone, it is already inverse -- puts a selected lowercase letter in
* the FLASHING range, where FOLDCASE lifts it straight back to a plain
* capital. Selected text then looked exactly like unselected text: the
* selection was real, and cutting proved it, but nothing was highlighted.
*
* So fold a lowercase letter up to its capital first, and invert that. A
* selected capital and a selected lowercase letter therefore look the same,
* which is what one alphabet and one highlight between them can manage.
*--------------------------------------
INVCHR       and   #$7f
             cmp   #$61             ; 'a'
             bcc   :inv
             cmp   #$7b             ; past 'z'
             bcs   :inv
             sec
             sbc   #$20             ; lowercase -> its capital
:inv         and   #$3f             ; and into the inverse range
             rts
