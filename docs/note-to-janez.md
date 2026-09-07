Your corrections are all in, and the Slovenian build passes the full test
suite. Almost everything went in exactly as you wrote it. Three things need
your eye, and one of them is a word we put in ourselves.

## 1. CHEATTXT -- we shortened one of your words and you should overrule us

Your line was 82 characters and the cheat sheet row is 80, so the screen was
cutting "(url)" down to "(ur". We took two characters off by shortening
koncano to konc.:

  `koda` # H1 ## H2 - seznam 1. st. - [ ] opraviti - [x] konc. > citat [link](url)

That is now exactly 80. It is the only place we have changed your Slovenian,
and konc. was chosen only because the file already abbreviates st. the same
way. If two characters are better spent somewhere else in that line, move
them -- anything at or under 80 works.

(For what it is worth, the machine translation was 89 characters and had been
losing nine. You had already fixed most of it.)

## 2. MSGWRAPPED -- a new string, and a guess

Find now wraps: a search that reaches the end of the document starts again at
the top instead of stopping. When it does that, the status row says so, because
a cursor that suddenly jumps backwards otherwise looks like a find that went
the wrong way.

  English:  " WRAPPED TO THE TOP"
  ours:     " NADALJEVANO Z VRHA"

Nobody who speaks Slovenian has seen this one. The sense wanted is "the search
reached the end and carried on from the beginning". It is NOT an error and
nothing has gone wrong -- and it is not about text being wrapped or folded. If
there is an ordinary phrase a Slovenian editor would use here, we would rather
have that.

## 3. The word count cannot be right, and we would like your least-bad answer

Slovenian counts in four forms -- 1 beseda, 2 besedi, 3-4 besede, 5+ besed --
and the editor has two: one for exactly 1, one for everything else.

  WTAIL1 = " BESEDA"
  WTAIL  = " BESED"

So "2 BESED" and "3 BESED" are both wrong. This is a limitation of the program,
not of the file, and we can fix it properly in the code if it is worth doing --
it is not a large change. What we would like to know is whether that is worth
doing, or whether some other pair of forms is a good enough compromise that
nobody notices.

## Two questions while you are in there

**The discard key.** The unsaved-changes prompt is:

  " NESHRANJENE SPREMEMBE.  S = SHRANI   D = ZAVRZI   ESC = PREKLICI"

You flagged that D does not carry the mnemonic in Slovenian the way it does for
"discard", and you are right. S happens to work for "shrani". The letters are
read by the program, so they are not free -- but they ARE changeable: if Z for
"zavrzi" is the natural key, say so and we will change what the program
listens for. Same for any other letter.

**Your credit.** The splash screen now reads:

  Razlicica 1.4 - avgust 2026
  Ben Long, prevod Janez Starc

You wrote that line yourself, so this is only a check that it is how you want
to be credited, and that the wording and order are right.

## What has changed around you since your pass

- The version is 1.4.
- The help screen carries the web address on page one. It is not translated --
  a URL has to match the server exactly.
- The status row labels are still your V: and S:. We moved them back to the
  columns they have to sit on: the line and column numbers are painted over
  that row at fixed positions, so a longer filename has to eat the spaces in
  front of the labels rather than push them along. Wording unchanged.

## The rules, so nothing you write fails to build

You write ordinary Slovenian -- s, c, z with carons and all. The tools do the
rest; if you ever find yourself typing a { to mean an s, that is a bug in our
tools, not something for you to work around.

The only hard limits:

  CHEATTXT     80 characters at most
  STATTXT      exactly 80, and STATTXT40 exactly 40. These are layouts rather
               than sentences. Change the words freely; if the total length
               changes, tell us and we will re-space it.
  UNTITLED     14 characters at most, must start with a letter, and only
               letters, digits and full stops -- it becomes a real filename
               the moment somebody saves without naming the document.
  HELP lines   each has a column budget. Too long and the build stops with a
               message saying so, rather than shipping a mangled row -- so
               there is no way for you to break it silently. Try it and see.

Everything else is free text.
