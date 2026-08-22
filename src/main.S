*--------------------------------------
* MAIN.S -- START and the main loop, shared by every machine
*
* Split out of edit.S so that a second top-level can build the same editor
* against a different screen and keyboard. What varies between machines is
* which files get PUT, not what the editor does once it is running: the
* geometry comes from a record the screen driver names, and the screen driver
* supplies DISPINIT, CLRSCRN and DRAWLINE.
*
* This must be PUT first, because ProDOS enters at $2000 and START has to be
* the first thing there.
*--------------------------------------

*--------------------------------------
START        jsr   GEOMINIT         ; the layout's columns first of all: it
                                    ; depends on nothing, and everything that
                                    ; draws depends on it
             lda   #$00             ; cheat sheet hidden by default; OA-/ shows it
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

*--- Everything here lives in a dum block or on zero page, so none of it is
*    part of the loaded file and none of it starts at a known value. A cold
*    boot leaves this memory zero and the editor looked correct by luck. Quit
*    to the ProDOS selector and relaunch, and it is whatever that left behind:
*    FNAME's length byte comes back non-zero, so the editor believes the
*    document is already named, prints the garbage as its filename, and OA-S
*    saves to it and fails. KNEW does this for a new document already -- the
*    launch path simply never did the same.
             lda   #$00
             sta   FNAME            ; length 0: no name yet, so OA-S asks
             sta   PLEN             ; nothing collected by a prompt yet
             sta   FINDLEN          ; no search pattern, so OA-G has nothing
             sta   CLIPLEN          ; and nothing on the clipboard to paste
             sta   CLIPLEN+1
             sta   CLIPLINE

             jsr   DETECTMT         ; MouseText, or solid blocks instead
             jsr   PLAINIFY         ; which the help screen has to know before
                                    ; it is ever drawn
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

*--- The cursor is at the first byte of the buffer, so the column is zero and
*    saying so is cheaper than having walked there correctly. CCOL is one byte
*    and GAPLEFT decrements it per character, so walking back over a line
*    longer than 255 wraps the count around -- which cannot happen while
*    editing, since nothing survives longer than the wrap margin, but happens
*    on every LOAD before WRAPALL has run. A file whose lines are whole
*    unwrapped paragraphs then arrived with CCOL already past the margin, and
*    WRAPALL broke the line at its FIRST character: "**History Duel**" opened
*    as "*" and then "*History Duel**" on the line below.
             lda   #$00
             sta   CCOL
             rts

*--------------------------------------
