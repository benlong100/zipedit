*--------------------------------------
* AUXBUF.S -- the text buffer in the //e's auxiliary bank
*
* The memory driver for a machine that has 64K it is not otherwise using.
* Supplies the six routines buffer.S calls and the bounds it works between;
* mainbuf.S supplies the same six for a machine with no auxiliary bank.
*
* Reading and writing aux are NOT symmetric:
*
*   writes  RAMWRT redirects stores to $0200-$BFFF into aux while instruction
*           fetches (which follow RAMRD) stay in main. An ordinary store loop
*           works inline.
*
*   reads   RAMRD redirects loads AND instruction fetches. Code at $2000 would
*           fetch its own next instruction out of the text buffer and die. So
*           reads go through AUXRD, a four-instruction stub copied into the
*           stack page, which RAMRD does not control.
*
* AUXRD assumes interrupts are not in play: an IRQ taken between RAMRD on and
* RAMRD off would run its handler out of aux. Nothing in this configuration
* generates interrupts under ProDOS 8 -- revisit if that changes.
*
* On a 128K machine ProDOS 8 installs /RAM, a RAM disk backed by exactly the
* auxiliary memory we want. Left alone, the two silently corrupt each other,
* so UNHOOKRAM disconnects it before anything touches aux.
*--------------------------------------

*--- where the buffer lives, and where the read stubs get copied to. $0100 is
*    the last address the stack would ever reach.
BUFLO        equ   $08              ; the buffer runs aux $0800...
BUFHI        equ   $c0              ; ...to just below aux $C000
AUXRD        equ   $0100            ; one byte, read through a stack-page stub
AUXBLK       equ   $0110            ; a block, with one bank switch for the lot

*--------------------------------------
* INSTSTUB -- copy the aux read stub into the stack page
*--------------------------------------
INSTSTUB     ldx   #STUBEND-STUBSRC-1
:loop        lda   STUBSRC,x
             sta   AUXRD,x
             dex
             bpl   :loop
             ldx   #BLKEND-BLKSRC-1
:loop2       lda   BLKSRC,x
             sta   AUXBLK,x
             dex
             bpl   :loop2
             rts

* Position independent: zero page indirect and absolute I/O only.
* On entry AUXPTR -> aux address, Y = index. On exit A = byte, flags set from
* it (STA does not disturb them).
STUBSRC      sta   RAMRDON
             lda   (AUXPTR),y
             sta   RAMRDOFF
             rts
STUBEND

* Block copy aux -> main with a single bank switch, rather than one per byte.
* Reads follow RAMRD and land in aux; writes follow RAMWRT, which stays off, so
* they land in main. Zero page follows ALTZP and is untouched, so both pointers
* stay readable. Entry: AUXPTR source, DSTPTR destination, BLKLEN count (1-255),
* Y = 0. About 15 cycles a byte against roughly 49 through AUXRD.
BLKSRC       sta   RAMRDON
:loop        lda   (AUXPTR),y
             sta   (DSTPTR),y
             iny
             cpy   BLKLEN
             bne   :loop
             sta   RAMRDOFF
             rts
BLKEND

*--------------------------------------
* PUTAUX -- store the byte in A at aux address AUXPTR,Y
*--------------------------------------
*    No need to save the byte across the switch: STA does not touch the
*    accumulator, and a soft switch cares only that its address was written,
*    not what was written to it. This used to stash A in X and take it back,
*    which cost two bytes, four cycles a write, and X.
PUTAUX       sta   RAMWRTON         ; value in A is irrelevant to the switch
             sta   (AUXPTR),y
             sta   RAMWRTOFF
             rts

*--------------------------------------
* UNHOOKRAM -- disconnect /RAM so auxiliary memory is ours
*--------------------------------------
UNHOOKRAM
*--- point /RAM's driver slot at the "no device connected" routine.
*    Slot 0 drive 1 can never be a real device, so its entry is a reliable
*    source for that address without hardcoding a ProDOS-version-specific one.
             lda   DEVTBL
             sta   RAMDRV
             lda   DEVTBL+1
             sta   RAMDRV+1

*--- drop any slot 3 drive 2 entry from DEVLST, compacting in place
             lda   DEVCNT
             sta   TMPA             ; loop bound (count-1)
             ldx   #$00             ; read index
             ldy   #$00             ; write index
:scan        lda   DEVLST,x
             pha
             and   #$f0             ; low nibble is device ID, not slot/drive
             cmp   #$b0             ; slot 3, drive 2
             beq   :drop
             pla
             sta   DEVLST,y
             iny
             jmp   :next
:drop        pla
:next        cpx   TMPA
             beq   :done
             inx
             jmp   :scan

:done        dey                    ; DEVCNT is count-1
             sty   DEVCNT
             rts

*--------------------------------------
* AUXFILL -- fill the whole aux text buffer with the byte in A
*
* RAMWRT redirects writes to $0200-$BFFF into aux while instruction fetches,
* zero page and the stack all stay in main -- those follow RAMRD and ALTZP,
* which we leave alone. So a perfectly ordinary store loop lands in aux.
*
* $0400-$07FF is skipped implicitly: the buffer starts at $0800, so we never
* collide with the 80STORE-controlled screen window.
*--------------------------------------
AUXFILL      sta   TMPA
             lda   #$00
             sta   AUXPTR
             lda   #BUFLO
             sta   AUXPTR+1

             sta   RAMWRTON
:page        ldy   #$00
             lda   TMPA
:byte        sta   (AUXPTR),y
             iny
             bne   :byte
             inc   AUXPTR+1
             lda   AUXPTR+1
             cmp   #BUFHI
             bne   :page
             sta   RAMWRTOFF
             rts
