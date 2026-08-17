*--------------------------------------
* CHARSET.S -- character generator probe
*
* Writes ASCII $20-$7F to the 80-column screen using the same direct
* screen-memory writes the display layer will use, so this doubles as a
* proof of the aux/main column interleave.
*
* Screen codes are ASCII | $80 for normal (non-inverse, non-flashing) text,
* which maps $20-$7F onto $A0-$FF contiguously -- so we just increment.
*
* Row layout: rows 2,3,4 hold 32 characters each.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   EDIT.SYSTEM

*--- soft switches ---
STORE80ON    equ   $c001            ; 80STORE on: PAGE2 picks screen half
COL80ON      equ   $c00d            ; 80 column video on
ALTCHARON    equ   $c00f            ; alternate character set
MAINWR       equ   $c054            ; PAGE2 off -> writes go to MAIN  (odd cols)
AUXWR        equ   $c055            ; PAGE2 on  -> writes go to AUX   (even cols)
TEXTON       equ   $c051
MIXEDOFF     equ   $c052
HIRESOFF     equ   $c056

*--- zero page ---
ZPTR         equ   $06              ; screen row pointer
CHR          equ   $08              ; current screen code
ROW          equ   $09

*--------------------------------------
             sta   TEXTON
             sta   MIXEDOFF
             sta   HIRESOFF
             sta   COL80ON
             sta   STORE80ON
             sta   ALTCHARON

             jsr   CLEAR

             lda   #$a0             ; screen code for ASCII $20
             sta   CHR
             lda   #2
             sta   ROW
:rows        jsr   PUTROW
             inc   ROW
             lda   ROW
             cmp   #5
             bne   :rows

:hang        jmp   :hang

*--------------------------------------
* CLEAR -- fill both screen halves with spaces
*--------------------------------------
CLEAR        ldx   #$00
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
* PUTROW -- write 32 consecutive screen codes across row ROW
*
* Even screen columns live in aux, odd columns in main, both at the same
* offset from the row base. So each iteration writes one aux byte and one
* main byte, then advances the offset.
*--------------------------------------
PUTROW       ldx   ROW
             lda   ROWLO,x
             sta   ZPTR
             lda   ROWHI,x
             sta   ZPTR+1
             ldy   #$00
:loop        sta   AUXWR            ; even column
             lda   CHR
             sta   (ZPTR),y
             inc   CHR
             sta   MAINWR           ; odd column
             lda   CHR
             sta   (ZPTR),y
             inc   CHR
             iny
             cpy   #16
             bne   :loop
             rts

*--------------------------------------
* Screen row base addresses (the usual non-linear Apple II layout)
*--------------------------------------
ROWLO        dfb   $00,$80,$00,$80,$00,$80,$00,$80
             dfb   $28,$a8,$28,$a8,$28,$a8,$28,$a8
             dfb   $50,$d0,$50,$d0,$50,$d0,$50,$d0
ROWHI        dfb   $04,$04,$05,$05,$06,$06,$07,$07
             dfb   $04,$04,$05,$05,$06,$06,$07,$07
             dfb   $04,$04,$05,$05,$06,$06,$07,$07
