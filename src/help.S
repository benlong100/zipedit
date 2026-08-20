*--------------------------------------
* HELP.S -- the keyboard command screens (OA-? , alias OA-H)
*
* NOT Ctrl-H: the //e keyboard encoder maps Ctrl-H and the left arrow to the
* same $88, exactly as it does Tab and Ctrl-I, so binding help there would cost
* the cursor-left key. Verified on the machine and asserted in the suite.
*
* OA-? opens this. The one-line cheat sheet moved to OA-/, the same physical
* key unshifted, which keeps the two mnemonically paired.
*
* TWO PAGES. One screen held every command at once and had run out of room --
* the selecting and clipboard columns had collided with no gap between them.
* OA-? now opens page one, a key turns to page two, and a key leaves. Both
* pages are the same 21-row box, so turning the page repaints in place and
* leaving needs nothing more than the full redraw the main loop already does.
*
* Page one is what you use while typing: moving, editing, selecting. Page two
* is what you reach for deliberately: markdown, clipboard, search, files and
* the screen toggles. The footer says which page you are on and what a key
* will do next, since nothing else on screen would tell you a second page
* exists.
*
* The border is MouseText, available at screen codes $40-$5F once the alternate
* character set is on. Probed rather than recalled -- and the first reading of
* the probe was wrong in a way only a real screen showed.
*
* $4C is a single stroke at the TOP of its cell. $5C is NOT a second rule at a
* different height: it draws TWO strokes, one at the top of its cell and one at
* the bottom, so a row of it renders as a double line. Using it for the top
* edge is what laid a stray line across the top of the screen, and using it
* under the title put two lines there. Every rule in this box is $4C, which
* sits hard against the row above it so the verticals descend cleanly from it.
*
* $5F is a clean vertical, drawn at the LEFT edge of its cell. Both ends of a
* rule row follow from that. The rule must START at the corner cell, or it
* begins a whole cell right of the vertical and never reaches it. It must END
* one cell short, letting the vertical own that cell, or it runs a whole cell
* past the corner. So a rule row is 63 rules then a vertical, and the closing
* bottom rule -- with nothing below it to carry a vertical -- is 63 rules and
* nothing else.
*
* MouseText has no corner or T-junction glyphs on this ROM -- $40-$4A are
* apples, a pointer, an hourglass, check marks and arrows -- so a corner is
* simply where a rule meets a vertical.
*
* Rows are emitted as raw screen codes, since MouseText cannot come from `asc`.
* The Open Apple key is drawn with its own glyph ($41) rather than spelt "OA",
* which is both truer to the keyboard and a column narrower.
*
* The rows below are GENERATED -- do not hand-edit the hex. Edit the layout in
* tools/genhelp.py and re-run it; it enforces the column stops and fails loudly
* if a description would overrun the border, which is exactly the mistake the
* one-page version shipped with.
*
* The box is 21 rows so it leaves the cheat sheet and status line showing
* underneath. Each row blanks the full screen width and paints the box in the
* middle.
*--------------------------------------
HELPCOL      equ   8
HELPN        equ   21
HELPPAGES    equ   2

*--------------------------------------
* HELPSHOW -- paint a page, wait for a key, then turn or leave
*--------------------------------------
HELPSHOW     lda   #$00
             sta   HELPPG
:page        lda   #$00
             sta   HELPI
:loop        lda   HELPI
             asl
             tay
             ldx   HELPPG
             bne   :two
             lda   HELPTBL1,y
             sta   STRPTR
             lda   HELPTBL1+1,y
             sta   STRPTR+1
             jmp   :draw
:two         lda   HELPTBL2,y
             sta   STRPTR
             lda   HELPTBL2+1,y
             sta   STRPTR+1
