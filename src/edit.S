*--------------------------------------
* EDIT.S -- ZipEdit for the Enhanced Apple //e
*
* The 80-column build: auxiliary-memory text buffer, MouseText where the
* machine has it, and the Open-Apple command set. See edit2p.S for the
* Apple ][+, which is the same editor against a 40-column screen.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   ZIPEDIT.SYSTEM

             put   equates
             put   main             ; START first: ProDOS enters at $2000
             put   screen80         ; the machine-specific half of the display
             put   auxbuf
             put   keysiie
             put   keyboard
             put   file
             put   wrap
             put   scroll
             put   select
             put   edit_ops
             put   help
             put   helpdata80
             put   splash
             put   buffer
             put   display
             put   machine
             put   geom

*--------------------------------------
* Sample content. CR ($8D) separates lines, $00 terminates.
*--------------------------------------
