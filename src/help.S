*--------------------------------------
* HELP.S -- the keyboard command screen (OA-? , alias OA-H)
*
* NOT Ctrl-H: the //e keyboard encoder maps Ctrl-H and the left arrow to the
* same $88, exactly as it does Tab and Ctrl-I, so binding help there would cost
* the cursor-left key. Verified on the machine and asserted in the suite.
*
* OA-? opens this. The one-line cheat sheet moved to OA-/, the same physical
* key unshifted, which keeps the two mnemonically paired.
*
* The box is 22 rows so it leaves the cheat sheet and status line showing
* underneath. Each row blanks the full screen width and paints the box in the
* middle, so dismissing it needs nothing more than the full redraw the main
* loop already performs whenever a handler has not opted into the one-row path.
*--------------------------------------
HELPCOL      equ   8
HELPN        equ   22

*--------------------------------------
* HELPSHOW -- paint the box, wait for any key
*--------------------------------------
HELPSHOW     lda   #$00
             sta   HELPI
:loop        lda   HELPI
             asl
             tay
             lda   HELPTBL,y
             sta   STRPTR
             lda   HELPTBL+1,y
             sta   STRPTR+1
             jsr   CLRBUF
             ldx   #HELPCOL
             jsr   BUFSTR
             lda   HELPI
             jsr   DRAWLINE
             inc   HELPI
             lda   HELPI
             cmp   #HELPN
             bne   :loop
             jsr   GETKEY
             rts

HELPTBL
             da    HL00
             da    HL01
             da    HL02
             da    HL03
             da    HL04
             da    HL05
             da    HL06
             da    HL07
             da    HL08
             da    HL09
             da    HL10
             da    HL11
             da    HL12
             da    HL13
             da    HL14
             da    HL15
             da    HL16
             da    HL17
             da    HL18
             da    HL19
             da    HL20
             da    HL21

HL00         asc   "+--------------------------------------------------------------+"
             dfb   $00
HL01         asc   "|   MARKDOWN EDITOR FOR THE APPLE //e  --  KEYBOARD COMMANDS   |"
             dfb   $00
HL02         asc   "+--------------------------------------------------------------+"
             dfb   $00
HL03         asc   "|  MOVING                      EDITING                         |"
             dfb   $00
HL04         asc   "|   arrows      char / line    Delete    delete left           |"
             dfb   $00
HL05         asc   "|   OA-arrows   word / page    Ctrl-D    delete right          |"
             dfb   $00
HL06         asc   "|   Ctrl-A      line start     Ctrl-Y    delete to line end    |"
             dfb   $00
HL07         asc   "|   Ctrl-E      line end       Tab       indent two spaces     |"
             dfb   $00
HL08         asc   "|   OA-<  OA->  doc start/end  OA-R      reflow paragraph      |"
             dfb   $00
HL09         asc   "|  MARKDOWN                    FILES                           |"
             dfb   $00
HL10         asc   "|   Ctrl-B      **bold** word  OA-O      open                  |"
             dfb   $00
HL11         asc   "|   Ctrl-I      _italic_ word  OA-S      save                  |"
             dfb   $00
HL12         asc   "|                              OA-Q      quit to ProDOS        |"
             dfb   $00
HL13         asc   "|  SEARCH                      CLIPBOARD                       |"
             dfb   $00
HL14         asc   "|   OA-F        find           OA-C      copy line             |"
             dfb   $00
HL15         asc   "|   OA-G        find again     OA-X      cut line              |"
             dfb   $00
HL16         asc   "|   OA-L        go to line     OA-V      paste                 |"
             dfb   $00
HL17         asc   "|  SCREEN                                                      |"
             dfb   $00
HL18         asc   "|   OA-/        cheat sheet    OA-?      this help             |"
             dfb   $00
HL19         asc   "+--------------------------------------------------------------+"
             dfb   $00
HL20         asc   "|   press any key to return                                    |"
             dfb   $00
HL21         asc   "+--------------------------------------------------------------+"
             dfb   $00

             dum   $1420
HELPI        ds    1
             dend
