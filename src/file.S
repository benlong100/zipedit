*--------------------------------------
* FILE.S -- ProDOS 8 file I/O
*
* An MLI call is JSR $BF00 followed by an inline command byte and a pointer to
* a parameter block. On return the carry is set on error and A holds the code.
*
* Two constraints shape this:
*
*   1. MLI reads and writes main memory only, but the text lives in aux. So
*      every transfer stages through DATBUF and crosses banks a byte at a time.
*
*   2. Parameter blocks are written by ProDOS (ref numbers, transfer counts),
*      so they cannot live in the code image without breaking the immutability
*      the test suite checks. They sit in a dummy section and are initialised
*      at startup from a template that does live in the image.
*
* Transfers are capped at 255 bytes so a transfer count always fits in one
* byte. The lost efficiency is irrelevant next to a floppy seek, and it takes
* a pile of 16-bit arithmetic out of the loop.
*
* Files are written as ProDOS TXT ($04): high ASCII, CR ($8D) terminated,
* which is the native Apple II convention. `make pull` converts on the Mac.
*--------------------------------------

*--------------------------------------
* INITFILE -- copy the parameter block template into RAM
*--------------------------------------
INITFILE     ldx   #PARMEND-PARMTPL-1
:loop        lda   PARMTPL,x
             sta   OPENPARM,x
             dex
             bpl   :loop
             rts

* Must match the dummy section layout below, field for field.
PARMTPL
             dfb   $03              ; OPEN: param count
             da    FNAME
             da    IOBUF
             dfb   $00              ; ref_num, returned

             dfb   $04              ; READ
             dfb   $00              ; ref_num
             da    DATBUF
             da    $00ff            ; request 255 so the count fits a byte
             da    $0000            ; transfer count, returned

             dfb   $04              ; WRITE
             dfb   $00
             da    DATBUF
             da    $0000            ; request count, set per call
             da    $0000

             dfb   $01              ; CLOSE
             dfb   $00

             dfb   $07              ; CREATE
             da    FNAME
             dfb   $c3              ; access: destroy/rename/read/write
             dfb   $04              ; file type TXT
             da    $0000            ; aux type
             dfb   $01              ; storage type: standard file
             da    $0000            ; create date, 0 = now
             da    $0000            ; create time

             dfb   $01              ; DESTROY
             da    FNAME
PARMEND

*--------------------------------------
* MLI wrappers. STA preserves the carry, so callers can branch on it.
*--------------------------------------
OPENF        jsr   MLI
             dfb   $c8
             da    OPENPARM
             sta   MLIERR
             rts

READF        jsr   MLI
             dfb   $ca
             da    READPARM
             sta   MLIERR
             rts

WRITEF       jsr   MLI
             dfb   $cb
             da    WRITEPARM
             sta   MLIERR
             rts

CLOSEF       jsr   MLI
             dfb   $cc
             da    CLOSEPARM
             sta   MLIERR
             rts

CREATEF      jsr   MLI
             dfb   $c0
             da    CREATEPARM
             sta   MLIERR
             rts

DESTROYF     jsr   MLI
             dfb   $c1
             da    DESTPARM
             sta   MLIERR
             rts

*--------------------------------------
* SAVEFILE -- write the buffer to the file named in FNAME
*
* The gap is not written out: the text is two runs, before it and after it,
* so no compaction pass is needed.
*--------------------------------------
SAVEFILE     jsr   DESTROYF         ; a missing file is not an error here
             jsr   CREATEF
             bcs   :fail
             jsr   OPENF
             bcs   :fail
             lda   OPENPARM+5       ; ref_num
             sta   WRITEPARM+1
             sta   CLOSEPARM+1

*--- run one: buffer start up to the gap
             lda   #$00
             sta   AUXPTR
             lda   #AUXLO
             sta   AUXPTR+1
             lda   GAPBEG
             sta   RUNLEN
             lda   GAPBEG+1
             sec
             sbc   #AUXLO
             sta   RUNLEN+1
             jsr   WRITERUN
             bcs   :shut

*--- run two: past the gap to the end of the buffer
             lda   GAPEND
             sta   AUXPTR
             lda   GAPEND+1
             sta   AUXPTR+1
             lda   #$00
             sec
             sbc   GAPEND
             sta   RUNLEN
             lda   #AUXHI
             sbc   GAPEND+1
             sta   RUNLEN+1
             jsr   WRITERUN

:shut        jsr   CLOSEF
             clc
             rts
:fail        sec
             rts

