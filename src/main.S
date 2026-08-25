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
START        lda   #$00             ; nothing remembered about the viewport yet
             sta   TOPOK
             jsr   GEOMINIT         ; the layout's columns first of all: it
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
             sta   FLOWOWED         ; no reflow put off yet
             sta   KBHEAD           ; and nothing caught in the ring. These
             sta   KBTAIL           ; live in a dum block, so a relaunch would
                                    ; otherwise start with garbage indices

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
* A full redraw per keystroke is more work than it needs to be, and what it
* costs is the rescan from the buffer start: RENDER counts its way down from
* byte zero every time, so the deeper in the document you are, the longer
* every redraw takes. Timed at 1MHz with the arrow keys, which force a full
* redraw on every press and so measure RENDER and nothing else:
*
*     line 1    218ms per arrow
*     line 64   398ms
*     line 112  553ms
*
* -- a straight line in the bytes above the viewport. That is what the line
* index is for. Measure this with the ARROW keys: an earlier attempt used
* typing, where most keystrokes take the one-row path and never reach RENDER
* at all, and averaged the effect away into "depth does not matter".
*--------------------------------------
MAINLOOP     jsr   SCROLLFIX
             jsr   REDRAW

*--- remember what a one-row redraw is allowed to assume
:keys        lda   #$00
             sta   FASTDRAW
             sta   PARTIAL
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

*--- The tidy-up WRAPCHECK put off, now that the writer has paused -- or is
*    about to do something other than type.
*
*    The second half of that matters. Deferring only while the NEXT key is
*    printable keeps the cursor inside the paragraph that needs tidying, and
*    this mirrors it: a command or an arrow gets the tidy done FIRST, before it
*    can move the cursor somewhere else and strand the mess. Without it, an
*    arrow pressed at the end of a burst could carry the cursor into another
*    paragraph and leave this one ragged until something else reflowed it.
*
*    Forward from the cursor, because forward is where the mess always is:
*    DOWRAP breaks out at the margin, so every break put off is further along
*    the line than the cursor and the words pushed off land on the lines below.
*    The rule above guarantees the cursor is still where the typing left it.
*
*    Which of the two walks depends on HOW MANY breaks were put off. RTFWD
*    stops as soon as a break lands back where one already was, which proves
*    the rest of the paragraph is right -- but only if it WAS right to begin
*    with. One deferred break leaves everything below it untouched, so the
*    proof holds and the cheap walk is correct. Two or more and it does not:
*    the early stop fires on the first break that happens to land right and
*    strands the rest, which showed up as "hotel", "india" and "juliet" left
*    sitting on lines of their own.
*
*    Measured at 1MHz, worst case -- a writer who pauses after every word, so
*    the tidy runs as often as it would have anyway: 83ms a character for the
*    cheap walk, matching no deferral at all, against 103ms if the thorough
*    walk is used every time. RTFLOW, tried first, was 147ms.
             lda   FLOWOWED
             beq   :noflow
             jsr   KBNEXT           ; the ring counts as waiting, not just
             bcs   :doflow          ; the latch. Nothing waiting: they paused
             cmp   #TEXTLO
             bcc   :doflow          ; a control key or an arrow is next
             cmp   #$ff             ; Delete
             bcs   :doflow
             bcc   :noflow          ; printable: the word is not finished
:doflow      ldx   FLOWOWED
             lda   #$00
             sta   FLOWOWED
             cpx   #$02
             bcs   :flowall
             jsr   RTFAST           ; one break: the early stop is still sound
             jmp   :noflow
:flowall     jsr   RTFASTALL        ; both clear FASTDRAW, so a full redraw
:noflow

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

*--- RENDERROW stages the row through LINEBUF, which is exactly one screen
*    wide, copying CCOL bytes into it from before the gap and GSCRW-CCOL from
*    after. Both of those run off the end of it once the cursor sits further
*    along the line than the screen is wide, and the second one runs off by
*    however far GSCRW-CCOL underflowed -- straight through page 2 and into
*    page 3. Nothing could put the cursor there while every insert was
*    wrap-checked; PASTE can. Over-long lines take the full redraw, which
*    clips at the margin instead of overrunning.
             lda   CCOL+1
             bne   :full
             lda   CCOL
             cmp   GSCRW
             bcs   :full
             jsr   RENDERROW
             jmp   :keys

*--- A wrap rearranges the text below the cursor and cannot touch a line above
*    it, so the rows above the one the cursor started on are already right and
*    RENDER can be told to count them rather than draw them. Everything else --
*    a scroll, a selection, a return, a load -- redraws the lot.
*--- A wrap rearranges the text below the cursor and cannot touch a line above
*    it, so the rows above the one the cursor started on are already right and
*    RENDER can be told to count them rather than draw them. Everything else --
*    a scroll, a selection, a return, a load -- redraws the lot.
:full        lda   SELACT
             ora   OLDSEL
             bne   :all
             lda   PARTIAL
             beq   :all
             lda   SCROLLTOP        ; a scroll moves every row: no shortcut
             cmp   OLDTOP
             bne   :all
             lda   SCROLLTOP+1
             cmp   OLDTOP+1
             bne   :all

             lda   OLDLINE          ; which row was that?
             sec
             sbc   SCROLLTOP
             tax
             lda   OLDLINE+1
             sbc   SCROLLTOP+1
             bne   :all             ; not on screen at all; draw everything
             cpx   MAXROW
             bcs   :all
             stx   RSKIP

:all         jsr   REDRAW
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
*    saying so is cheaper than having walked there correctly. This used to be
*    load-bearing rather than an optimisation: CCOL was one byte, GAPLEFT
*    decrements it per character, and walking back over a line longer than 255
*    wrapped the count around. A file whose lines are whole unwrapped
*    paragraphs arrived with CCOL already past the margin and WRAPALL broke the
*    line at its FIRST character: "**History Duel**" opened as "*" and then
*    "*History Duel**" on the line below.
*
*    The comment here used to add that such a line "cannot happen while
*    editing, since nothing survives longer than the wrap margin". That was
*    wrong: PASTE inserts a whole clipboard between wrap checks and every
*    character of it goes in unwrapped. CCOL is two bytes now, so the count no
*    longer wraps either way, and this remains simply the cheap answer.
             lda   #$00
             sta   CCOL
             sta   CCOL+1
             rts

*--- $1428 is display.S's LASTCOLH; $1429-$142f is otherwise free.
             dum   $1429
FLOWOWED     ds    1                ; a reflow was put off and is still owed
             dend

*--------------------------------------
