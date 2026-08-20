*--------------------------------------
* MACHINE.S -- which //e are we on, and which glyphs can it draw
*
* MouseText lives at $40-$5F of the ALTERNATE character set, and only on an
* Enhanced //e. The original //e keeps a second, redundant copy of inverse
* uppercase there, so every MouseText code we draw comes out as a letter:
*
*     $5F vertical rule  -> inverse _        $4C thin rule -> inverse L
*     $5C thick rule     -> inverse \        $56 checker   -> inverse V
*
* The help screen's border is therefore a fence of L's and backslashes, and the
* prompt cursor is a V. Legible, but plainly broken.
*
* $41, the open apple, is the exception worth knowing: it lands on inverse A,
* which reads perfectly well as the Apple key. The status row, the splash and
* every OA- label in the help screen need no substitute at all.
*
* So four codes need replacing, and one replacement serves all four: $20, an
* inverse space. MouseText never touched $20-$3F, so a solid block is a solid
* block on both machines -- and boxes were drawn out of solid blocks for years
* before MouseText existed.
*--------------------------------------

*--- A disk can be patched to force the plain glyphs on a machine that would
*    otherwise be detected as Enhanced. tools/forceplain.py finds the marker
*    and sets the byte after it; the suite uses that to exercise this path on
*    an Enhanced machine, and it is an escape hatch for a //e whose CPU was
*    upgraded without its character generator.
             asc   "GLYPH"
FORCEPL      dfb   $00

*--------------------------------------
* DETECTMT -- decide whether MouseText can be drawn
*
* Apple's own note identifies an Enhanced //e by $FBC0 ($E0 enhanced, $EA
* original). Reading it is not a plain LDA: ProDOS 8 lives in the language
* card, so $FBC0 reads ProDOS rather than ROM unless the card is switched out
* and then restored to exactly the state ProDOS expects, with interrupts off.
* Getting that restore wrong is a hang, not a cosmetic bug.
*
* The enhancement was a set -- 65C02, ROMs and character generator together --
* so the CPU answers the same question without touching the language card at
* all. In decimal mode the 65C02 sets N and Z from the decimal result and the
* NMOS 6502 sets them from the binary one, which is the classic test: $99 + $01
* is $00 on a 65C02 and $9A on a 6502.
*
* It is wrong only on a machine enhanced by halves -- a 65C02 dropped in
* without the character ROM -- which is what FORCEPL above is for.
*--------------------------------------
DETECTMT     lda   FORCEPL          ; a patched disk overrides the test
             bne   :plain
             sed
             lda   #$99
             clc
             adc   #$01             ; 65C02: $00, so Z set. 6502: $9A, Z clear
             cld                    ; CLD leaves N and Z alone
             beq   :mtext
:plain       lda   #$00
             beq   :set             ; always taken
:mtext       lda   #$80
:set         sta   HASMTEXT
             rts

*--------------------------------------
* PLAINIFY -- rewrite the help screens for a machine without MouseText
*
* Called once at startup, and only when MouseText is missing, so the Enhanced
* path costs one branch. The rows are null-terminated strings of screen codes
* reached through the same two tables HELPSHOW walks, so this needs no second
* copy of the help screen and no change to how it is drawn.
*--------------------------------------
PLAINIFY     bit   HASMTEXT
             bmi   :done            ; MouseText is there: leave the rows alone
             lda   #$00
             sta   PLI
:row         lda   PLI
             asl
             tay
             lda   HELPTBL1,y
             sta   STRPTR
             lda   HELPTBL1+1,y
             sta   STRPTR+1
             jsr   :scan
             lda   PLI
             asl
             tay
             lda   HELPTBL2,y
             sta   STRPTR
             lda   HELPTBL2+1,y
             sta   STRPTR+1
             jsr   :scan
             inc   PLI
             lda   PLI
             cmp   #HELPN
             bne   :row
:done        rts

*--- one row: every rule becomes a solid block, everything else stands
:scan        ldy   #$00
:next        lda   (STRPTR),y
             beq   :end             ; end of the row
             cmp   #$4c             ; thin rule
             beq   :sub
             cmp   #$5c             ; thick rule
             beq   :sub
             cmp   #$5f             ; vertical
             bne   :on
:sub         lda   #$20             ; inverse space: a solid block
             sta   (STRPTR),y
:on          iny
             bne   :next
:end         rts

*--- Scratch. These live in a dum block rather than in the loaded image
*    because the image itself must stay byte-identical to the file on disk --
*    the suite compares the two, which is what catches a stale build. Both are
*    written before they are read: DETECTMT sets HASMTEXT at startup, ahead of
*    anything that draws, and PLAINIFY sets PLI before its loop.
             dum   $1441            ; $1440 is splash's, $1450 is wrap's
HASMTEXT     ds    1                ; $80 when MouseText can be drawn
PLI          ds    1                ; which row PLAINIFY is on
             dend