:draw        jsr   CLRBUF
             ldx   #HELPCOL
             jsr   BUFSTR
             lda   HELPI
             jsr   DRAWLINE
             inc   HELPI
             lda   HELPI
             cmp   #HELPN
             bne   :loop
             jsr   GETKEY           ; a key turns the page, and then leaves
             inc   HELPPG
             lda   HELPPG
             cmp   #HELPPAGES
             bne   :page
             rts

HELPTBL1
             da    H100
             da    H101
             da    H102
             da    H103
             da    H104
             da    H105
             da    H106
             da    H107
             da    H108
             da    H109
             da    H110
             da    H111
             da    H112
             da    H113
             da    H114
             da    H115
             da    H116
             da    H117
             da    H118
             da    H119
             da    H120

HELPTBL2
             da    H200
             da    H201
             da    H202
             da    H203
             da    H204
             da    H205
             da    H206
             da    H207
             da    H208
             da    H209
             da    H210
             da    H211
             da    H212
             da    H213
             da    H214
             da    H215
             da    H216
             da    H217
             da    H218
             da    H219
             da    H220

H100
             hex   5F4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C
             hex   4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C5F
             dfb   $00
H101
             hex   5FA0A0A0CDC1D2CBC4CFD7CEA0C5C4C9D4CFD2A0C6CFD2A0D4C8C5A0C1D0D0CC
             hex   C5A0AFAFE5A0A0ADADA0A0CBC5D9C2CFC1D2C4A0C3CFCDCDC1CEC4D3A0A0A05F
             dfb   $00
H102
             hex   4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C
             hex   4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C5F
             dfb   $00
H103
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H104
             hex   5FA0CDCFD6C9CEC7A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0C5C4C9D4C9CEC7A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H105
             hex   5FA0A0A0E1F2F2EFF7F3A0A0A0A0A0A0A0E3E8E1F2A0AFA0ECE9EEE5A0A0A0A0
             hex   A0A0A0C4E5ECE5F4E5A0A0A0E4E5ECE5F4E5A0ECE5E6F4A0A0A0A0A0A0A0A05F
             dfb   $00
H106
             hex   5FA0A0A041ADE1F2F2EFF7F3A0A0A0A0A0F7EFF2E4A0AFA0F0E1E7E5A0A0A0A0
             hex   A0A0A0C3F4F2ECADC4A0A0A0E4E5ECE5F4E5A0F2E9E7E8F4A0A0A0A0A0A0A05F
             dfb   $00
H107
             hex   5FA0A0A0C3F4F2ECADC1A0A0A0A0A0A0A0ECE9EEE5A0F3F4E1F2F4A0A0A0A0A0
             hex   A0A0A0C3F4F2ECADD9A0A0A0E4E5ECE5F4E5A0F4EFA0ECE9EEE5A0E5EEE4A05F
             dfb   $00
H108
             hex   5FA0A0A0C3F4F2ECADC5A0A0A0A0A0A0A0ECE9EEE5A0E5EEE4A0A0A0A0A0A0A0
             hex   A0A0A0D4E1E2A0A0A0A0A0A0E9EEE4E5EEF4A0F4F7EFA0F3F0E1E3E5F3A0A05F
             dfb   $00
H109
             hex   5FA0A0A041ADBCA0A041ADBEA0A0A0A0A0E4EFE3A0F3F4E1F2F4AFE5EEE4A0A0
             hex   A0A0A041ADD2A0A0A0A0A0A0F2E5E6ECEFF7A0F0E1F2E1E7F2E1F0E8A0A0A05F
             dfb   $00
H110
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A041ADC4E5ECE5F4E5A0E4E5ECE5F4E5A0F7EFF2E4A0ECE5E6F4A0A0A05F
             dfb   $00
