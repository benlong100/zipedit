*--------------------------------------
* KEYS2P.S -- reading the keyboard on an Apple ][+
*
* There are no Apple keys on this machine, so there are no modifiers to read
* and every command has to live in the character code itself. See
* docs/design.md section 9 for the keymap that follows from that.
*
* It matters that this does not read $C061 and $C062 at all. Those addresses
* exist on a ][+ -- they are paddle pushbuttons 0 and 1 -- and with nothing
* plugged into the game port they float, and read as pressed. The //e version
* of this routine therefore reports Open-Apple held on every keystroke, and
* every key dispatches as a command: pressing Q on a real ][+ quits the
* editor. Found on the hardware, because there is no other place to find it.
*--------------------------------------
GETKEY       lda   KBD
             bpl   GETKEY
             sta   KEYCHR
             lda   #$00             ; no Apple keys: no modifiers, ever
             sta   MODOA
             sta   MODCA
             sta   KBDSTRB          ; value written is irrelevant

*--- This keyboard has no lowercase, and a writer needs far more lowercase
*    than capitals, so a letter means the lowercase one. Esc before it asks
*    for the capital, which is how Apple Writer did it on this machine and
*    needs no soldering iron. The BUFFER holds real mixed case either way, so
*    what reaches the Mac is ordinary text and not a shout.
             lda   KEYCHR
             cmp   #$c1             ; 'A'
             bcc   :done
             cmp   #$db             ; past 'Z'
             bcs   :done
             ora   #$20             ; capital -> lowercase
             sta   KEYCHR
:done        lda   KEYCHR
             rts

*--------------------------------------
* The ][+ dispatch table
*
* Eighteen commands lived on Open-Apple, a key this machine does not have.
* Twelve keep their exact letter under Ctrl, so a //e user presses Ctrl where
* they would have pressed Open-Apple and is right most of the time. Three of
* the six leftovers take the three Ctrl letters still free, ranked by how
* often they are wanted mid-typing. The rest go behind Esc.
*
* All four cursor directions arrive as ordinary characters here, because the
* //e's arrow keys ARE these control codes: Ctrl-H and Ctrl-U are left and
* right, Ctrl-K and Ctrl-J are up and down. Confirmed on real hardware, since
* Virtual ][ cannot deliver $8A at all -- see docs/design.md section 9.
*--------------------------------------
KEYTBL
             dfb   $88,$00
             da    KLEFT            ; Ctrl-H, and the left arrow key
             dfb   $95,$00
             da    KRIGHT           ; Ctrl-U, and the right arrow key
             dfb   $8a,$00
             da    KUPSEL           ; Ctrl-J
             dfb   $8b,$00
             da    KDOWNSEL         ; Ctrl-K
             dfb   $8d,$00
             da    KRETURN          ; Return
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

*--- the twelve that keep their letter
             dfb   $83,$00
             da    KCOPY            ; Ctrl-C
             dfb   $86,$00
             da    KFIND            ; Ctrl-F
             dfb   $87,$00
             da    FINDNEXT         ; Ctrl-G
             dfb   $8c,$00
             da    KGOTO            ; Ctrl-L
             dfb   $8e,$00
             da    KNEW             ; Ctrl-N
             dfb   $8f,$00
             da    KLOAD            ; Ctrl-O
             dfb   $91,$00
             da    KQUIT            ; Ctrl-Q
             dfb   $92,$00
             da    REFLOW           ; Ctrl-R
             dfb   $93,$00
             da    KSAVE            ; Ctrl-S
             dfb   $96,$00
             da    KPASTE           ; Ctrl-V
             dfb   $97,$00
             da    KWORDS           ; Ctrl-W
             dfb   $98,$00
             da    KCUT             ; Ctrl-X

*--- and the three that do not
             dfb   $9a,$00
             da    KDELETE          ; Ctrl-Z, delete backwards
             dfb   $94,$00
             da    SELTOGGLE        ; Ctrl-T, start selecting
             dfb   $90,$00
             da    HELPSHOW         ; Ctrl-P, help

*--- Delete has no key on this machine at all, but an emulator will happily
*    send $FF. Bound so that testing under emulation exercises the same
*    handler; on the hardware it is simply unreachable, which is what Ctrl-Z
*    is for.
             dfb   $ff,$00
             da    KDELETE

             dfb   $9b,$00
             da    ESCPFX           ; Esc: cancel, or the prefix for the rest
             dfb   $00              ; end of table

*--------------------------------------
* ESCPFX -- Esc cancels a selection, or introduces a two-key command
*
* Esc already meant "back out of this" and still does whenever there is
* something to back out of. With no selection up it waits for a second key
* instead. The commands behind it are the deliberate, occasional ones -- the
* ones you reach for on purpose -- so a second keystroke costs little, and
* everything wanted mid-typing stays on one.
*
* Esc followed by a movement key gives the larger movement, which is one
* thing to remember rather than four.
*--------------------------------------
ESCPFX       lda   SELACT
             beq   :prefix
             jmp   SELESC           ; something to cancel: cancel it

*--- A letter after Esc is that letter capitalised. Everything else after Esc
*    is a command, which is why the commands live on symbols and control
*    codes: those can never be confused with a letter somebody wants a
*    capital of.
:prefix      jsr   GETKEY
             cmp   #$e1             ; 'a'
             bcc   :cmd
             cmp   #$fb             ; past 'z'
             bcs   :cmd
             and   #$df             ; lowercase -> capital
             sta   KEYCHR
             jmp   DISPATCH         ; no table entry for a letter: it is typed

:cmd         ldx   #$00
:scan        lda   ESCTBL,x
             beq   :none            ; unknown second key: do nothing
             cmp   KEYCHR
             beq   :go
             inx
             inx
             inx
             jmp   :scan
:go          lda   ESCTBL+1,x
             sta   JMPVEC
             lda   ESCTBL+2,x
             sta   JMPVEC+1
             jmp   (JMPVEC)
:none        rts

ESCTBL
             dfb   $93
             da    KSAVEAS          ; Esc Ctrl-S -- save as. Not Esc A: that
                                    ; is how you type a capital A.
             dfb   $bc
             da    KTOP             ; Esc < -- start of the document
             dfb   $be
             da    KEND             ; Esc > -- end of it
             dfb   $9a
             da    KDELWORD         ; Esc Ctrl-Z -- delete the word behind
             dfb   $8a
             da    KPGUP            ; Esc Ctrl-J -- a page up
             dfb   $8b
             da    KPGDN            ; Esc Ctrl-K -- a page down
             dfb   $88
             da    KWORDLSEL        ; Esc Ctrl-H -- a word left
             dfb   $95
             da    KWORDRSEL        ; Esc Ctrl-U -- a word right
             dfb   $bf
             da    HELPSHOW         ; Esc ? -- help, for the hand that keeps
                                    ; reaching for it. Ctrl-P is the single
                                    ; keystroke; this is what a //e user
                                    ; types without thinking, OA-? being the
                                    ; same key on that machine.
             dfb   $00
