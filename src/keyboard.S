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
             jsr   DELSEL           ; typing replaces the selection
             lda   KEYCHR
             jsr   INSCHR
             jsr   FASTOK           ; plain typing touches one row...
             jsr   WRAPCHECK        ; looks ahead down the line, not just at CCOL
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
             da    KUPSEL           ; up arrow
             dfb   $8a,$00
             da    KDOWNSEL         ; down arrow
             dfb   $9b,$00
             da    SELESC           ; Esc cancels selecting
             dfb   $a0,$80
             da    SELTOGGLE        ; OA-Space latches selection mode
             dfb   $8d,$00
             da    KRETURN          ; Return
             dfb   $ff,$80
             da    KDELWORD         ; OA-Delete
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
             dfb   $99,$00
             da    KDELEOL          ; Ctrl-Y
             dfb   $88,$80
             da    KWORDLSEL        ; OA-left
             dfb   $95,$80
             da    KWORDRSEL        ; OA-right
             dfb   $c8,$80
             da    HELPSHOW         ; OA-H, alias for OA-?
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
             da    HELPSHOW         ; OA-?
             dfb   $af,$80
             da    TOGGLECHEAT      ; OA-/  (same key as ?, unshifted)
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
             dfb   $ce,$80
             da    KNEW             ; OA-N
             dfb   $d7,$80
             da    KWORDS           ; OA-W
             dfb   $c1,$80
             da    KSAVEAS          ; OA-A
             dfb   $00              ; end of table

*--------------------------------------
* Simple handlers
*--------------------------------------
FASTOK       lda   #$01
             sta   FASTDRAW
             rts

KLEFT        jsr   SELUPD
             jsr   FASTOK
             jmp   GAPLEFT
KRIGHT       jsr   SELUPD
             jsr   FASTOK
             jmp   GAPRIGHT
KUPSEL       jsr   SELUPD
             jmp   KUP
KDOWNSEL     jsr   SELUPD
             jmp   KDOWN
KWORDLSEL    jsr   SELUPD
             jmp   KWORDL
KWORDRSEL    jsr   SELUPD
             jmp   KWORDR

*--- with a selection up, Delete removes the selection rather than a character
KDELETE      lda   SELACT
             beq   :plain
             jmp   DELSEL
:plain       jsr   FASTOK
             jmp   DELBACK
KDELFWD      lda   SELACT
             beq   :plain
             jmp   DELSEL
:plain       jsr   FASTOK
             jmp   DELFWD

*--------------------------------------
* KDELWORD -- delete back to the start of the word (OA-Delete)
*
* Mid-word it deletes back to that word's start. Sitting after a word it takes
* the spaces first and then the word, so "one two   " twice leaves "one ".
*
* Ctrl-Delete was the ask, and the //e cannot do it: only the two Apple keys
* are readable as state, and the keyboard encoder folds Ctrl into the character
* code -- the same folding that makes Tab and Ctrl-I both $89. Delete arrives
* as $ff either way. OA-Delete is the sibling of OA-left and OA-right, which
* already move by word.
*
* A newline stops it rather than being eaten, so a word delete never silently
* joins two lines. The one exception is a newline directly behind the cursor,
* where there is no word to take and it behaves as a plain Delete.
*--------------------------------------
KDELWORD     lda   SELACT           ; a selection wins, as it does for Delete
             beq   :start
             jmp   DELSEL

:start       jsr   PEEKBACK
             bcs   :done            ; nothing behind the cursor at all
             cmp   #TEXTLO
             bcs   :spaces
             jmp   DELBACK          ; sitting at a line start: just join

*--- the run of spaces first, so sitting after "word   " takes both
:spaces      jsr   PEEKBACK
             bcs   :done
             cmp   #$a0
             bne   :word
             jsr   DELBACK
             jmp   :spaces

*--- then the word, stopping at a space, a newline, or the start of the buffer
:word        jsr   PEEKBACK
             bcs   :done
             cmp   #TEXTLO+1        ; a space or a break ends the word
             bcc   :done
             jsr   DELBACK
             jmp   :word
:done        rts

KRETURN      lda   #HARDCR          ; the writer asked for this one
             jmp   INSCHR

*--------------------------------------
* ASKUNSAVED -- guard anything that would throw the document away
*
* Carry set to go ahead, clear to stay put. Shared by OA-Q, OA-N and OA-O --
* all three discard the document completely. OA-O went without it for a while
* and quietly threw away unsaved work, which is exactly the way a guard that
* only some callers use gets found out.
*--------------------------------------
ASKUNSAVED   lda   MODFLAG
             beq   :yes             ; nothing to lose
             lda   #<MSGUNSAVED
             sta   STRPTR
             lda   #>MSGUNSAVED
             sta   STRPTR+1
             jsr   SHOWMSG

