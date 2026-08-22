ZipEdit @VERSION@
A Markdown editor for the Apple II
August 2026


WHAT IS IN THIS FOLDER

  ZIPEDIT.po   For an Enhanced Apple //e with 128K. 80 columns, and
               room for about seven thousand words.
  ZIPEDIT2P.po For an Apple ][+ with 64K. 40 columns, and room for
               about three thousand words. It also runs on a //e.
  xfer.sh      A shell script for moving files between a disk image
               and your Mac.
  README.txt   This file.

  Both are bootable ProDOS 8 disk images, 143K, in 5.25-inch format.
  Take the one that matches your machine; they are the same editor.


WHICH ONE DO I WANT

  An Enhanced //e -- or a //c, or a IIgs -- takes ZIPEDIT.po. So does
  an unenhanced //e with an extended 80-column card: the editor asks
  the machine what it is at startup and draws accordingly.

  An Apple ][+, or a //e without the extra 64K, takes ZIPEDIT2P.po.

  If you are not sure, try ZIPEDIT.po first. A machine that cannot run
  it will not get as far as the splash screen, and nothing is harmed.


RUNNING IT

  In an emulator, mount the image in drive 1 and boot it.

  On real hardware, write the image to a 5.25-inch disk, or copy it to
  the card your Floppy Emu or CFFA3000 reads.

  A splash screen comes up. Press any key and you are in an empty
  document.

  On the //e, Open-Apple-? shows the keyboard commands, two pages of
  them. On the ][+, which has no Open-Apple key, press Esc then ?.


THE ][+ AND LOWER CASE

  An Apple ][+ character generator holds 64 glyphs and none of them is
  a lowercase letter, so ZipEdit borrows Apple Writer's answer: type in
  lower case and it draws as ordinary capitals. Press Esc before a
  letter to get a capital, which draws inverse so that it stands out.

  The screen is doing the best it can. The file on the disk has the
  case you meant.


GETTING YOUR WRITING BACK OUT

  ZipEdit reads ordinary text files from any machine -- Mac, PC or
  Apple line endings, high ASCII or low. Drop a .txt on the disk and
  open it.

  It saves ordinary text files too. Line breaks are only the ones you
  typed -- the wrapping you see on screen is not written into the file
  -- so what lands on your Mac needs no cleaning up.

  To copy files off an image:

      ./xfer.sh pull ZIPEDIT.po ~/Documents

  and onto one:

      ./xfer.sh push ZIPEDIT.po ~/Documents

  The script needs AppleCommander, which it will tell you about if it
  cannot find it.


WHERE IT LIVES

  https://github.com/benlong100/zipedit

  Written in 6502 assembly. The source, the design notes and the
  regression suite are all in the repository.
