*--------------------------------------
* EDIT40.S -- ZipEdit at 40 columns, still on a //e
*
* NOT the Apple ][+ build. This is the //e editor -- auxiliary-memory buffer,
* //e keyboard, Open-Apple commands -- drawing on a 40 column screen through
* screen40.S and laid out by GEOM40.
*
* It exists because those two pieces can be tested long before the ][+ build
* can run at all. The ][+ still needs its buffer moved into main memory and a
* keymap with no Open-Apple key in it; until both are done there is nothing to
* boot. This isolates the display and the geometry from that work, on a
* machine the suite can already drive.
*
* A //e in 40 column mode is a real configuration, so this is a fair test of
* the drawing: 80STORE stays off, writes to $0400 land in main memory, and
* what appears is what a ][+ would see.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   ZIPEDIT40.SYSTEM

             put   equates
             put   main             ; START first: ProDOS enters at $2000
             put   screen40         ; 40 columns, one bank, no MouseText
             put   auxbuf
             put   keysiie
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
             put   machine
             put   geom
