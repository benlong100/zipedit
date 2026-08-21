*--------------------------------------
* MAINBUF.S -- the text buffer in main memory
*
* The memory driver for a machine with no auxiliary bank: an Apple ][+, or a
* //e without the extended card. Supplies the same six routines auxbuf.S does,
* so buffer.S and its twenty-odd callers do not change a line between them.
*
* This is the simple one. There is no bank to switch, so a read is a read, a
* write is a write, and the stack-page stub the //e needs -- because RAMRD
* redirects instruction fetches as well as loads, and code at $2000 would
* fetch its next instruction out of the text buffer -- is not needed at all.
* INSTSTUB and UNHOOKRAM survive as entry points that do nothing, rather than
* as conditionals at every call site.
*
* The cost is capacity. Aux gives 46K between $0800 and $C000 and asks nothing
* in return, because nothing else wants it. Main memory has to be shared with
* the editor itself, its file buffers and ProDOS, which leaves roughly 20K --
* about three thousand words. That is the whole of the trade for running on a
* machine that predates auxiliary memory by four years.
*
*   $0800-$11E9   file buffers, the clipboard, the find pattern
*   $1400-$14xx   scratch
*   $2000-CODEEND the editor
*   BUFLO-BUFHI   the text buffer: whatever is left below ProDOS
*
* BUFLO is the page after the code rather than a number chosen by hand, so
* the buffer starts wherever the editor happens to end and does not have to
* be re-tuned every time the code grows. CODEEND is defined by the top-level
* file, after everything has been PUT.
*--------------------------------------

BUFLO        equ   >CODEEND         ; CODEEND is padded to a page boundary
BUFHI        equ   $96              ; below ProDOS 8's own buffers

*--------------------------------------
* INSTSTUB -- nothing to install: no bank, no stub
*--------------------------------------
INSTSTUB     rts

*--------------------------------------
* UNHOOKRAM -- nothing to disconnect
*
* ProDOS 8 only installs /RAM where there is auxiliary memory to put it in.
* On a machine without any there is nothing to collide with, and on a machine
* with some this driver is not using it.
*--------------------------------------
UNHOOKRAM    rts

*--------------------------------------
* AUXRD -- the byte at AUXPTR,Y
*
* Same contract as the //e's stub: A holds the byte and the flags are set
* from it, which several callers rely on.
*--------------------------------------
AUXRD        lda   (AUXPTR),y
             rts

*--------------------------------------
* PUTAUX -- store the byte in A at AUXPTR,Y
*--------------------------------------
PUTAUX       sta   (AUXPTR),y
             rts

*--------------------------------------
* AUXBLK -- copy BLKLEN bytes from AUXPTR to DSTPTR. Y = 0 on entry.
*
* Both ends are in main memory here, so this is an ordinary copy. It stays a
* separate routine because the //e's version saves a bank switch per byte and
* the callers are written around that.
*--------------------------------------
AUXBLK
:loop        lda   (AUXPTR),y
             sta   (DSTPTR),y
             iny
             cpy   BLKLEN
             bne   :loop
             rts

*--------------------------------------
* AUXFILL -- fill the whole text buffer with the byte in A
*--------------------------------------
AUXFILL      sta   TMPA
             lda   #$00
             sta   AUXPTR
             lda   #BUFLO
             sta   AUXPTR+1

:page        ldy   #$00
             lda   TMPA
:byte        sta   (AUXPTR),y
             iny
             bne   :byte
             inc   AUXPTR+1
             lda   AUXPTR+1
             cmp   #BUFHI
             bne   :page
             rts