:ask         jsr   GETKEY
             and   #$df             ; fold case; leaves Esc alone
             cmp   #$d3             ; S -- save first
             beq   :save
             cmp   #$c4             ; D -- discard
             beq   :discard
             cmp   #$9b             ; Esc -- carry on editing
             beq   :no
             jmp   :ask

*--- KSAVE clears MODFLAG only if the save actually succeeded, so this both
*    handles a cancelled prompt and refuses to go on after a write error
:save        jsr   KSAVE
             lda   MODFLAG
             bne   :no
:discard     jsr   RESTORESTAT      ; retire the prompt before going ahead
:yes         sec
             rts
:no          jsr   RESTORESTAT
             clc
             rts

MSGUNSAVED   asc   " UNSAVED CHANGES.  S = SAVE FIRST   D = DISCARD   ESC = CANCEL"
             dfb   $00

*--------------------------------------
* KQUIT -- hand control back to ProDOS, but not over unsaved work
*
* OA-Q sits next to OA-S and OA-O on the keyboard, so a slip is easy and the
* cost is the whole document. If anything has been edited since the last save
* or load, ask first.
*--------------------------------------
KQUIT        jsr   ASKUNSAVED
             bcc   :stay
             jsr   MLI
             dfb   $65
             da    QUITPARM
:stay        rts                    ; the MLI quit does not come back

QUITPARM     dfb   $04
             dfb   $00
             da    $0000
             dfb   $00
             da    $0000

*--------------------------------------
* KNEW -- start an empty document (OA-N)
*
* Guarded exactly as quitting is, since it throws the document away just as
* thoroughly. This resets everything START sets up, minus the sample text: an
* empty gap buffer, viewport and cursor at the top, no selection, no goal
* column, and the filename forgotten so the next save asks for a new one.
*
* Nothing clears the screen here. BLANKTAIL already wipes the text rows past
* the end of the buffer on the next full redraw, and an empty buffer means
* every one of them.
*--------------------------------------
KNEW         jsr   ASKUNSAVED
             bcc   :stay
             lda   #$00
             sta   SCROLLTOP
             sta   SCROLLTOP+1
             sta   GOALCOL
             sta   VERTMOVE
             sta   WASVERT
             sta   FNAME            ; length 0, so OA-S asks for a name
             jsr   SELINIT
             jsr   BUFINIT          ; empties the buffer; clears MODFLAG too
             jsr   HOMECURSOR
             jsr   DRAWSTATUS
             jmp   STATUPD
:stay        rts

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
             cmp   #TEXTLO
             bcc   :done
             jsr   GAPLEFT
             jmp   BOL
:done        rts

EOL          jsr   PEEKFWD
             bcs   :done
             cmp   #TEXTLO
             bcc   :done
             jsr   GAPRIGHT
             jmp   EOL
:done        rts

*--------------------------------------
* VERTSET -- decide what column vertical movement should aim for
*
* The goal column is captured the first time a run of vertical moves begins and
* then left alone, so passing through a short line does not truncate it. Any
* other command clears VERTMOVE, which ends the run.
*
* VERTMOVE covers repeats inside one keystroke -- KPGUP calls KUP many times --
* while WASVERT carries the run across keystrokes.
*--------------------------------------
VERTSET      lda   VERTMOVE
             ora   WASVERT
             bne   :mark
             lda   CCOL             ; fresh run: aim for where we are now
             sta   GOALCOL
:mark        lda   #$01
             sta   VERTMOVE
             rts

*--------------------------------------
* KUP -- previous line, at the goal column
*
* No column counting: CCOL is already maintained, so BOL and a step back over
* the newline is the whole journey.
*--------------------------------------
KUP          jsr   VERTSET
             jsr   BOL
             jsr   PEEKBACK
             bcs   :fin             ; already on the first line
             jsr   GAPLEFT          ; over the newline, to the end of the line above
             jsr   BOL
             lda   GOALCOL
             sta   TMPC
             jmp   FWDCOL
:fin         rts

*--------------------------------------
* KDOWN -- next line, at the goal column
*--------------------------------------
KDOWN        jsr   VERTSET
             jsr   EOL
             jsr   PEEKFWD
             bcs   :fin             ; no line below
             jsr   GAPRIGHT         ; over the newline, to the start of the next
             lda   GOALCOL
             sta   TMPC
             jmp   FWDCOL
:fin         rts

*--------------------------------------
* FWDCOL -- advance TMPC columns, stopping at the end of the line
*--------------------------------------
FWDCOL       lda   TMPC
             beq   :done
             jsr   PEEKFWD
             bcs   :done
             cmp   #TEXTLO
             bcc   :done
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
             cmp   #TEXTLO          ; start of line, all spaces behind us
             bcc   :yes
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
