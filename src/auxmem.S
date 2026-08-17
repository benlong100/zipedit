*--------------------------------------
* AUXMEM.S -- claim auxiliary memory for the text buffer
*
* On a 128K machine ProDOS 8 installs /RAM, a RAM disk backed by exactly the
* auxiliary memory ($0800-$BFFF) we want for the gap buffer. Left alone, the
* two silently corrupt each other. So we disconnect /RAM before touching aux.
*
* The layout below was read out of a live ProDOS 2.4.3 global page rather than
* recalled:
*
*   $BF26/$BF27  driver address for slot 3 drive 2   = $FF00  (/RAM)
*   every unused slot                                = $DEA3  ("no device")
*   $BF31 DEVCNT = $02                               (i.e. three devices)
*   $BF32 DEVLST = $E0 $60 $BF                       ($BF is /RAM)
*
* Note DEVCNT is the device count MINUS ONE, and DEVLST entries carry ID bits
* in the low nibble ($BF, not $B0), so slot/drive matching must mask to $F0.
*--------------------------------------

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
             lda   #AUXLO
             sta   AUXPTR+1

             sta   RAMWRTON
:page        ldy   #$00
             lda   TMPA
:byte        sta   (AUXPTR),y
             iny
             bne   :byte
             inc   AUXPTR+1
             lda   AUXPTR+1
             cmp   #AUXHI
             bne   :page
             sta   RAMWRTOFF
             rts