H111
             hex   5FA0D3C5CCC5C3D4C9CEC7A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H112
             hex   5FA0A0A041ADF3F0E1E3E5A0A0A0A0A0A0F3F4E1F2F4A0F3E5ECE5E3F4E9EEE7
             hex   A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H113
             hex   5FA0A0A0E1F2F2EFF7F3A0A0A0A0A0A0A0F0E1E9EEF4A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H114
             hex   5FA0A0A0C5F3E3A0A0A0A0A0A0A0A0A0A0E3E1EEE3E5ECA0A0A0A0A0A0A0A0A0
             hex   A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H115
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H116
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H117
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H118
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H119
             hex   5FA0A0A0A0A0A0A0A0A0A0F0F2E5F3F3A0E1EEF9A0EBE5F9A0E6EFF2A0EDEFF2
             hex   E5A0A0A0ADADA0A0A0F0E1E7E5A0B1A0EFE6A0B2A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H120
             hex   4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C
             hex   4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C
             dfb   $00
H200
             hex   5F4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C
             hex   4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C5F
             dfb   $00
H201
             hex   5FA0A0A0CDC1D2CBC4CFD7CEA0C5C4C9D4CFD2A0C6CFD2A0D4C8C5A0C1D0D0CC
             hex   C5A0AFAFE5A0A0ADADA0A0CBC5D9C2CFC1D2C4A0C3CFCDCDC1CEC4D3A0A0A05F
             dfb   $00
H202
             hex   4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C
             hex   4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C5F
             dfb   $00
H203
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H204
             hex   5FA0CDC1D2CBC4CFD7CEA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0D3C5C1D2C3C8A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H205
             hex   5FA0A0A0C3F4F2ECADC2A0A0A0A0A0A0A0AAAAE2EFECE4AAAAA0F7EFF2E4A0A0
             hex   A0A0A041ADC6A041ADC7A0A0E6E9EEE4A0AFA0E1E7E1E9EEA0A0A0A0A0A0A05F
             dfb   $00
H206
             hex   5FA0A0A0C3F4F2ECADC9A0A0A0A0A0A0A0AAE9F4E1ECE9E3AAA0F7EFF2E4A0A0
             hex   A0A0A041ADCCA0A0A0A0A0A0E7EFA0F4EFA0ECE9EEE5A0A0A0A0A0A0A0A0A05F
             dfb   $00
H207
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A041ADD7A0A0A0A0A0A0F7EFF2E4A0E3EFF5EEF4A0A0A0A0A0A0A0A0A05F
             dfb   $00
H208
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H209
             hex   5FA0C3CCC9D0C2CFC1D2C4A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0C6C9CCC5D3A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H210
             hex   5FA0A0A041ADC3A0A0A0A0A0A0A0A0A0A0E3EFF0F9A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A041ADCEA0A0A0A0A0A0EEE5F7A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H211
             hex   5FA0A0A041ADD8A0A0A0A0A0A0A0A0A0A0E3F5F4A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A041ADCFA0A0A0A0A0A0EFF0E5EEA0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H212
             hex   5FA0A0A041ADD6A0A0A0A0A0A0A0A0A0A0F0E1F3F4E5A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A041ADD3A0A0A0A0A0A0F3E1F6E5A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H213
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A041ADC1A0A0A0A0A0A0F3E1F6E5A0E1F3A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H214
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A041ADD1A0A0A0A0A0A0F1F5E9F4A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H215
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H216
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0D3C3D2C5C5CEA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H217
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A041ADAFA0A0A0A0A0A0E3E8E5E1F4A0F3E8E5E5F4A0A0A0A0A0A0A0A05F
             dfb   $00
H218
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0
             hex   A0A0A041ADBFA0A0A0A0A0A0F4E8E9F3A0E8E5ECF0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H219
             hex   5FA0A0A0A0A0A0A0A0A0A0F0F2E5F3F3A0E1EEF9A0EBE5F9A0F4EFA0F2E5F4F5
             hex   F2EEA0A0A0ADADA0A0A0F0E1E7E5A0B2A0EFE6A0B2A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
H220
             hex   4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C
             hex   4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C
             dfb   $00
             dum   $1420
HELPI        ds    1
HELPPG       ds    1                ; which page is on screen, 0 or 1
             dend
