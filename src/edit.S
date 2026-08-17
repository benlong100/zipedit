*--------------------------------------
* EDIT.S -- 80 column Markdown editor for the Enhanced Apple //e
*
* Entered by ProDOS 8 as a SYS file at $2000.
*
* At this stage: display layer and gap buffer. Sample text is inserted into
* the aux buffer a byte at a time and then rendered back out of it, so the
* screen is proof of a full round trip through auxiliary memory. Keyboard and
* file layers land next.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   EDIT.SYSTEM

             put   equates

*--------------------------------------
START        lda   #FCHEAT          ; cheat sheet visible at startup
             sta   FLAGS

             jsr   UNHOOKRAM        ; claim aux before anything else uses it
             lda   #$e5             ; poison, so tests can see untouched gap
             jsr   AUXFILL
             jsr   INSTSTUB         ; aux read stub into the stack page
             jsr   BUFINIT

             lda   #<SAMPLE
             sta   STRPTR
             lda   #>SAMPLE
             sta   STRPTR+1
             jsr   INSSTR           ; text now lives in auxiliary memory

             jsr   HOMECURSOR       ; rewind so RENDER starts from the top

             jsr   DISPINIT
             jsr   RENDER           ; read it back out of aux and draw it
             jsr   DRAWCHEAT
             jsr   DRAWSTATUS

:hang        jmp   :hang

*--------------------------------------
* HOMECURSOR -- walk the gap back to the start of the buffer
*
* Deliberately uses the single-byte primitive rather than a bulk move: it
* exercises GAPLEFT across the whole text, so if the shuffle across the gap
* were wrong the rendered screen would show it immediately.
*--------------------------------------
HOMECURSOR   jsr   GAPLEFT
             bcc   HOMECURSOR
             rts

*--------------------------------------
             put   auxmem
             put   buffer
             put   display

*--------------------------------------
* Sample content. CR ($8D) separates lines, $00 terminates.
*--------------------------------------
SAMPLE       asc   "# Notes from the Apple //e"
             dfb   $8d,$8d
             asc   "This editor is written in 6502 assembly and runs under ProDOS 8"
             dfb   $8d
             asc   "on an Enhanced Apple //e with 128K. The text you are reading"
             dfb   $8d
             asc   "was inserted into auxiliary memory one byte at a time, then"
             dfb   $8d
             asc   "read back out of it to draw this screen."
             dfb   $8d,$8d
             asc   "## How it writes"
             dfb   $8d,$8d
             asc   "- lines hard wrap near column 76, so one line is one screen row"
             dfb   $8d
             asc   "- **bold** with Ctrl-B, _italic_ with Ctrl-I"
             dfb   $8d
             asc   "- `code` spans and [links](url) are typed literally"
             dfb   $8d
             asc   "- Open-Apple-? toggles the cheat sheet below"
             dfb   $8d,$8d
             asc   "> Drafted here, then carried back to the Mac as plain UTF-8."
             dfb   $8d
             dfb   $00
