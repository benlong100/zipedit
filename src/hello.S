*--------------------------------------
* HELLO.S -- toolchain spike
*
* Proves: Merlin32 -> AppleCommander -> ProDOS 8 -> Virtual ][
* Runs as a ProDOS SYS file (loaded at $2000, entered at $2000).
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   ZIPEDIT.SYSTEM

COUT         equ   $fded
HOME         equ   $fc58

             jsr   HOME
             ldx   #$00
:loop        lda   MSG,x
             beq   :hang
             jsr   COUT
             inx
             bne   :loop
:hang        jmp   :hang

MSG          asc   "HELLO FROM MERLIN32 ON PRODOS 8"
             dfb   $8d,$00
