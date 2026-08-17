*--------------------------------------
* EDIT.S -- 80 column Markdown editor for the Enhanced Apple //e
*
* Entered by ProDOS 8 as a SYS file at $2000.
*
* At this stage: display, gap buffer and keyboard. Sample text is inserted into
* the aux buffer a byte at a time and rendered back out of it, then the main
* loop takes keys and edits it. The file layer lands next, which is what turns
* this from an editor you can type into to one you can keep work in.
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

             jsr   SETMAXROW
             jsr   DISPINIT
             jsr   DRAWSTATUS

*--------------------------------------
* Main loop. Redraw, wait for a key, act on it, repeat.
*
* A full redraw per keystroke is more work than it needs to be -- RENDER
* rescans the buffer from the start every time. At this size it is well under
* a frame and invisible; the line index is the fix when it stops being.
*--------------------------------------
MAINLOOP     jsr   REDRAW
             jsr   GETKEY
             jsr   DISPATCH
             jmp   MAINLOOP

*--------------------------------------
* REDRAW -- text area, cursor, and whichever chrome is showing
*--------------------------------------
REDRAW       jsr   RENDER
             jsr   BLANKTAIL
             jsr   SHOWCURSOR
             lda   FLAGS
             and   #FCHEAT
             beq   :nocheat
             jmp   DRAWCHEAT
:nocheat     jmp   CLRCHEAT

*--------------------------------------
* BLANKTAIL -- clear text rows below the end of the buffer, so deleting a line
*              does not leave its ghost on screen
*--------------------------------------
BLANKTAIL    lda   CURROW
             cmp   MAXROW
             bcs   :done
             pha
             jsr   CLRBUF
             pla
:loop        pha
             jsr   DRAWLINE
             pla
             clc
             adc   #$01
             cmp   MAXROW
             bcc   :loop
:done        rts

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
             put   keyboard
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
