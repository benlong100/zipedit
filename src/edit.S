*--------------------------------------
* EDIT.S -- 80 column Markdown editor for the Enhanced Apple //e
*
* Entered by ProDOS 8 as a SYS file at $2000.
*
* Display, gap buffer, keyboard, ProDOS file I/O and hard wrap are all in.
* Sample text is inserted into the aux buffer at startup, the main loop edits
* it with wrapping at column 76, OA-R reflows a paragraph, and OA-S / OA-O
* save and load real ProDOS TXT files. The viewport scrolls to follow the
* cursor, so documents longer than the screen are reachable.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   EDIT.SYSTEM

             put   equates

*--------------------------------------
START        lda   #$00             ; cheat sheet hidden by default; OA-/ shows it
             sta   FLAGS
             lda   #$00
             sta   SCROLLTOP
             sta   SCROLLTOP+1

             jsr   UNHOOKRAM        ; claim aux before anything else uses it
             lda   #$e5             ; poison, so tests can see untouched gap
             jsr   AUXFILL
             jsr   INSTSTUB         ; aux read stub into the stack page
             jsr   INITFILE         ; ProDOS parameter blocks into RAM
             jsr   SELINIT
             lda   #$00
             sta   GOALCOL
             sta   VERTMOVE
             sta   WASVERT
             jsr   BUFINIT

             lda   #<SAMPLE
             sta   STRPTR
             lda   #>SAMPLE
             sta   STRPTR+1
             jsr   INSSTR           ; text now lives in auxiliary memory

             jsr   HOMECURSOR       ; rewind so RENDER starts from the top
             lda   #$00             ; the sample is not the user's unsaved work
             sta   MODFLAG

             jsr   SETMAXROW
             lda   #$00
             sta   MSGSHOWN
             jsr   DISPINIT
             jsr   SPLASH           ; dismissed by any key, before the document
             jsr   DRAWSTATUS
             jsr   STATUPD

*--------------------------------------
* Main loop. Redraw, wait for a key, act on it, repeat.
*
* A full redraw per keystroke is more work than it needs to be -- RENDER
* rescans the buffer from the start every time. At this size it is well under
* a frame and invisible; the line index is the fix when it stops being.
*--------------------------------------
MAINLOOP     jsr   SCROLLFIX
             jsr   REDRAW

*--- remember what a one-row redraw is allowed to assume
:keys        lda   #$00
             sta   FASTDRAW
             lda   CURLNO
             sta   OLDLINE
             lda   CURLNO+1
             sta   OLDLINE+1
             lda   SCROLLTOP
             sta   OLDTOP
             lda   SCROLLTOP+1
             sta   OLDTOP+1
             lda   SELACT
             sta   OLDSEL
             lda   VERTMOVE         ; did the last keystroke move vertically?
             sta   WASVERT
             lda   #$00
             sta   VERTMOVE

             jsr   GETKEY

*--- a keystroke retires whatever message was owning the status line
             lda   MSGSHOWN
             beq   :go
             lda   #$00
             sta   MSGSHOWN
             jsr   DRAWSTATUS

:go          jsr   DISPATCH
             jsr   SCROLLFIX
             jsr   STATUPD

*--- one row is enough only if the handler opted in AND nothing structural
*    moved. Anything else -- a wrap, a newline, a scroll, a file load -- falls
*    through to the full redraw.
             lda   SELACT           ; a selection spans rows: repaint the lot
             ora   OLDSEL
             bne   :full
             lda   FASTDRAW
             beq   :full
             lda   CURLNO
             cmp   OLDLINE
             bne   :full
             lda   CURLNO+1
             cmp   OLDLINE+1
             bne   :full
             lda   SCROLLTOP
             cmp   OLDTOP
             bne   :full
             lda   SCROLLTOP+1
             cmp   OLDTOP+1
             bne   :full
             jsr   RENDERROW
             jmp   :keys

:full        jsr   REDRAW
             jmp   :keys

*--------------------------------------
* REDRAW -- text area, cursor, and whichever chrome is showing
*--------------------------------------
REDRAW       jsr   RENDER
             jsr   BLANKTAIL
             jsr   SHOWCURSOR
             lda   FLAGS
             and   #FCHEAT
             beq   :done            ; hidden: row 22 is text, leave it alone
             jmp   DRAWCHEAT
:done        rts

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
             put   file
             put   wrap
             put   scroll
             put   select
             put   edit_ops
             put   help
             put   splash
             put   buffer
             put   display

*--------------------------------------
* Sample content. CR ($8D) separates lines, $00 terminates.
*--------------------------------------
SAMPLE       asc   "# Notes from the Apple //e"
             dfb   $8d,$8d
             asc   "This editor is written in 6502 assembly and runs under ProDOS 8"
             dfb   SOFTCR           ; one paragraph across four screen rows, so
             asc   "on an Enhanced Apple //e with 128K. The text you are reading"
             dfb   SOFTCR           ; these three breaks are the wrapper's and
             asc   "was inserted into auxiliary memory one byte at a time, then"
             dfb   SOFTCR           ; will not be written to the file
             asc   "read back out of it to draw this screen."
             dfb   $8d,$8d
             asc   "## How it writes"
             dfb   $8d,$8d
             asc   "- lines hard wrap near column 76, so one line is one screen row"
             dfb   $8d
             asc   "- **bold** with Ctrl-B, *italic* with Ctrl-I"
             dfb   $8d
             asc   "- `code` spans and [links](url) are typed literally"
             dfb   $8d
             asc   "- Open-Apple-? toggles the cheat sheet below"
             dfb   $8d,$8d
             asc   "> Drafted here, then carried back to the Mac as plain UTF-8."
             dfb   $8d,$8d
             asc   "Paragraph 01 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 02 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 03 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 04 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 05 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 06 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 07 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 08 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 09 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 10 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 11 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 12 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 13 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 14 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 15 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 16 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 17 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "Paragraph 18 of the draft, kept short for the scroll test."
             dfb   $8d
             asc   "THE END"
             dfb   $8d
             dfb   $00
