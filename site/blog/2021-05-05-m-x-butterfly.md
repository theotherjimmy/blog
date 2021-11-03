```templateinfo
title = "M-x Butterfly Build Log"
description = "A good blog"
style = "post.css"
template = "post.html"
time = "2021-05-05 19:53:52 +0000"
```
Once, shortly after college, I built a keyboard.

I designed this keyboard myself, using a tool called 
[ImplicitCad](https://implicitcad.org), for manufacture on a laser cutter.
I used a laser cutter because I had access to it, as part of the newly created
makerspace at the college and I was more comfortable with programmatic 2D 
design, despite my previous use of blender and AutoDesk Inventer.

I designed the keyboard simply: I traced my hand flat on a sheet of paper and
used that outline to position the home row and home thumb keys.
This created a column staggered layout.
Then I filled in the columns with three keys each and added an extra column for
my pointer finger.
I mimicked the Kinesis Advantage in the thumb clusters, hoping that they had done
enough studying to get the layout correct.
The layout I designed had no number or function keys, and totaled to a
minimallist 42 keys.

The program, using ImplicitCad as a Haskell library, is available through github
as [my keyboardCad repo](https://github.com/theotherjimmy/keyboardCad).
I made the model generation program far too general for my own good, allowing 
the creation of any column staggered keyboard with an extra row for the pointer
finger and a thumb cluster.
This was a generality that I did not need, and was not worth the extra effort.
Sadly, I'm no longer able to recreate the designs.
You'll have to trust me that they look like a butterfly.

Later, I bought a small amount of plywood, birch if I recall correctly, and
scheduled some time with the laser cutter.
After about an hour of fiddling around, I had my cuts.

I then selected my MCU, ordered key switches and key caps.
I could have done this earlier, but since this was a passion project, it had no
deadline, and would languish needlessly.
The MCU I selected is a Luminary Micro LM4F, now a TI part called the TM4C, as 
part of a board called a launchpad.
I selected this part because I had access to a large box of more than 100 of
them, it had sufficient IO to drive the 42 keys and it had a usb keyboard example
application.
Thinking myself a bit of a brute on keyboards, I opted for Cherry MX Clears.
The Clears were originally designed as the space bar key switch for keyboards
that feature MX Browns.
I selected black, blank, DSA key caps as I liked the way the looked.

After confirming that the example application worked, including testing the
matrix scanning by shorting a columns pin to a row pin, I got to soldering.
I could not simply solder to the through holes, as the launchpad had 
combination male and female headers already soldered in place.
I spent an hour or two with a soldering iron and flush cutters making brutal
work of these headers.
The header remains were discarded and I had a low-profile launchpad to put into
my keyboard.

The next obstacle in my path was that the keys, while they fit in their sockets,
did not stay in place.
I reached for whatever glue I had on hand, hot glue.
While it held the keys, mostly, it flexed some, and would allow them to slip 
when left in the sun.
Further, this presented difficulty when soldering, as the glue would melt if I
held the soldering iron near it for more than a second or two.

Finally, I soldered the key matrices.
Having more than 30 GPIO available, I elected to solder the matrices 
independently and use a GPIO for each thumb key.
This was bit wasteful, but it meant that I simplify the hardware, which I was 
most nervous about, at the expense of slightly more complicated software.
I was sure to check my work with frequent continuity tests with a multi-meter,
finding several shorts that I subsequently fixed.

Now I could write the firmware.

I wrote the firmware in C, using the StellarisWare library, and it's hosted
in an incomplete form on github as 
[my keyboard-firmware repo](https://github.com/theotherjimmy/keyboard-firmware).
I don't recall writing this to be that difficult, though it did take me weeks
to find and squash all of the bugs I wrote.

After all this work I was ready to use the keyboard. 

I called it the M-x Butterfly, as it had MX switches and it looked like a
butterfly.

Typing was slow at first.
After a few weeks of use, I got used to it, and was typing proficiently on it
regularly.

However, this keyboard has a few flaws that lead to it's quick retire.
When designing the key locations, I had placed the home row at the full extension
of my fingers, making it quite difficult to reach above the home row.
When resting on the home row, my hands were flat, which is not very
comfortable.
Since I had not allocated any keys for them, the numbers and symbols were on a
separate layer.
This made typing numbers difficult, and symbols a hand-straining 3-key chord.

So I bought a goldtouch split keyboard on ebay for a reasonable price and typed
on it for a while.
