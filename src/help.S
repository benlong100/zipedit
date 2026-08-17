*--------------------------------------
* HELP.S -- the keyboard command screen (OA-? , alias OA-H)
*
* NOT Ctrl-H: the //e keyboard encoder maps Ctrl-H and the left arrow to the
* same $88, exactly as it does Tab and Ctrl-I, so binding help there would cost
* the cursor-left key. Verified on the machine and asserted in the suite.
*
* OA-? opens this. The one-line cheat sheet moved to OA-/, the same physical
* key unshifted, which keeps the two mnemonically paired.
*
* The border is MouseText, available at screen codes $40-$5F once the alternate
* character set is on. Probed rather than recalled: $5C and $4C are horizontal
* rules at different heights within the cell, and $5F is a clean vertical. The
* low rule goes on top and the high rule on the bottom so both meet the
* verticals and the box closes.
*
* MouseText has no corner or T-junction glyphs on this ROM -- $40-$4A are
* apples, a pointer, an hourglass, check marks and arrows -- so a corner is
* simply where a rule meets a vertical.
*
* Rows are emitted as raw screen codes, since MouseText cannot come from `asc`.
* The Open Apple key is drawn with its own glyph ($41) rather than spelt "OA",
* which is both truer to the keyboard and a column narrower.
*
* The box is 22 rows so it leaves the cheat sheet and status line showing
* underneath. Each row blanks the full screen width and paints the box in the
* middle, so dismissing it needs nothing more than the full redraw the main
* loop already performs whenever a handler has not opted into the one-row path.
*--------------------------------------
HELPCOL      equ   8
HELPN        equ   22

*--------------------------------------
* HELPSHOW -- paint the box, wait for any key
*--------------------------------------
HELPSHOW     lda   #$00
             sta   HELPI
:loop        lda   HELPI
             asl
             tay
             lda   HELPTBL,y
             sta   STRPTR
             lda   HELPTBL+1,y
             sta   STRPTR+1
             jsr   CLRBUF
             ldx   #HELPCOL
             jsr   BUFSTR
             lda   HELPI
             jsr   DRAWLINE
             inc   HELPI
             lda   HELPI
             cmp   #HELPN
             bne   :loop
             jsr   GETKEY
             rts

HELPTBL
             da    HL00
             da    HL01
             da    HL02
             da    HL03
             da    HL04
             da    HL05
             da    HL06
             da    HL07
             da    HL08
             da    HL09
             da    HL10
             da    HL11
             da    HL12
             da    HL13
             da    HL14
             da    HL15
             da    HL16
             da    HL17
             da    HL18
             da    HL19
             da    HL20
             da    HL21

HL00
             hex   5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C
             hex   5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C
             dfb   $00
HL01
             hex   5FA0A0A0CDC1D2CBC4CFD7CEA0C5C4C9D4CFD2A0C6CFD2A0D4C8C5A0C1D0D0CC
             hex   C5A0AFAFE5A0A0ADADA0A0CBC5D9C2CFC1D2C4A0C3CFCDCDC1CEC4D3A0A0A05F
             dfb   $00
HL02
             hex   5F5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C
             hex   5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5F
             dfb   $00
HL03
             hex   5FA0A0CDCFD6C9CEC7A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0C5
             hex   C4C9D4C9CEC7A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL04
             hex   5FA0A0A0E1F2F2EFF7F3A0A0A0A0A0A0A0E3E8E1F2A0AFA0ECE9EEE5A0A0A0C4
             hex   E5ECE5F4E5A0A0A0A0E4E5ECE5F4E5A0ECE5E6F4A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL05
             hex   5FA0A0A041ADE1F2F2EFF7F3A0A0A0A0F7EFF2E4A0AFA0F0E1E7E5A0A0A0A0C3
             hex   F4F2ECADC4A0A0A0A0E4E5ECE5F4E5A0F2E9E7E8F4A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL06
             hex   5FA0A0A0C3F4F2ECADC1A0A0A0A0A0A0A0ECE9EEE5A0F3F4E1F2F4A0A0A0A0C3
             hex   F4F2ECADD9A0A0A0A0E4E5ECE5F4E5A0F4EFA0ECE9EEE5A0E5EEE4A0A0A0A05F
             dfb   $00
