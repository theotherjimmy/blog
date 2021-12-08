```templateinfo
title = "Notes from a bug"
description = "A good blog"
style = "post.css"
template = "post.html"
time = "2021-12-08 13:09:20 -0600"
```

This is my edited notes that confirmed a decode bug that I stubled on while
doing some work for a Cortex-M55 port of Zephyr. 
In particular, the bug dealt with printing a double float "1.0" as "6.25...",
which is a tad baffling.

I debugged this by stepping trough the code in gdb, and mentally doing some
checking of the dissasembly, whith the corresponding C open in another window.

This is edited to include more context and commentary where I feelt it is
needed.

> Original notes will be indented like this

Comentary is written as normal text, and some of the headings are from the
original notes.

# Background

I was working with a bug that affected the `%f` and related float formatting
code.
An interesting property of this code, in Zephyr, is that it does all of this
formatting without using the FPU.
I think it avoids the FPU, as it's possible to run this code, and format floats,
from within the kernel, where FPU use is banned by convention.

> For reference, the IEEE 754-2008 double precision floating point format:

> ```text
> bit #
> 63_62_________51___________________________________________________0
>  | |          |       Fractional part (52 bits)                    |
>   - ---------- ----------------------------------------------------
>   ^     ^
>   |     |
>   |     +- Exponent part (11 bits)
>   |
>   +- Sign bit
> ```

I drew this diagram in my notes as I was having trouble keeping track of the
bit positions of all of the various parts of the float in my head.
Refering to this diagram whil reading the C really helped me understand it.

# Register history

When stepping through the code for 1.0, I found that the bit patter was quite
recognisable: 0x3ff_0000_0000_0000, which has a fraction of 0 and an exponent
of 1023.
This was helpful in identifying the bug, as the fractional part was all 0's.
Since the fractional part was most important in the printing routine, I traced
it's contents with gdb's `display` command.

This lead me to some strange behavior, which I noted below.

## Before 0x100019b0

> R2, Lower bits of float, containing only fractional part

> R3, higher bits containing fractional, exponent and sign parts

## After 0x100019b0

> R6, Lower bits of float, containing only fractional part

> R1, higher bits containing fractional, exponent and sign parts

# An unusal instruction

Shortly after tracking where the binary is storing the float it's printing,
I noticed that there was an instruction that was doing something strange with
the fractional part:

> `100019b4:       ea52 23cf       orrs.w  r3, r2, pc, lsl #11`

> `R3 <- R2 | (PC << 11)`

> Which for some reason includes the PC !? 
> This is a very weird thing to or into the fractional part?
> This seems to be a red herring, or at least not the most
> pressing issue, as clearing fract (backed by R3), does not
> resolve the issue.

This was not a red herring

## Another example: 

Shortly after I had noticed the weird disassembly, I noticed another instance
where PC was included as a source register of an OR instruction.

> ```
> (gdb) x/2ht 0x10001dc6
> 0x10001dc6 <cbvprintf+2542>:    1110101001010010        0000001101011111
> (gdb) x/1i 0x10001dc6
> 0x10001dc6 <cbvprintf+2542>: orrs.w  r3, r2, pc, lsr #1
> ```

## Confirming the Disassembly

Since this was affecting more than one instruction, and I was debugging why the
divide by 10 routine (called `_ldiv10`) was not dividing by ten, and messing
with the rounding needed to print, I decided that the best path forward was
checking this instruction.

Note, that I had orininally tried to do this decode with the gdb output of both
```
(gdb) x/4bt 0x10001dc6
(gdb) x/1wt 0x10001dc6
```

which stands for eXamine memory /(as) 4 Bytes (t)in binary at... and
eXamine memory /(as) 1 Word (t)in binary at...
but these did not match the manual used in aid of this decode.
Turns out arm T2 style instructions are decoded as middle endian, specifically
byte order 1032.
I did not know that before embarking on this journey

> Breaknig it up to make it easier to read
> ```
> 1110101001010010        0000001101011111
> |      | \      \      /      / |      |
> |      |  \      \    /      /  |      |
> 11101010   01010010  00000011   01011111
> | ||--| Data Processing (Shifter Register) see. C2.3.3
> |-| Is T2
> 11101010   01010010  00000011   01011111
>        |     |||--| Rn = 0010
>        |     || S bit = 1
>        |-----| op0 of section 2.3.3 = 0010, Wide shift, etc. C2.3.3.1
> 11101010   01010010  00000011   01011111
>                      | |||-| op2 = 001
>                      | || op1 = 0
>                      | op0 of section 2.3.3.1 = 0
> 11101010   01010010  00000011   01011111
>                                   |||--| op4 = 1111
>                                   || op3 = 01
>
> ```
> an abreviated version of the table from section 2.3.3.1

