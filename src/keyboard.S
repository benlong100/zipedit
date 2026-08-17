*--------------------------------------
* KEYBOARD.S -- key input, dispatch, and cursor movement
*
* $C000 holds the last key with bit 7 set when one is waiting; writing $C010
* clears the strobe. The Apple keys are NOT in the key byte -- they are bit 7
* of $C061 and $C062, and must be sampled at the moment the key is read, not
* afterwards, or a fast typist outruns them.
*
* The Tab / Ctrl-I collision: the //e keyboard encoder maps both to $89 and
* software cannot tell them apart. So $89 is dispatched positionally -- indent
* when the cursor sits in a line's leading whitespace, italic anywhere else.
*--------------------------------------

*--------------------------------------
* GETKEY -- block until a key is pressed. Returns it in A and KEYCHR, with
*           MODOA / MODCA holding the modifier state at the instant of the read.
*--------------------------------------
GETKEY       lda   KBD
             bpl   GETKEY
             sta   KEYCHR
             lda   OPNAPPLE
             and   #$80
             sta   MODOA
             lda   CLSAPPLE
             and   #$80
             sta   MODCA
             sta   KBDSTRB          ; value written is irrelevant

*--- fold Open-Apple letters to uppercase so OA-q and OA-Q both dispatch
             lda   MODOA
             beq   :done
             lda   KEYCHR
             cmp   #$e1             ; 'a'
             bcc   :done
             cmp   #$fb             ; past 'z'
             bcs   :done
             sec
             sbc   #$20
             sta   KEYCHR
:done        lda   KEYCHR
             rts

*--------------------------------------
* DISPATCH -- run the handler for KEYCHR, or insert it if it is printable
*
* Table entries are 4 bytes: key, required MODOA state, handler address.
* A linear scan is the right call here; the table is far too short for
* anything cleverer to pay for itself.
*--------------------------------------
DISPATCH     ldx   #$00
:scan        lda   KEYTBL,x
             beq   :deflt
             cmp   KEYCHR
             bne   :next
             lda   KEYTBL+1,x
             cmp   MODOA
             bne   :next
             lda   KEYTBL+2,x
             sta   JMPVEC
             lda   KEYTBL+3,x
             sta   JMPVEC+1
             jmp   (JMPVEC)         ; handler's rts returns to our caller
:next        txa
             clc
             adc   #$04
             tax
             jmp   :scan

*--- no table entry: insert printable characters, ignore everything else
:deflt       lda   MODOA
             bne   :ret
             lda   KEYCHR
             cmp   #$a0             ; below space
             bcc   :ret
             cmp   #$ff             ; Delete
             bcs   :ret
             jsr   INSCHR
             jsr   FASTOK           ; plain typing touches one row...
             jsr   WRAPCHECK        ; ...unless this wraps, which moves CURLNO
:ret         rts

*--------------------------------------
* Dispatch table
*--------------------------------------
KEYTBL
             dfb   $88,$00
             da    KLEFT            ; left arrow
             dfb   $95,$00
             da    KRIGHT           ; right arrow
             dfb   $8b,$00
             da    KUP              ; up arrow
             dfb   $8a,$00
             da    KDOWN            ; down arrow
             dfb   $8d,$00
             da    KRETURN          ; Return
             dfb   $ff,$00
             da    KDELETE          ; Delete
             dfb   $84,$00
             da    KDELFWD          ; Ctrl-D
             dfb   $81,$00
             da    BOL              ; Ctrl-A
             dfb   $85,$00
             da    EOL              ; Ctrl-E
             dfb   $82,$00
             da    KBOLD            ; Ctrl-B
             dfb   $89,$00
             da    KTABITAL         ; Ctrl-I / Tab
             dfb   $c3,$80
             da    KCOPY            ; OA-C
             dfb   $d8,$80
             da    KCUT             ; OA-X
             dfb   $d6,$80
             da    KPASTE           ; OA-V
             dfb   $c6,$80
             da    KFIND            ; OA-F
             dfb   $c7,$80
             da    FINDNEXT         ; OA-G
             dfb   $cc,$80
             da    KGOTO            ; OA-L
             dfb   $bf,$80
             da    TOGGLECHEAT      ; OA-?
             dfb   $8b,$80
             da    KPGUP            ; OA-up
             dfb   $8a,$80
             da    KPGDN            ; OA-down
             dfb   $bc,$80
             da    KTOP             ; OA-<
             dfb   $be,$80
             da    KEND             ; OA->
             dfb   $d2,$80
             da    REFLOW           ; OA-R
             dfb   $d3,$80
             da    KSAVE            ; OA-S
             dfb   $cf,$80
             da    KLOAD            ; OA-O
             dfb   $d1,$80
             da    KQUIT            ; OA-Q
             dfb   $00              ; end of table

*--------------------------------------
* Simple handlers
*--------------------------------------
FASTOK       lda   #$01
             sta   FASTDRAW
             rts

KLEFT        jsr   FASTOK
             jmp   GAPLEFT
KRIGHT       jsr   FASTOK
             jmp   GAPRIGHT
KDELETE      jsr   FASTOK
             jmp   DELBACK