HL07
             hex   5FA0A0A0C3F4F2ECADC5A0A0A0A0A0A0A0ECE9EEE5A0E5EEE4A0A0A0A0A0A0D4
             hex   E1E2A0A0A0A0A0A0A0E9EEE4E5EEF4A0F4F7EFA0F3F0E1E3E5F3A0A0A0A0A05F
             dfb   $00
HL08
             hex   5FA0A0A041ADBCA0A0A041ADBEA0A0A0E4EFE3A0F3F4E1F2F4AFE5EEE4A0A041
             hex   ADD2A0A0A0A0A0A0A0F2E5E6ECEFF7A0F0E1F2E1E7F2E1F0E8A0A0A0A0A0A05F
             dfb   $00
HL09
             hex   5FA0A0CDC1D2CBC4CFD7CEA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0C6
             hex   C9CCC5D3A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL10
             hex   5FA0A0A0C3F4F2ECADC2A0A0A0A0A0A0A0AAAAE2EFECE4AAAAA0F7EFF2E4A041
             hex   ADCFA0A0A0A0A0A0A0EFF0E5EEA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL11
             hex   5FA0A0A0C3F4F2ECADC9A0A0A0A0A0A0A0DFE9F4E1ECE9E3DFA0F7EFF2E4A041
             hex   ADD3A0A0A0A0A0A0A0F3E1F6E5A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL12
             hex   5FA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A041
             hex   ADD1A0A0A0A0A0A0A0F1F5E9F4A0F4EFA0D0F2EFC4CFD3A0A0A0A0A0A0A0A05F
             dfb   $00
HL13
             hex   5FA0A0D3C5C1D2C3C8A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0C3
             hex   CCC9D0C2CFC1D2C4A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL14
             hex   5FA0A0A041ADC6A0A0A0A0A0A0A0A0A0E6E9EEE4A0A0A0A0A0A0A0A0A0A0A041
             hex   ADC3A0A0A0A0A0A0A0E3EFF0F9A0ECE9EEE5A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL15
             hex   5FA0A0A041ADC7A0A0A0A0A0A0A0A0A0E6E9EEE4A0E1E7E1E9EEA0A0A0A0A041
             hex   ADD8A0A0A0A0A0A0A0E3F5F4A0ECE9EEE5A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL16
             hex   5FA0A0A041ADCCA0A0A0A0A0A0A0A0A0E7EFA0F4EFA0ECE9EEE5A0A0A0A0A041
             hex   ADD6A0A0A0A0A0A0A0F0E1F3F4E5A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL17
             hex   5FA0A0D3C3D2C5C5CEA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0C1
             hex   D4A0C1CED9A0D0D2CFCDD0D4A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL18
             hex   5FA0A0A041ADAFA0A0A0A0A0A0A0A0A0E3E8E5E1F4A0F3E8E5E5F4A0A0A0A0D2
             hex   E5F4F5F2EEA0A0A0A0E1E3E3E5F0F4A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL19
             hex   5FA0A0A041ADBFA0A0A0A0A0A0A0A0A0F4E8E9F3A0E8E5ECF0A0A0A0A0A0A0C5
             hex   F3E3A0A0A0A0A0A0A0E3E1EEE3E5ECA0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL20
             hex   5FA0A0A0F0F2E5F3F3A0E1EEF9A0EBE5F9A0F4EFA0F2E5F4F5F2EEA0A0A0A0A0
             hex   A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A05F
             dfb   $00
HL21
             hex   4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C
             hex   4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C
             dfb   $00

             dum   $1420
HELPI        ds    1
             dend