> ```
> |  Rn  | S | op0 | op1 | op2 | op3 |  op4  | opcode |
> -----------------------------------------------------
> |!=1111| 1 |  0  |  -  |  -  |  -  |!=11x1 | orrs   |
> | xxx0 | 1 |  0  |  -  |!=111|  01 |  1111 | lsrl   |
> ```

> So, uh, I dissagree with gdb (!?), and I think it's lsrl

This is where I start to question the tools I'm working with.
Specifically if they know about the lsrl instruction.

> Which, in the context of the rest of the program, actually makes a lot
> of sense.

> My full decode is:
> ```
> 11101010   01010010  00000011   01011111
>                | |    | || |    || imml = 01
>                | |    | ||-| RdaHi = 001 
>                | |    |-| immh = 000
>                |-| RdaLo = 001
> Hi Reg (arg/dest) = RdaHi : 1 = 0011 = R3
> Lo Reg (arg/dest) = RdaLo : 0 = 0010 = R2

> lrsl r2, r3, #1
> ```

> This second decode shows up in the inlined call to _ldiv10, C to follow:
```C
/* Division by 10 */
static void _ldiv10(uint64_t *v)
{
        *v >>= 1;
        _ldiv5(v);
}
```

Note: the above code block is from the notes, but renders poorly when in a
quoted section, so it's not indented like the rest.

> This disassembles to (the add to r6 is part of the inlining, I think):
> ```
> 10001dda:       4602            mov     r2, r0
> 10001ddc:       460b            mov     r3, r1
> 10001dde:       ea52 035f       orrs.w  r3, r2, pc, lsr #1
> 10001de2:       a80a            add     r0, sp, #40     ; 0x28
> 10001de4:       e9cd 230a       strd    r2, r3, [sp, #40]       ; 0x28
> 10001de8:       3601            adds    r6, #1
> 10001dea:       f00b f9e1       bl      1000d1b0 <_ldiv5>
> ```

> Which seems wrong to me.
> However, with my fixed dissasemble, it makes sense:
> ```
> 10001dda:       4602            mov     r2, r0
> 10001ddc:       460b            mov     r3, r1
> 10001dde:       ea52 035f       lsrl    r2, r3, #1
> 10001de2:       a80a            add     r0, sp, #40     ; 0x28
> 10001de4:       e9cd 230a       strd    r2, r3, [sp, #40]       ; 0x28
> 10001de8:       3601            adds    r6, #1
> 10001dea:       f00b f9e1       bl      1000d1b0 <_ldiv5>
> ```

> I have no idea what happened here.

## first example, again

> So I reworked the first example, instructions from bad decode to memory write:
> ```
> 100019b4 orrs.w  r3, r2, pc, lsl #11
> 100019b8 cmp.w   r9, #70 ; 0x46
> 100019bc orr.w   r6, r0, r2
> 100019c0 orr.w   r1, r3, r0, asr #31
> 100019c4 it      eq
> 100019c6 moveq.w r9, #102        ; 0x66
> 100019ca orrs    r1, r6
> 100019cc strd    r2, r3, [sp, #40]       ; 0x28
> ```
> Eliminating all instructions that don't store to R2 or R3 (the arugemnts to
> the store):
> ```
> 100019b4 orrs.w  r3, r2, pc, lsl #11
> 100019cc strd    r2, r3, [sp, #40]       ; 0x28
> ```
> Which is most of the instructions.
> R2 and R3 are both 0 before these instructions.
> after the orrs.w with a pc as a source, r3 becomes:
> ```
> 0xcdc000 = 0x100019b8 << 11 = $PC << 11
> ```

> So that makes me think it's executed as (incorrectly) written

> My decode would not have affected the value of R2 or R3

> Running a simple test of this bug through objdump shows:
> ```
>     ; cat incorrect-decode.asm
> main:
>     lsrl r2, r3, #1
>     ; $ZEPHYR_SDK_INSTALL_DIR/arm-zephyr-eabi/bin/arm-zephyr-eabi-gcc -x \
>       assembler-with-cpp -mcpu=cortex-m55 -mthumb incorrect-decode.asm  \
>       -o incorrect-decode.o -c
>     ; $ZEPHYR_SDK_INSTALL_DIR/arm-zephyr-eabi/bin/arm-zephyr-eabi-objdump \
>       -S incorrect-decode.o
>
> incorrect-decode.o:     file format elf32-littlearm
>
>
> Disassembly of section .text:
>
> 00000000 <main>:
>    0:   ea52 035f       orrs.w  r3, r2, pc, lsr #1
> ```

> unless you add `-m armv8.1-m.main`, then it shows the same `lsrl` as the source
> file.

# Epologue

So at this point I figured that it was maybe a bug in the released version of
qemu and started to test with a version built from master.

It executed the lsrl correctly. :facepalm:

Turns out that was simply a mis-decode of a MVE-specific instruction.
Further, this was fixed in upstream.