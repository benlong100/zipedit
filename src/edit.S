*--------------------------------------
* EDIT.S -- 80 column Markdown editor for the Enhanced Apple //e
*
* Entered by ProDOS 8 as a SYS file at $2000.
*
* At this stage: display layer only. The text area is filled with static
* sample content so the layout, the aux/main interleave, the cheat sheet and
* the status line can all be verified on screen. Buffer, keyboard and file
* layers land next.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   EDIT.SYSTEM

             put   equates

*--------------------------------------
START        lda   #FCHEAT          ; cheat sheet visible at startup
             sta   FLAGS

             jsr   DISPINIT
             jsr   DRAWSAMPLE
             jsr   DRAWCHEAT
             jsr   DRAWSTATUS

:hang        jmp   :hang

*--------------------------------------
* DRAWSAMPLE -- fill the text area from a table of strings
*--------------------------------------
DRAWSAMPLE   ldx   #$00
:loop        stx   TMPB
             txa
             asl                    ; two bytes per table entry
             tay
             lda   SAMPLE,y
             sta   STRPTR
             lda   SAMPLE+1,y
             sta   STRPTR+1
             lda   TMPB
             jsr   SHOWSTR
             ldx   TMPB
             inx
             cpx   #NSAMPLE
             bne   :loop
             rts

*--------------------------------------
             put   display

*--------------------------------------
* Sample content
*--------------------------------------
SAMPLE       da    L00,L01,L02,L03,L04,L05,L06,L07
             da    L08,L09,L10,L11,L12,L13,L14,L15
NSAMPLE      equ   16

L00          asc   "# Notes from the Apple //e"
             dfb   $00
L01          dfb   $00
L02          asc   "This editor is written in 6502 assembly and runs under ProDOS 8"
             dfb   $00
L03          asc   "on an Enhanced Apple //e with 128K. The text buffer lives in"
             dfb   $00
L04          asc   "auxiliary memory as a gap buffer, which leaves main memory for"
             dfb   $00
L05          asc   "the code, the line index and the clipboard."
             dfb   $00
L06          dfb   $00
L07          asc   "## How it writes"
             dfb   $00
L08          dfb   $00
L09          asc   "- lines hard wrap near column 76, so one line is one screen row"
             dfb   $00
L10          asc   "- **bold** with Ctrl-B, _italic_ with Ctrl-I"
             dfb   $00
L11          asc   "- `code` spans and [links](url) are typed literally"
             dfb   $00
L12          asc   "- Open-Apple-? toggles the cheat sheet below"
             dfb   $00
L13          dfb   $00
L14          asc   "> Drafted here, then carried back to the Mac as plain UTF-8."
             dfb   $00
L15          dfb   $00
