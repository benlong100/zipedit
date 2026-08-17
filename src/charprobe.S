*--------------------------------------
* CHARPROBE.S -- character generator probe, for real hardware
*
* Built to settle a question the emulator cannot: which glyphs this machine's
* character ROM actually has at screen codes $40-$5F with the alternate
* character set enabled.
*
* MouseText arrived with the Enhanced //e ROM. An original //e has no MouseText
* at all, and an emulator may be modelling either. So the probe identifies the
* machine first, then shows the glyphs, so the two can be read together.
*
* Three pages, any key to advance:
*   1  machine identification
*   2  all 32 codes $40-$5F with their hex values
*   3  each code tiled eight times, which makes rules, verticals and combs
*      obvious where a single 7x8 glyph is guesswork
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   PROBE.SYSTEM

*--- soft switches ---
STORE80ON    equ   $c001
COL80ON      equ   $c00d
ALTCHARON    equ   $c00f
ALTCHAROFF   equ   $c00e
MAINWR       equ   $c054
AUXWR        equ   $c055
TEXTON       equ   $c051
MIXEDOFF     equ   $c052
HIRESOFF     equ   $c056
KBD          equ   $c000
KBDSTRB      equ   $c010

*--- ROM identification bytes ---
IDBYTE1      equ   $fbb3
IDBYTE2      equ   $fbc0

*--- zero page ---
SCRPTR       equ   $06
STRPTR       equ   $08
CODE         equ   $0a
COL          equ   $0b
ROW          equ   $0c
COUNT        equ   $0d
IDX          equ   $0e

*--------------------------------------
START        sta   TEXTON
             sta   MIXEDOFF
             sta   HIRESOFF
             sta   COL80ON
             sta   STORE80ON
             sta   ALTCHARON

             jsr   PAGE1
             jsr   WAITKEY
             jsr   PAGE2
             jsr   WAITKEY
             jsr   PAGE3
             jsr   WAITKEY
             jmp   START

*--------------------------------------
* PAGE1 -- what machine is this?
*--------------------------------------
PAGE1        jsr   CLEAR
             lda   #<T1
             ldy   #>T1
             ldx   #$02
             jsr   SAY
             lda   #<T2
             ldy   #>T2
             ldx   #$04
             jsr   SAY

*--- $FBB3
             lda   #<T3
             ldy   #>T3
             ldx   #$06
             jsr   SAY
             lda   #$06
             jsr   SETROW
             lda   IDBYTE1
             ldx   #$16
             jsr   HEXBYTE

*--- $FBC0
             lda   #<T4
             ldy   #>T4
             ldx   #$07
             jsr   SAY
             lda   #$07
             jsr   SETROW
             lda   IDBYTE2
             ldx   #$16
             jsr   HEXBYTE

*--- verdict
             lda   IDBYTE1
             cmp   #$06
             bne   :older
             lda   IDBYTE2
             cmp   #$e0
             beq   :enh
             cmp   #$ea
             beq   :orig
             cmp   #$00
             beq   :iic
             lda   #<V4
             ldy   #>V4
             jmp   :say
:enh         lda   #<V1
             ldy   #>V1
             jmp   :say
:orig        lda   #<V2
             ldy   #>V2
             jmp   :say
:iic         lda   #<V3
             ldy   #>V3
             jmp   :say
:older       lda   #<V5
             ldy   #>V5
:say         ldx   #$09
             jsr   SAY

             lda   #<T5
             ldy   #>T5
             ldx   #$0b
             jsr   SAY
             lda   #<T6
             ldy   #>T6
             ldx   #$0c
             jsr   SAY
             lda   #<TNEXT
             ldy   #>TNEXT
             ldx   #$16
             jsr   SAY
             rts

*--------------------------------------
* PAGE2 -- the 32 codes with hex labels
*--------------------------------------
PAGE2        jsr   CLEAR
             lda   #<T7
             ldy   #>T7
             ldx   #$01
             jsr   SAY
             lda   #$40
             sta   CODE
             lda   #$04
             sta   ROW
             jsr   BLOCK16
             lda   #$0a
             sta   ROW
             jsr   BLOCK16
             lda   #<TNEXT
             ldy   #>TNEXT
             ldx   #$16
             jsr   SAY
             rts

*--- 16 glyphs on ROW, hex labels on ROW+1
BLOCK16      lda   ROW
             jsr   SETROW
             lda   #$06
             sta   COL
             lda   #$10
             sta   COUNT