*--------------------------------------
* WRITERUN -- write RUNLEN bytes of aux starting at AUXPTR
*--------------------------------------
WRITERUN     lda   RUNLEN
             ora   RUNLEN+1
             bne   :go
             clc
             rts

:go          lda   RUNLEN+1         ; chunk = min(255, RUNLEN)
             bne   :full
             lda   RUNLEN
             cmp   #$ff
             bcc   :have
:full        lda   #$ff
:have        sta   TMPC

             ldy   #$00             ; aux -> main staging
:copy        cpy   TMPC
             beq   :copied
             jsr   AUXRD
             sta   DATBUF,y
             iny
             jmp   :copy

:copied      lda   TMPC
             sta   WRITEPARM+4
             lda   #$00
             sta   WRITEPARM+5
             jsr   WRITEF
             bcs   :fail

             lda   AUXPTR           ; advance
             clc
             adc   TMPC
             sta   AUXPTR
             bcc   :sub
             inc   AUXPTR+1
:sub         lda   RUNLEN
             sec
             sbc   TMPC
             sta   RUNLEN
             bcs   WRITERUN
             dec   RUNLEN+1
             jmp   WRITERUN
:fail        sec
             rts

*--------------------------------------
* LOADFILE -- replace the buffer with the contents of FNAME
*--------------------------------------
LOADFILE     jsr   OPENF
             bcs   :fail
             lda   OPENPARM+5
             sta   READPARM+1
             sta   CLOSEPARM+1
             jsr   BUFINIT          ; discard whatever was there

:loop        jsr   READF
             bcs   :eof             ; end of file reports as an error
             lda   READPARM+6       ; transfer count
             sta   TMPC
             beq   :eof
             ldy   #$00
:ins         cpy   TMPC
             beq   :loop
             lda   DATBUF,y
             sty   TMPB
             jsr   INSCHR
             ldy   TMPB
             iny
             jmp   :ins

:eof         jsr   CLOSEF
             clc
             rts
:fail        sec
             rts

*--------------------------------------
* PROMPT -- read a line on the status line. STRPTR -> prompt text.
*           Result in PBUF/PLEN as high ASCII. Carry set if cancelled.
*
* High ASCII because that is what the buffer and the screen use; MKFNAME
* converts to the low ASCII ProDOS wants for a pathname. Y cannot hold the
* character count -- DRAWLINE clobbers it on every echo.
*--------------------------------------
PROMPT       jsr   CLRBUF
             ldx   #$00
             jsr   BUFSTR
             stx   TMPB             ; input begins at this column

*--- say how to back out; nothing else on screen does
             lda   #<HINTESC
             sta   STRPTR
             lda   #>HINTESC
             sta   STRPTR+1
             ldx   #PHINTCOL
             jsr   BUFSTR
             lda   #$00
             sta   PLEN
             jsr   PDRAW

:key         jsr   GETKEY
             cmp   #$8d             ; Return
             beq   :done
             cmp   #$9b             ; Esc
             beq   :cancel
             cmp   #$ff             ; Delete
             beq   :del
             cmp   #$a0             ; ignore other control keys
             bcc   :key

             ldx   PLEN
             cpx   #PMAXLEN
             bcs   :key
             sta   TMPA
             sta   PBUF,x
             txa
             clc
             adc   TMPB
             tax
             lda   TMPA             ; echo
             sta   LINEBUF,x
             inc   PLEN
             jsr   PDRAW
             jmp   :key

:del         lda   PLEN
             beq   :key
             dec   PLEN
             lda   PLEN
             clc
             adc   TMPB
             tax
             lda   #$a0
             sta   LINEBUF,x
             jsr   PDRAW
             jmp   :key

*--- either way, hand the status row straight back rather than leaving the
*    prompt sitting there until the user happens to press something else
:done        lda   PLEN
             beq   :cancel          ; empty entry is a cancel
             jsr   RESTORESTAT
             clc
             rts
:cancel      jsr   RESTORESTAT
             sec
             rts

*--------------------------------------
* MKFNAME -- turn what PROMPT collected into a ProDOS pathname
*--------------------------------------
MKFNAME      lda   PLEN
             sta   FNAME
             ldx   #$00
:loop        cpx   PLEN
             beq   :done
             lda   PBUF,x
             and   #$7f             ; ProDOS pathnames are low ASCII
             sta   FNAME+1,x
             inx
             bne   :loop
:done        rts

PDRAW        lda   #$01             ; the prompt owns the row too
             sta   MSGSHOWN
             lda   #STATROW
             jmp   DRAWLINE

