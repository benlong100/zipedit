*--------------------------------------
* MOUSETEXT.S -- probe the MouseText glyphs
*
* With the alternate character set on, screen codes $40-$5F are MouseText on an
* Enhanced //e instead of the inverse/flashing capitals of the primary set.
* This displays all 32 with their hex codes underneath so the box-drawing ones
* can be identified by eye rather than recalled.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   EDIT.SYSTEM

STORE80ON    equ   $c001
COL80ON      equ   $c00d
ALTCHARON    equ   $c00f
MAINWR       equ   $c054
AUXWR        equ   $c055
TEXTON       equ   $c051
MIXEDOFF     equ   $c052
HIRESOFF     equ   $c056

SCRPTR       equ   $06
CODE         equ   $08
COL          equ   $09
COUNT        equ   $0a
IDX          equ   $0b
HTOP         equ   $0c
HBOT         equ   $0d
BROW         equ   $0e
BCOL         equ   $0f
SIDES        equ   $10

*--------------------------------------
             sta   TEXTON
             sta   MIXEDOFF
             sta   HIRESOFF
             sta   COL80ON
             sta   STORE80ON
             sta   ALTCHARON
             jsr   CLEAR

*--- a box drawn with the supplied codes:
*    $40 TL  $41 TR  $42 BL  $43 BR  $44 horizontal  $45 vertical
             lda   #$02
             jsr   SETROW
             lda   #$40             ; top left
             ldx   #$04
             jsr   PUTAT
             lda   #$05
             sta   COL
             lda   #$14
             sta   COUNT
:t           lda   #$44             ; horizontal
             ldx   COL
             jsr   PUTAT
             inc   COL
             dec   COUNT
             bne   :t
             lda   #$41             ; top right
             ldx   #$19
             jsr   PUTAT

             lda   #$03
             jsr   SETROW
             lda   #$45             ; vertical
             ldx   #$04
             jsr   PUTAT
             lda   #$45
             ldx   #$19
             jsr   PUTAT

             lda   #$04
             jsr   SETROW
             lda   #$42             ; bottom left
             ldx   #$04
             jsr   PUTAT
             lda   #$05
             sta   COL
             lda   #$14
             sta   COUNT
:b           lda   #$44
             ldx   COL
             jsr   PUTAT
             inc   COL
             dec   COUNT
             bne   :b
             lda   #$43             ; bottom right
             ldx   #$19
             jsr   PUTAT

*--- and the T junctions / intersection on row 7
             lda   #$07
             jsr   SETROW
             lda   #$46
             ldx   #$04
             jsr   PUTAT
             lda   #$47
             ldx   #$08
             jsr   PUTAT
             lda   #$48
             ldx   #$0c
             jsr   PUTAT
             lda   #$49
             ldx   #$10
             jsr   PUTAT
             lda   #$4a
             ldx   #$14
             jsr   PUTAT
:hang        jmp   :hang

*--------------------------------------
* HEXCH -- A = nibble, returns the normal-video screen code for it
*--------------------------------------
HEXCH        cmp   #$0a
             bcc   :dig
             clc
             adc   #$b7             ; 'A'-10, high ASCII
             rts
:dig         clc
             adc   #$b0             ; '0', high ASCII
             rts

*--------------------------------------
* PUTAT -- A = screen code, X = column, row already in SCRPTR
*--------------------------------------
PUTAT        pha
             txa
             and   #$01
             beq   :aux
             sta   MAINWR
             jmp   :put
:aux         sta   AUXWR
:put         txa
             lsr
             tay
             pla
             sta   (SCRPTR),y
             rts

SETROW       tax
             lda   ROWLO,x
             sta   SCRPTR
             lda   ROWHI,x
             sta   SCRPTR+1
             rts

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

ROWLO        dfb   $00,$80,$00,$80,$00,$80,$00,$80
             dfb   $28,$a8,$28,$a8,$28,$a8,$28,$a8
             dfb   $50,$d0,$50,$d0,$50,$d0,$50,$d0
ROWHI        dfb   $04,$04,$05,$05,$06,$06,$07,$07
             dfb   $04,$04,$05,$05,$06,$06,$07,$07
             dfb   $04,$04,$05,$05,$06,$06,$07,$07