:g           lda   CODE
             ldx   COL
             jsr   PUTAT
             inc   CODE
             lda   COL
             clc
             adc   #$04
             sta   COL
             dec   COUNT
             bne   :g

             lda   CODE             ; rewind for the labels
             sec
             sbc   #$10
             sta   CODE
             lda   ROW
             clc
             adc   #$01
             jsr   SETROW
             lda   #$06
             sta   COL
             lda   #$10
             sta   COUNT
:l           lda   CODE
             ldx   COL
             jsr   HEXBYTE
             inc   CODE
             lda   COL
             clc
             adc   #$04
             sta   COL
             dec   COUNT
             bne   :l
             rts

*--------------------------------------
* PAGE3 -- each code tiled, so shapes are unmistakable
*--------------------------------------
PAGE3        jsr   CLEAR
             lda   #<T8
             ldy   #>T8
             ldx   #$00
             jsr   SAY
             lda   #$40
             sta   CODE
             lda   #$00
             sta   IDX
:row         lda   IDX
             cmp   #$20
             bcs   :done
             lsr                    ; two per screen row
             clc
             adc   #$02
             jsr   SETROW
             lda   IDX
             and   #$01
             beq   :left
             lda   #$2a
             jmp   :go
:left        lda   #$04
:go          sta   COL
             lda   CODE
             ldx   COL
             jsr   HEXBYTE
             lda   COL
             clc
             adc   #$03
             sta   COL
             lda   #$0a
             sta   COUNT
:tile        lda   CODE
             ldx   COL
             jsr   PUTAT
             inc   COL
             dec   COUNT
             bne   :tile
             inc   CODE
             inc   IDX
             jmp   :row
:done        lda   #<TNEXT
             ldy   #>TNEXT
             ldx   #$16
             jsr   SAY
             rts

*--------------------------------------
* Helpers
*--------------------------------------
* SAY -- A/Y = string, X = row. Draws at column 2.
SAY          sta   STRPTR
             sty   STRPTR+1
             txa
             jsr   SETROW
             ldx   #$02
             ldy   #$00
:loop        lda   (STRPTR),y
             beq   :done
             sty   COUNT
             jsr   PUTAT
             ldy   COUNT
             inx
             iny
             bne   :loop
:done        rts

* HEXBYTE -- A = byte, X = column, row already set
HEXBYTE      pha
             lsr
             lsr
             lsr
             lsr
             jsr   HEXCH
             jsr   PUTAT
             inx
             pla
             and   #$0f
             jsr   HEXCH
             jsr   PUTAT
             rts

HEXCH        cmp   #$0a
             bcc   :dig
             clc
             adc   #$b7
             rts
:dig         clc
             adc   #$b0
             rts

* PUTAT -- A = screen code, X = column, row in SCRPTR. Preserves X.
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

WAITKEY      lda   KBD
             bpl   WAITKEY
             sta   KBDSTRB
             rts

*--------------------------------------
T1           asc   "CHARACTER GENERATOR PROBE"
             dfb   $00
T2           asc   "Which glyphs does this machine actually have?"
             dfb   $00
T3           asc   "ROM byte $FBB3 ="
             dfb   $00
T4           asc   "ROM byte $FBC0 ="
             dfb   $00
T5           asc   "MouseText exists only on the Enhanced //e."
             dfb   $00
T6           asc   "An original //e shows inverse capitals instead."
             dfb   $00
T7           asc   "Screen codes $40-$5F, alternate character set:"
             dfb   $00
T8           asc   "Each code tiled ten times:"
             dfb   $00
TNEXT        asc   "press any key"
             dfb   $00

V1           asc   ">> ENHANCED //e  -- MouseText should be present"
             dfb   $00
V2           asc   ">> ORIGINAL //e  -- no MouseText in this ROM"
             dfb   $00
V3           asc   ">> Apple //c"
             dfb   $00
V4           asc   ">> //e family, unrecognised sub-type"
             dfb   $00
V5           asc   ">> older than a //e"
             dfb   $00

ROWLO        dfb   $00,$80,$00,$80,$00,$80,$00,$80
             dfb   $28,$a8,$28,$a8,$28,$a8,$28,$a8
             dfb   $50,$d0,$50,$d0,$50,$d0,$50,$d0
ROWHI        dfb   $04,$04,$05,$05,$06,$06,$07,$07
             dfb   $04,$04,$05,$05,$06,$06,$07,$07
             dfb   $04,$04,$05,$05,$06,$06,$07,$07
