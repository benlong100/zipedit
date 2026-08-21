*--------------------------------------
* EDIT2P.S -- ZipEdit for the Apple ][+
*
* Forty columns, main-memory buffer, no auxiliary bank and no MouseText. The
* same editor as edit.S: what differs is which screen and which memory driver
* get PUT, and the geometry that the screen driver names.
*
* INCOMPLETE. This still uses the //e keymap, so every command behind
* Open-Apple -- save, open, find, help, selection -- is unreachable on a
* machine with no Open-Apple key. It boots, it draws, it types, it wraps, and
* the cursor moves; that is worth having on the real machine before the keymap
* is rewritten, because it is the part that would be hardest to debug blind.
*
* See docs/design.md section 9 for the keymap this is waiting on.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   ZIPEDIT2P.SYSTEM

             put   equates
             put   main             ; START first: ProDOS enters at $2000
             put   screen40         ; 40 columns, one bank
             put   mainbuf          ; the text buffer in main memory
             put   keys2p
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

*--- The text buffer starts here, on the page after the code. Padding to a
*    page boundary first means mainbuf.S can take the high byte and be done,
*    and means the buffer follows the code wherever the code ends up rather
*    than starting at a number somebody has to remember to re-tune.
             ds    \
CODEEND      equ   *
