*--------------------------------------
* KEYPROBE.S -- what code does this keyboard actually send?
*
* Built for one question: on a real Apple ][+, does Ctrl-J produce $8A, the
* code the //e's down arrow sends and the code ZipEdit dispatches on? Virtual
* ][ cannot answer it -- something between AppleScript and the emulator turns
* a line feed into a carriage return, so Ctrl-J arrives as $8D there however
* it is sent. A ][+ has no down arrow key, so if Ctrl-J does not carry $8A
* there is no way to move the cursor down and the keymap needs rethinking.
*
* Reads $C000 and clears the strobe at $C010, exactly as the editor does, so
* no firmware gets a chance to filter or steal anything. Applesoft would have
* stolen Ctrl-C and paused on Ctrl-S; this does neither.
*
* Output goes through the monitor's COUT at $FDED, which every Apple II has
* and which handles 40 columns and scrolling for us. Plain 6502, no //e
* anything: this has to run on the oldest machine in the family.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   KEYPROBE.SYSTEM

KBD          equ   $c000
KBDSTRB      equ   $c010
COUT         equ   $fded
PSTR         equ   $06              ; zero page: (PSTR),y needs it there
HOME         equ   $fc58

START        jsr   HOME
             lda   #<BANNER
             ldy   #>BANNER
             jsr   PUTS

*--- one key at a time, forever. RESET is the way out.
:loop        lda   KBD
             bpl   :loop
             sta   KBDSTRB
             pha                    ; the byte, for the low nibble
             lsr
             lsr
             lsr
             lsr
             jsr   HEXDIG
             pla
             and   #$0f
             jsr   HEXDIG
             lda   #$a0             ; a space between codes
             jsr   COUT
             jmp   :loop

*--------------------------------------
* HEXDIG -- print the low nibble of A as a hex digit
*--------------------------------------
HEXDIG       and   #$0f
             cmp   #$0a
             bcc   :digit
             adc   #$06             ; carry is set, so this adds 7: A-F
:digit       adc   #$b0             ; and high ASCII, which is what COUT wants
             jmp   COUT

*--------------------------------------
* PUTS -- print the null-terminated string at A,Y
*--------------------------------------
PUTS         sta   PSTR
             sty   PSTR+1
             ldy   #$00
:loop        lda   (PSTR),y
             beq   :done
             jsr   COUT             ; the monitor's COUT preserves Y
             iny
             bne   :loop
             inc   PSTR+1           ; Y alone caps a string at 256 bytes, and
             bne   :loop            ; this banner is longer than that
:done        rts


BANNER       asc   "ZIPEDIT KEYBOARD PROBE"
             dfb   $8d,$8d
             asc   "EACH KEY PRINTS ITS CODE IN HEX,"
             dfb   $8d
             asc   "READ AS ZIPEDIT READS IT."
             dfb   $8d,$8d
             asc   "THE ONE THAT MATTERS:"
             dfb   $8d
             asc   "  CTRL-J  SHOULD BE 8A"
             dfb   $8d
             asc   "  IF IT IS 8D IT SENDS RETURN,"
             dfb   $8d
             asc   "  SO IT CANNOT BE DOWN ARROW."
             dfb   $8d,$8d
             asc   "ALSO:"
             dfb   $8d
             asc   "  CTRL-K 8B    CTRL-H 88"
             dfb   $8d
             asc   "  CTRL-U 95    CTRL-C 83"
             dfb   $8d
             asc   "  CTRL-S 93"
             dfb   $8d
             asc   "  CTRL-SPACE VS SPACE: SAME?"
             dfb   $8d,$8d
             asc   "RESET STOPS IT."
             dfb   $8d,$8d
             dfb   $00