KDELFWD      jsr   FASTOK
             jmp   DELFWD

KRETURN      lda   #$8d
             jmp   INSCHR

*--------------------------------------
* KQUIT -- hand control back to ProDOS
*--------------------------------------
KQUIT        jsr   MLI
             dfb   $65
             da    QUITPARM
             rts                    ; not reached
QUITPARM     dfb   $04
             dfb   $00
             da    $0000
             dfb   $00
             da    $0000

*--------------------------------------
* PEEKBACK -- read the byte before the cursor without moving it.
*             Carry set if the cursor is at the start of the buffer.
*--------------------------------------
PEEKBACK     jsr   ATSTART
             bcs   :none
             lda   GAPBEG
             bne   :same
             lda   GAPBEG+1         ; low byte is zero, borrow from high
             sec
             sbc   #$01
             sta   AUXPTR+1
             lda   #$ff
             sta   AUXPTR
             jmp   :rd
:same        sec
             sbc   #$01
             sta   AUXPTR
             lda   GAPBEG+1
             sta   AUXPTR+1
:rd          ldy   #$00
             jsr   AUXRD
             clc
             rts
:none        sec
             rts

*--------------------------------------
* PEEKFWD -- read the byte at the cursor without moving it.
*            Carry set if the cursor is at the end of the buffer.
*--------------------------------------
PEEKFWD      jsr   ATEND
             bcs   :none
             lda   GAPEND
             sta   AUXPTR
             lda   GAPEND+1
             sta   AUXPTR+1
             ldy   #$00
             jsr   AUXRD
             clc
             rts
:none        sec
             rts

*--------------------------------------
* BOL / EOL -- move the cursor to the start or end of the current line
*--------------------------------------
BOL          jsr   PEEKBACK
             bcs   :done
             cmp   #$8d
             beq   :done
             jsr   GAPLEFT
             jmp   BOL
:done        rts

EOL          jsr   PEEKFWD
             bcs   :done
             cmp   #$8d
             beq   :done
             jsr   GAPRIGHT
             jmp   EOL
:done        rts

*--------------------------------------
* KUP -- previous line, keeping the column where possible
*
* Counting the column by walking to the start of the line is destructive, but
* that is fine: we were going to leave this line anyway.
*--------------------------------------
KUP          lda   #$00
             sta   TMPC
:back        jsr   PEEKBACK
             bcs   :fin             ; already on the first line
             cmp   #$8d
             beq   :atbol
             jsr   GAPLEFT
             inc   TMPC
             jmp   :back
:atbol       jsr   GAPLEFT          ; step back over the CR
             jsr   BOL
             jmp   FWDCOL
:fin         rts

*--------------------------------------
* KDOWN -- next line, keeping the column where possible
*--------------------------------------
KDOWN        lda   #$00
             sta   TMPC
:back        jsr   PEEKBACK
             bcs   :havecol
             cmp   #$8d
             beq   :havecol
             jsr   GAPLEFT
             inc   TMPC
             jmp   :back
:havecol     jsr   EOL
             jsr   PEEKFWD
             bcs   :fin             ; no line below
             jsr   GAPRIGHT         ; step over the CR
             jmp   FWDCOL
:fin         rts

*--------------------------------------
* FWDCOL -- advance TMPC columns, stopping at the end of the line
*--------------------------------------
FWDCOL       lda   TMPC
             beq   :done
             jsr   PEEKFWD
             bcs   :done
             cmp   #$8d
             beq   :done
             jsr   GAPRIGHT
             dec   TMPC
             jmp   FWDCOL
:done        rts

*--------------------------------------
* INLEAD -- carry set if the cursor sits in a line's leading whitespace.
*           Scans backwards through aux without disturbing the gap.
*--------------------------------------
INLEAD       lda   GAPBEG
             sta   AUXPTR
             lda   GAPBEG+1
             sta   AUXPTR+1
:loop        lda   AUXPTR+1         ; reached the start of the buffer?
             cmp   #AUXLO
             bne   :dec
             lda   AUXPTR
             bne   :dec
             sec
             rts
:dec         lda   AUXPTR
             bne   :d1
             dec   AUXPTR+1
:d1          dec   AUXPTR
             ldy   #$00
             jsr   AUXRD
             cmp   #$8d             ; start of line, all spaces behind us
             beq   :yes
             cmp   #$a0             ; space
             beq   :loop
             clc                    ; real text behind the cursor
             rts
:yes         sec
             rts

*--------------------------------------
* KTABITAL -- $89 is both Tab and Ctrl-I. Indent in leading whitespace,
*             italic anywhere else.
*--------------------------------------
KTABITAL     jsr   INLEAD
             bcs   :indent
             jmp   KITALIC          ; too far for a relative branch
*--- indent two spaces
:indent      lda   #$a0
             jsr   INSCHR
             lda   #$a0
             jmp   INSCHR

*--------------------------------------
* KBOLD / KITALIC -- wrap the cursor in emphasis markers and sit between them
*
* Word-aware wrapping comes with the editing-operations work; for now this
* inserts the markers and leaves the cursor in the middle, which is what you
* want when reaching for emphasis before typing the word.
*--------------------------------------
