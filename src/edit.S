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
             dsk   ZIPEDIT.SYSTEM

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

*--- The editor opens on an empty document. It used to plant a sample here,
*    which was useful while the buffer was being built and is just something to
*    delete now. The sample lives on the disk as SAMPLE.MD instead, where it can
*    be opened deliberately -- and where the test suite gets it from.
             jsr   HOMECURSOR
             lda   #$00             ; an empty document is not unsaved work
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
