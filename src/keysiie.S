*--------------------------------------
* KEYSIIE.S -- reading the keyboard on a //e
*
* The //e wires its two Apple keys in parallel with paddle pushbuttons 0 and
* 1, so they read as state at $C061 and $C062 rather than arriving in the
* character code. That is what makes an Open-Apple command set possible here
* and impossible on a ][+, where those same addresses are the paddle buttons
* and nothing else. See keys2p.S.
*--------------------------------------
*--- KBMODS -- what KBPOLL stores alongside a key it catches. Open-Apple is a
*    soft switch, not part of the character, so it is only true at the instant
*    the key arrives and has to be sampled then.
KBMODS       lda   OPNAPPLE
             and   #$80
             rts

GETKEY       jsr   KBDEQ            ; keys caught while the editor was busy
             bcc   :fold            ; come first, in the order they were struck
:wait        lda   KBD
             bpl   :wait
             sta   KEYCHR
             lda   OPNAPPLE
             and   #$80
             sta   MODOA
             lda   CLSAPPLE
             and   #$80
             sta   MODCA
             sta   KBDSTRB          ; value written is irrelevant

*--- fold Open-Apple letters to uppercase so OA-q and OA-Q both dispatch
:fold        lda   MODOA
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
             dfb   $a7,$80
             da    KBACKTICK        ; OA-' -- a backtick, which this keyboard
                                    ; cannot otherwise produce at all
             dfb   $00              ; end of table

*--------------------------------------
* SPLHELP -- the hint on the splash screen. It names a key that has to exist
* on THIS machine, so it belongs with the keymap and not in splash.S, which
* every build shares. edit40.S is 40 columns but still a //e, and takes this.
*--------------------------------------
SPLHELP      dfb   $41,$ad,$bf      ; Open Apple glyph, "-", "?"
             asc   " to get help"
             dfb   $00