*--------------------------------------
* SHOWMSG -- put STRPTR on the status line
*--------------------------------------
SHOWMSG      jsr   CLRBUF
             ldx   #$00
             jsr   BUFSTR
             lda   #$01             ; the message owns the row until a key
             sta   MSGSHOWN
             lda   #STATROW
             jmp   DRAWLINE

*--------------------------------------
* SHOWBUSY -- take the whole status row for a centred, inverse notice
*
* Drawn before a disk operation starts, so there is something on screen while
* ProDOS works. On a floppy the drive is audible; on a CompactFlash card
* nothing moves and nothing sounds, so a silent pause is indistinguishable from
* a hang.
*--------------------------------------
SHOWBUSY     jsr   CLRBUF
             ldy   #$00             ; measure the message
:len         lda   (STRPTR),y
             beq   :got
             iny
             bne   :len
:got         sty   TMPA
             lda   #SCRW
             sec
             sbc   TMPA
             lsr                    ; centre it
             tax
             jsr   BUFSTR
             jsr   INVBUF
             lda   #$01
             sta   MSGSHOWN
             lda   #STATROW
             jmp   DRAWLINE

*--------------------------------------
* SHOWERR -- report the last MLI error code in hex
*--------------------------------------
SHOWERR      jsr   CLRBUF
             lda   #<MSGERR
             sta   STRPTR
             lda   #>MSGERR
             sta   STRPTR+1
             ldx   #$00
             jsr   BUFSTR
             lda   MLIERR
             lsr
             lsr
             lsr
             lsr
             jsr   HEXDIG
             sta   LINEBUF,x
             inx
             lda   MLIERR
             and   #$0f
             jsr   HEXDIG
             sta   LINEBUF,x
             lda   #$01
             sta   MSGSHOWN
             lda   #STATROW
             jmp   DRAWLINE

HEXDIG       cmp   #$0a
             bcc   :dig
             clc
             adc   #$b7             ; 'A' - 10, high ASCII
             rts
:dig         clc
             adc   #$b0             ; '0', high ASCII
             rts

*--------------------------------------
* Key handlers
*--------------------------------------
KSAVE        lda   #<MSGSAVE
             sta   STRPTR
             lda   #>MSGSAVE
             sta   STRPTR+1
             jsr   PROMPT
             bcs   :quit
             jsr   MKFNAME
             lda   #<MSGSAVING
             sta   STRPTR
             lda   #>MSGSAVING
             sta   STRPTR+1
             jsr   SHOWBUSY
             jsr   SAVEFILE
             bcs   :err
             jmp   RESTORESTAT      ; the busy notice was the feedback
:err         jmp   SHOWERR
:quit        rts

KLOAD        lda   #<MSGOPEN
             sta   STRPTR
             lda   #>MSGOPEN
             sta   STRPTR+1
             jsr   PROMPT
             bcs   :quit
             jsr   MKFNAME
             lda   #<MSGLOADING
             sta   STRPTR
             lda   #>MSGLOADING
             sta   STRPTR+1
             jsr   SHOWBUSY
             jsr   LOADFILE
             bcs   :err
             jsr   HOMECURSOR
             jmp   RESTORESTAT      ; the busy notice was the feedback
:err         jmp   SHOWERR
:quit        rts

HINTESC      asc   "ESC CANCELS"
             dfb   $00
MSGSAVING    asc   "-- SAVING --"
             dfb   $00
MSGLOADING   asc   "-- LOADING --"
             dfb   $00
MSGSAVE      asc   "SAVE AS: "
             dfb   $00
MSGOPEN      asc   "OPEN: "
             dfb   $00
MSGERR       asc   " PRODOS ERROR $"
             dfb   $00

*--------------------------------------
* Mutable storage, declared but not emitted.
* IOBUF must be 1K and page aligned; ProDOS requires it.
*--------------------------------------
             dum   $0800
IOBUF        ds    1024
DATBUF       ds    256
FNAME        ds    65               ; length byte + up to 64 characters
PBUF         ds    64               ; what PROMPT collected, high ASCII
PLEN         ds    1
CLIPBUF      ds    256              ; line clipboard
FINDBUF      ds    64               ; search pattern, high ASCII
OPENPARM     ds    6
READPARM     ds    8
WRITEPARM    ds    8
CLOSEPARM    ds    2
CREATEPARM   ds    12
DESTPARM     ds    3
MLIERR       ds    1
             dend
