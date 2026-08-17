*--------------------------------------
* EQUATES.S -- hardware and zero page map
*
* Emits no code; included first so everything below can reference it.
*--------------------------------------

*--- soft switches (write to set, unless noted) ---
CLR80STORE   equ   $c000
SET80STORE   equ   $c001            ; PAGE2 then selects screen half
RAMRDOFF     equ   $c002
RAMRDON      equ   $c003
RAMWRTOFF    equ   $c004
RAMWRTON     equ   $c005
CLR80VID     equ   $c00c
SET80VID     equ   $c00d            ; 80 column video
CLRALTCHAR   equ   $c00e
SETALTCHAR   equ   $c00f            ; alt charset: MouseText + inverse lower
MAINWR       equ   $c054            ; PAGE2 off -> screen writes to MAIN
AUXWR        equ   $c055            ; PAGE2 on  -> screen writes to AUX
TXTSET       equ   $c051
MIXCLR       equ   $c052
HIRESOFF     equ   $c056

*--- keyboard (read) ---
KBD          equ   $c000            ; bit 7 set when a key is waiting
KBDSTRB      equ   $c010
OPNAPPLE     equ   $c061            ; bit 7 = Open-Apple held
CLSAPPLE     equ   $c062            ; bit 7 = Closed-Apple held

*--- firmware ---
AUXMOVE      equ   $c311

*--- ProDOS global page ---
MLI          equ   $bf00
DEVTBL       equ   $bf10            ; driver addresses, indexed by unit>>4
RAMDRV       equ   $bf26            ; slot 3 drive 2 -- where /RAM hooks in
DEVNUM       equ   $bf30
DEVCNT       equ   $bf31            ; device count MINUS ONE
DEVLST       equ   $bf32

*--- auxiliary text buffer ---
AUXLO        equ   $08              ; buffer starts at aux $0800
AUXHI        equ   $c0              ; and ends below aux $C000

*--- zero page ---
* $3c-$43 are left alone: AUXMOVE uses them as A1/A2/A4.
SCRPTR       equ   $06              ; 2 bytes, current screen row base
STRPTR       equ   $08              ; 2 bytes, string source
CURROW       equ   $0a
CURCOL       equ   $0b
SAVEY        equ   $0c
TMPA         equ   $0d
TMPB         equ   $0e
FLAGS        equ   $0f
AUXPTR       equ   $10              ; 2 bytes, pointer into the aux buffer

*--- FLAGS bits ---
FCHEAT       equ   %00000001        ; cheat sheet visible

*--- screen geometry ---
SCRW         equ   80
CHEATROW     equ   22               ; 0-based; row 23 in the design doc
STATROW      equ   23
TEXTROWS     equ   22               ; when the cheat sheet is showing
TEXTROWSMAX  equ   23               ; when it is hidden
