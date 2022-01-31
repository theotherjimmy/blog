```templateinfo
title = "Notes from debugging the an547 Zephyr ethernet failure"
description = "Etherenet is failing on initialization, this requires debugging TF-M, Zephyr and Qemu at the same time!"
style = "post.css"
template = "post.html"
time = "2022-01-31 14:38:48-06:00"
```

Since I debugged a PPC fault the other day, and now we don't fault.
This is great!
However, now the application, which is supposed to connect over Ethernet
to a network, simply fails to initialize the network at all.

I'm going to debug it.

# Debugger setup

The setup will be much the same as last time I debugged the PPC fault.
This time though, I'll be using my shortened commands.
This on is simplified to:

```bash
    ; j debug
[...lots of build log...]
[348/389] Linking C executable bin/bl2.axf
Memory region         Used Size  Region Size  %age Used
           FLASH:       21892 B       512 KB      4.18%
             RAM:       24384 B       512 KB      4.65%
[364/389] Linking C executable bin/tfm_s.axf
Memory region         Used Size  Region Size  %age Used
           FLASH:      135672 B     389312 B     34.85%
             RAM:       65392 B       512 KB     12.47%
         VENEERS:          64 B        832 B      7.69%
[384/389] Linking C executable bin/tfm_ns.axf
Memory region         Used Size  Region Size  %age Used
           FLASH:       10908 B       381 KB      2.80%
             RAM:       17600 B         2 MB      0.84%
[389/389] Generating tfm_s_ns_signed.bin
[1/198] Preparing syscall dependency handling

[186/196] Linking C executable zephyr/zephyr_pre0.elf

[190/196] Linking C executable zephyr/zephyr_pre1.elf

[196/196] Linking C executable zephyr/zephyr.elf
Memory region         Used Size  Region Size  %age Used
           FLASH:       91848 B       384 KB     23.36%
            SRAM:       31024 B         2 MB      1.48%
        IDT_LIST:          0 GB         2 KB      0.00%
add symbol table from file "build/mps3_an547_ns/net/dhcpv4_client/zephyr/zephyr.elf"
add symbol table from file "build/mps3_an547_ns/net/dhcpv4_client/tfm/bin/tfm_s.elf"
The target architecture is set to "armv8.1-m.main".
qemu-system-arm: warning: nic lan9118.0 has no peer

warning: No executable has been specified and target does not support
determining executable automatically.  Try using the "file" command.
Breakpoint 1 at 0x1069d60: eth_init. (2 locations)
Num     Type           Disp Enb Address    What
1       breakpoint     keep y   <MULTIPLE>
1.1                         y   0x01069d60 in eth_init
                                           at /home/jimbri01/src/c/zephyr/zephyr/drivers/ethernet/eth_smsc911x.c:663
1.2                         y   0x01069d76 in eth_init
                                           at /home/jimbri01/src/c/zephyr/zephyr/drivers/ethernet/eth_smsc911x.c:670
(gdb)
```

This is somewhat less than ideal, as I have to modify the justfile every time
I change applications that I'm debugging, but that happens infrequently enough
that it's not a big deal.

# The rest of the notes

Last time, during the PPC fault debugging, I came across two particularly
useful-looking functions: `eth_init` and then `smsc_init`.

We'll start there.

Initially it seems that the control flow looks like:
 
  1) `eth_init` calls `smsc_init`, which fails
  2) `smsc_init` calls `smsc_check_id`, which fails returning < 0
  3) `smsc_check_id` fails at it's first check, with id == 0
  
So that's what is failing, but why?

To figure that out, I tried inspecting the code to see what it's accessing.
It seems to go for the SMSC9220 global variable, which is a preprocessor
macro and is a typecast of SMSC9220_BASE, which I could not track down in
less than a minute.
Instead, I disassembled the function and looked at what the compiler decided
to access:

```
(gdb) disass
Dump of assembler code for function smsc_init:
   0x01069c80 <+0>:     movs    r3, #0
   0x01069c82 <+2>:     push    {r4, r5, lr}
   0x01069c84 <+4>:     sub     sp, #20
   0x01069c86 <+6>:     str     r3, [sp, #4]
=> 0x01069c88 <+8>:     ldr     r3, [pc, #200]  ; (0x1069d54 <smsc_init+212>)
   0x01069c8a <+10>:    ldr     r2, [r3, #80]   ; 0x50
   0x01069c8c <+12>:    uxth    r0, r2
   0x01069c8e <+14>:    cmp.w   r0, r2, lsr #16
   0x01069c92 <+18>:    mov.w   r1, r2, lsr #16
```

Ah, so the instruction I'm currently stopped at is the load of a constant.
I think that this is SMSC9220_BASE, as the second instruction loads with an
offset of 0x50, which is the ID.
Let's ask the debugger what that is:

```
(gdb) x 0x01069d54
0x1069d54 <smsc_init+212>:      0x41400000
```

Huh, I wonder what peripheral that is?
Let's look it up in the manual.
It seems to be a part of the Peripheral Expansion interface, matching my
debugging from the PPC fault earlier.
Based on the device tree, this corresponds to the eth0 peripheral.
Let's dump it and get back to the manual.

```
(gdb) p *((volatile SMSC9220_TypeDef *)0x41400000)
$3 = {RX_DATA_PORT = 0, RESERVED1 = {0, 0, 0, 0, 0, 0, 0},
  TX_DATA_PORT = 0, RESERVED2 = {0, 0, 0, 0, 0, 0, 0}, RX_STAT_PORT = 0,
  RX_STAT_PEEK = 0, TX_STAT_PORT = 0, TX_STAT_PEEK = 0, ID_REV = 0,
  IRQ_CFG = 0, INT_STS = 0, INT_EN = 0, RESERVED3 = 0, BYTE_TEST = 0,
  FIFO_INT = 0, RX_CFG = 0, TX_CFG = 0, HW_CFG = 0, RX_DP_CTRL = 0,
  RX_FIFO_INF = 0, TX_FIFO_INF = 0, PMT_CTRL = 0, GPIO_CFG = 0,
  GPT_CFG = 0, GPT_CNT = 0, RESERVED4 = 0, ENDIAN = 0, FREE_RUN = 0,
  RX_DROP = 0, MAC_CSR_CMD = 0, MAC_CSR_DATA = 0, AFC_CFG = 0,
  E2P_CMD = 0, E2P_DATA = 0}
```

So that's all zeros, which, to me, means "read as zero" memory, or a
disconnected peripheral.

I should sanity check that we're asking qemu for networking.
To do this, I'm going to shoot a fly with a bazooka by using bfptrace
to capture execve arguments and see if we're getting the SMSC9220 
enabled on the command line:

```bash
    ; sudo bpftrace -e 'tracepoint:syscalls:sys_enter_execve { join(args->argv); }'  | rg qemu
[sudo] password for jimbri01:
/nix/store/2qqjggn75hayr14wxgab106d3j347krn-Zephyr-SDK/sysroots/x86_64-pokysdk-linux/usr/bin/qemu-system-arm 
  -cpu cortex-m55 
  -machine mps3-an547 
  -nographic 
  -vga none 
  -nic user,model=lan9118, 
  -pidfile qemu.pid 
  -chardev stdio,id=con,mux=on 
  -serial chardev:con
```

So that looks okay, I suppose, though I don't know that `lan9118` and
`smsc9220` are the same thing.
I wonder what qemu thinks the memory map is?
Let's check:

```
(gdb) monitor info mtree
address-space: memory
  0000000000000000-ffffffffffffffff (prio -2, i/o): system
    0000000001000000-00000000011fffff (prio 0, i/o): tz-mpc-upstream
    0000000021000000-00000000213fffff (prio 0, ram): sram 2
    0000000028000000-00000000287fffff (prio 0, i/o): tz-mpc-upstream
    0000000040080000-0000000040080fff (prio 0, i/o): iotkit-secctl-ns-regs
    0000000041100000-0000000041100fff (prio 0, i/o): tz-ppc-port[0]
    0000000041101000-0000000041101fff (prio 0, i/o): tz-ppc-port[1]
    0000000041102000-0000000041102fff (prio 0, i/o): tz-ppc-port[2]
    0000000041103000-0000000041103fff (prio 0, i/o): tz-ppc-port[3]
    0000000041400000-00000000415fffff (prio 0, i/o): tz-ppc-port[4]
    0000000048007000-0000000048007fff (prio -1000, i/o): FPGA NS PC
    0000000048102000-0000000048102fff (prio -1000, i/o): U55 timing adapter 0
    0000000048103000-0000000048103fff (prio -1000, i/o): U55 timing adapter 1
    0000000049200000-0000000049200fff (prio 0, i/o): tz-ppc-port[0]
    0000000049201000-0000000049201fff (prio 0, i/o): tz-ppc-port[1]
    0000000049202000-0000000049202fff (prio 0, i/o): tz-ppc-port[2]
    0000000049203000-0000000049203fff (prio 0, i/o): tz-ppc-port[3]
    0000000049204000-0000000049204fff (prio 0, i/o): tz-ppc-port[4]
    0000000049205000-0000000049205fff (prio 0, i/o): tz-ppc-port[5]
    0000000049206000-0000000049206fff (prio 0, i/o): tz-ppc-port[6]
    0000000049208000-0000000049208fff (prio 0, i/o): tz-ppc-port[8]
    0000000049300000-0000000049300fff (prio 0, i/o): tz-ppc-port[0]
    0000000049301000-0000000049301fff (prio 0, i/o): tz-ppc-port[1]
    0000000049302000-0000000049302fff (prio 0, i/o): tz-ppc-port[2]
    0000000049303000-0000000049303fff (prio 0, i/o): tz-ppc-port[3]
    0000000049304000-0000000049304fff (prio 0, i/o): tz-ppc-port[4]
    0000000049305000-0000000049305fff (prio 0, i/o): tz-ppc-port[5]
    0000000049306000-0000000049306fff (prio 0, i/o): tz-ppc-port[6]
    0000000049307000-0000000049307fff (prio 0, i/o): tz-ppc-port[7]
    0000000049308000-0000000049308fff (prio 0, i/o): tz-ppc-port[8]
    000000004930a000-000000004930afff (prio 0, i/o): tz-ppc-port[10]
    000000004930b000-000000004930bfff (prio 0, i/o): tz-ppc-port[11]
    0000000050080000-0000000050080fff (prio 0, i/o): iotkit-secctl-s-regs
    0000000057000000-0000000057000fff (prio 0, i/o): tz-ppc-port[0]
    0000000057001000-0000000057001fff (prio 0, i/o): tz-ppc-port[1]
    0000000057002000-0000000057002fff (prio 0, i/o): tz-ppc-port[2]
    0000000060000000-00000000dfffffff (prio 0, i/o): tz-mpc-upstream
...
address-space: tz-ppc-port[4]
  0000000000000000-0000000000000fff (prio 0, i/o): pl022
...
address-space: tz-ppc-port[4]
  0000000000000000-0000000000000fff (prio 0, i/o): uart
...
address-space: tz-ppc-port[4]
  0000000000000000-00000000001fffff (prio 0, i/o): mps2-tz-eth-usb-container
    0000000000000000-00000000000000ff (prio 0, i/o): lan9118-mmio
    0000000000100000-00000000001fffff (prio 0, i/o): usb-otg
```

So that's a tad confusing.
I wonder which one it is.
At the very least, we can dump the SMSC9220 struct as if it were at the other
addresses:

```
(gdb)  p *((volatile SMSC9220_TypeDef *)0x49204000)
$2 = {RX_DATA_PORT = 0, RESERVED1 = {0, 0, 0, 0, 0, 0, 0},
  TX_DATA_PORT = 0, RESERVED2 = {0, 0, 0, 0, 0, 0, 0}, RX_STAT_PORT = 0,
  RX_STAT_PEEK = 0, TX_STAT_PORT = 0, TX_STAT_PEEK = 0, ID_REV = 0,
  IRQ_CFG = 0, INT_STS = 0, INT_EN = 0, RESERVED3 = 0, BYTE_TEST = 0,
  FIFO_INT = 0, RX_CFG = 0, TX_CFG = 0, HW_CFG = 0, RX_DP_CTRL = 0,
  RX_FIFO_INF = 0, TX_FIFO_INF = 0, PMT_CTRL = 0, GPIO_CFG = 0,
  GPT_CFG = 0, GPT_CNT = 0, RESERVED4 = 0, ENDIAN = 0, FREE_RUN = 0,
  RX_DROP = 0, MAC_CSR_CMD = 0, MAC_CSR_DATA = 0, AFC_CFG = 0,
  E2P_CMD = 0, E2P_DATA = 0}
(gdb)  p *((volatile SMSC9220_TypeDef *)0x49304000)
$3 = {RX_DATA_PORT = 0, RESERVED1 = {0, 3, 0, 217, 0, 0, 0},
  TX_DATA_PORT = 0, RESERVED2 = {0, 0, 0, 0, 0, 0, 0}, RX_STAT_PORT = 0,
  RX_STAT_PEEK = 0, TX_STAT_PORT = 0, TX_STAT_PEEK = 0, ID_REV = 0,
  IRQ_CFG = 0, INT_STS = 0, INT_EN = 0, RESERVED3 = 0, BYTE_TEST = 0,
  FIFO_INT = 0, RX_CFG = 0, TX_CFG = 0, HW_CFG = 0, RX_DP_CTRL = 0,
  RX_FIFO_INF = 0, TX_FIFO_INF = 0, PMT_CTRL = 0, GPIO_CFG = 0,
  GPT_CFG = 0, GPT_CNT = 0, RESERVED4 = 0, ENDIAN = 0, FREE_RUN = 0,
  RX_DROP = 0, MAC_CSR_CMD = 0, MAC_CSR_DATA = 0, AFC_CFG = 0,
  E2P_CMD = 0, E2P_DATA = 0}
(gdb)
```

Hm... also ID == 0 on both of them.
According to the device tree, they should be i2c_shield 1 and UART 1,
respectively.

Let's check with the secure mode alias:

```
(gdb)  p *((volatile SMSC9220_TypeDef *)0x59204000)
$4 = {RX_DATA_PORT = 0, RESERVED1 = {0, 0, 3, 0, 0, 8, 0},
  TX_DATA_PORT = 0, RESERVED2 = {0, 0, 0, 0, 0, 0, 0}, RX_STAT_PORT = 0,
  RX_STAT_PEEK = 0, TX_STAT_PORT = 0, TX_STAT_PEEK = 0, ID_REV = 0,
  IRQ_CFG = 0, INT_STS = 0, INT_EN = 0, RESERVED3 = 0, BYTE_TEST = 0,
  FIFO_INT = 0, RX_CFG = 0, TX_CFG = 0, HW_CFG = 0, RX_DP_CTRL = 0,
  RX_FIFO_INF = 0, TX_FIFO_INF = 0, PMT_CTRL = 0, GPIO_CFG = 0,
  GPT_CFG = 0, GPT_CNT = 0, RESERVED4 = 0, ENDIAN = 0, FREE_RUN = 0,
  RX_DROP = 0, MAC_CSR_CMD = 0, MAC_CSR_DATA = 0, AFC_CFG = 0,
  E2P_CMD = 0, E2P_DATA = 0}
(gdb)  p *((volatile SMSC9220_TypeDef *)0x59304000)
$5 = {RX_DATA_PORT = 0, RESERVED1 = {0, 0, 0, 0, 0, 0, 0},
  TX_DATA_PORT = 0, RESERVED2 = {0, 0, 0, 0, 0, 0, 0}, RX_STAT_PORT = 0,
  RX_STAT_PEEK = 0, TX_STAT_PORT = 0, TX_STAT_PEEK = 0, ID_REV = 0,
  IRQ_CFG = 0, INT_STS = 0, INT_EN = 0, RESERVED3 = 0, BYTE_TEST = 0,
  FIFO_INT = 0, RX_CFG = 0, TX_CFG = 0, HW_CFG = 0, RX_DP_CTRL = 0,
  RX_FIFO_INF = 0, TX_FIFO_INF = 0, PMT_CTRL = 0, GPIO_CFG = 0,
  GPT_CFG = 0, GPT_CNT = 0, RESERVED4 = 0, ENDIAN = 0, FREE_RUN = 0,
  RX_DROP = 0, MAC_CSR_CMD = 0, MAC_CSR_DATA = 0, AFC_CFG = 0,
  E2P_CMD = 0, E2P_DATA = 0}
(gdb)  p *((volatile SMSC9220_TypeDef *)0x51400000)
$6 = {RX_DATA_PORT = 0, RESERVED1 = {0, 0, 0, 0, 0, 0, 0},
  TX_DATA_PORT = 0, RESERVED2 = {0, 0, 0, 0, 0, 0, 0}, RX_STAT_PORT = 0,
  RX_STAT_PEEK = 0, TX_STAT_PORT = 0, TX_STAT_PEEK = 0,
  ID_REV = 18350081, IRQ_CFG = 0, INT_STS = 16384, INT_EN = 0,
  RESERVED3 = 0, BYTE_TEST = 2271560481, FIFO_INT = 1207959552,
  RX_CFG = 0, TX_CFG = 0, HW_CFG = 327684, RX_DP_CTRL = 0,
  RX_FIFO_INF = 0, TX_FIFO_INF = 4608, PMT_CTRL = 1, GPIO_CFG = 0,
  GPT_CFG = 65535, GPT_CNT = 65535, RESERVED4 = 0, ENDIAN = 0,
  FREE_RUN = 0, RX_DROP = 0, MAC_CSR_CMD = 0, MAC_CSR_DATA = 0,
  AFC_CFG = 0, E2P_CMD = 256, E2P_DATA = 0}
```

Hm... Yeah that last one looks good.
Not only is it the correct address, with a secure-mode alias, but it also
seems to have an ID.
So, we probably have to revisit my prior patch that allows access to
this peripheral.

It's time to dive into the TF-M code to figure out what's causing the 
read as zero behavior.
When I do this, I like to have a monitor dedicated to these notes and the
manual, and another monitor with the debugger and two editor windows with
various bits of code that I'm reading open.
The notes and manual are on a vertical monitor.

I'm examining the bits of configuration used by using gdb as if it were
ctags to tell me about types, mostly because it's more convenient than
setting up a ctags setup that spans mcuboot, tf-m and zephyr.
For example, I looked up the struct that points to the registers of the
PPC peripheral expansion block 0 by:

```
(gdb) p &PPC_SSE300_PERIPH_EXP0_DATA_S
$6 = (struct ppc_sse300_dev_data_t *) 0x3000fefc <PPC_SSE300_PERIPH_EXP0_DATA_S>
(gdb) info types ppc_sse300_dev_data_t
All types matching regular expression "ppc_sse300_dev_data_t":

File /home/jimbri01/src/c/zephyr/modules/tee/tf-m/trusted-firmware-m/platform/ext/target/arm/mps3/an547/native_drivers/ppc_sse300_drv.h:
56:     struct ppc_sse300_dev_data_t;
```

Which works well enough for this sort of code spelunking.
This gives me context (code comments) for dump of this struct:

```c
/* SSE-300 PPC device data structure */
struct ppc_sse300_dev_data_t {
    volatile uint32_t* sacfg_ns_ppc;   /*!< Pointer to non-secure register */
    volatile uint32_t* sacfg_sp_ppc;   /*!< Pointer to secure unprivileged
                                             register */
    volatile uint32_t* nsacfg_nsp_ppc; /*!< Pointer to non-secure unprivileged
                                             register */
    uint32_t int_bit_mask;              /*!< Interrupt bit mask */
    bool is_initialized;                /*!< Indicates if the PPC driver
                                             is initialized */
};
```

and the dump:

```
$7 = {sacfg_ns_ppc = 0x50080080, sacfg_sp_ppc = 0x500800c0,
  nsacfg_nsp_ppc = 0x400800c0, int_bit_mask = 16, is_initialized = true}
```

My reading of the TRM indicates that the following register configuration
should allow both secure and non-secure access.
However, it seems that qemu is emulating this as a read as zero situation:

```
 (gdb) p *PPC_SSE300_PERIPH_EXP0_DATA_S.sacfg_ns_ppc
$2 = 1
(gdb) p *PPC_SSE300_PERIPH_EXP0_DATA_S.sacfg_sp_ppc
$3 = 1
(gdb) p *PPC_SSE300_PERIPH_EXP0_DATA_S.nsacfg_nsp_ppc
$4 = 1
(gdb)  p *((volatile SMSC9220_TypeDef *)0x51400000)
$5 = {RX_DATA_PORT = 0, RESERVED1 = {0, 0, 0, 0, 0, 0, 0},
  TX_DATA_PORT = 0, RESERVED2 = {0, 0, 0, 0, 0, 0, 0}, RX_STAT_PORT = 0,
  RX_STAT_PEEK = 0, TX_STAT_PORT = 0, TX_STAT_PEEK = 0,
  ID_REV = 18350081, IRQ_CFG = 0, INT_STS = 16384, INT_EN = 0,
  RESERVED3 = 0, BYTE_TEST = 2271560481, FIFO_INT = 1207959552,
  RX_CFG = 0, TX_CFG = 0, HW_CFG = 327684, RX_DP_CTRL = 0,
  RX_FIFO_INF = 0, TX_FIFO_INF = 4608, PMT_CTRL = 1, GPIO_CFG = 0,
  GPT_CFG = 65535, GPT_CNT = 65535, RESERVED4 = 0, ENDIAN = 0,
  FREE_RUN = 1792732, RX_DROP = 0, MAC_CSR_CMD = 0, MAC_CSR_DATA = 0,
  AFC_CFG = 0, E2P_CMD = 256, E2P_DATA = 0}
(gdb)  p *((volatile SMSC9220_TypeDef *)0x41400000)
$6 = {RX_DATA_PORT = 0, RESERVED1 = {0, 0, 0, 0, 0, 0, 0},
  TX_DATA_PORT = 0, RESERVED2 = {0, 0, 0, 0, 0, 0, 0}, RX_STAT_PORT = 0,
  RX_STAT_PEEK = 0, TX_STAT_PORT = 0, TX_STAT_PEEK = 0, ID_REV = 0,
  IRQ_CFG = 0, INT_STS = 0, INT_EN = 0, RESERVED3 = 0, BYTE_TEST = 0,
  FIFO_INT = 0, RX_CFG = 0, TX_CFG = 0, HW_CFG = 0, RX_DP_CTRL = 0,
  RX_FIFO_INF = 0, TX_FIFO_INF = 0, PMT_CTRL = 0, GPIO_CFG = 0,
  GPT_CFG = 0, GPT_CNT = 0, RESERVED4 = 0, ENDIAN = 0, FREE_RUN = 0,
  RX_DROP = 0, MAC_CSR_CMD = 0, MAC_CSR_DATA = 0, AFC_CFG = 0,
  E2P_CMD = 0, E2P_DATA = 0}
```

So it's time to connect to qemu with gdb at the same time as we debug the
application hosted in qemu.
This can be a bit confusing, because if the host is stopped, the guests
debugger is unresponsive.
It's actually pretty simple to setup.
With the guest already in the debugger, I open another terminal and run:

```bash
    ; gdb -p $(pgrep qemu)
Attaching to process 1317407
[New LWP 1317408]
[New LWP 1317409]
[Thread debugging using libthread_db enabled]
Using host libthread_db library "/nix/store/563528481rvhc5kxwipjmg6rqrl95mdx-glibc-2.33-56/lib/libthread_db.so.1".
0x00007f5f516fd482 in ppoll () from /nix/store/mij848h2x5wiqkwhg027byvmf9x3gx7y-glibc-2.33-50/lib/libc.so.6
warning: File "/nix/store/7fv9v6mnlkb4ddf9kz1snknbvbfbcbx0-gcc-10.3.0-lib/lib/libstdc++.so.6.0.28-gdb.py" auto-loading has been declined by your `auto-load safe-path' set to "$debugdir:$datadir/auto-load:/nix/store/2nkjrh3za68vrw6kf8lxn6nq1dval05v-gcc-10.3.0-lib".
To enable execution of this file add
        add-auto-load-safe-path /nix/store/7fv9v6mnlkb4ddf9kz1snknbvbfbcbx0-gcc-10.3.0-lib/lib/libstdc++.so.6.0.28-gdb.py
line to your configuration file "/home/jimbri01/.config/gdb/gdbinit".
To completely disable this security protection add
        set auto-load safe-path /
line to your configuration file "/home/jimbri01/.config/gdb/gdbinit".
For more information about this security protection see the
"Auto-loading safe path" section in the GDB manual.  E.g., run from the shell:
        info "(gdb)Auto-loading safe path"
(gdb)
```

Now I have to be sure that this debugger is running it's target before I
interact with the guest debugger at all.

As a baseline, I've put a breakpoint in the `lan9118_readh` and
`lan9118_readw` functions and I've dumped the secure-mode address of the
peripheral in gdb.

Amusingly, guest gdb gets an error during the dump, but host gdb hits the
`lan9118_readl` breakpoint.
I tried reading from the non-secure address and, well no breakpoint is hit
in host gdb.
So we know that qemu does not try to read from the LAN9118 when reading
from the non-secure address.
Time to find the point in qemu where it handles the alias and put a
breakpoint there.

The appropriate function is `tz_ppc_read`, which handles reads that are 
behind a Peripheral Protection Controller (PPC).
The relevant bits of the function:

```c
static MemTxResult tz_ppc_read(void *opaque, hwaddr addr, uint64_t *pdata,
                               unsigned size, MemTxAttrs attrs)
{
    TZPPCPort *p = opaque;
    TZPPC *s = p->ppc;
    int n = p - s->port;
    AddressSpace *as = &p->downstream_as;
    uint64_t data;
    MemTxResult res;

    if (!tz_ppc_check(s, n, attrs)) {
        trace_tz_ppc_read_blocked(n, addr, attrs.secure, attrs.user);
        if (s->cfg_sec_resp) {
            return MEMTX_ERROR;
        } else {
            *pdata = 0;
            return MEMTX_OK;
        }
    }
    
```

and when I access it from the NS-address:

```c
Thread 1 "qemu-system-arm" hit Breakpoint 3, tz_ppc_read (opaque=0x7f5f50c76640, addr=0, pdata=0x7ffe6ecdc848, size=4, attrs=...) at ../hw/misc/tz-ppc.c:107
107     {
(gdb) n
110         int n = p - s->port;
(gdb)
115         if (!tz_ppc_check(s, n, attrs)) {
(gdb)
116             trace_tz_ppc_read_blocked(n, addr, attrs.secure, attrs.user);
(gdb)
117             if (s->cfg_sec_resp) {
(gdb)
120                 *pdata = 0;
(gdb)
121                 return MEMTX_OK;
(gdb)
```

So it really is read-as-zero here, intentionally.
I'll re-run the gdb print and step into the `tz_ppc_check` function.

I stepped into `tz_ppc_check` and tested all of the conditionals that
determine if a read is denied.
It seems that the register `cfg_ap` is not setup correctly and reads as all
zero:

```
(gdb) p s->cfg_ap
$8 = {false <repeats 16 times>}
(gdb) p s->cfg_ap[n]
$9 = false
```

Since there's a `tz_ppc_cfg_ap` function in the same file, I'm going to put
a breakpoint there.

Huh, so we're not configuring `cfg_ap[4]`, and it defaults to zero.
We should inspect the TF-M code to see exactly how it's writing to the
PPC registers.
It really feels like we're reverse engineering an understanding of the PPC
and the TF-M code that drives it.

It seems like the writes to `sacfg_ns_ppc` trigger the `tz_ppc_cfg_ap`
breakpoints, implying that those writes control if the non-secure state
has access to a peripheral, or it reads as zeros.

Strangely, it seems that level (the argument to `tz_ppc_cfg_ap`) is zero
even when the mask in TF-M (the local variable that enables a given
peripheral) is non-zero.
Tracing through the code, it looks like the `ppc->ns` register muxes
between the `ppc->nsp` and `ppc->sp` registers, and the `mask` writes
to the `ppc->ns` register.
I wonder what writes to the two registers it muxes.

So I hit the breakpoint in qemu, and decided to hit C-c in the guest
debugger.

Tracing through the code, it's looking like I need to setup the peripheral
PPC EXP0 with `(1 << 4)`, because that's what accessing the LAN9118 peripheral
generates.

This might work, but qemu seems to ignore all bits above bit 2.
It seems that this is because the ports after port index 2 are null:

```c
(gdb) p ppc->numports
$7 = 16
(gdb) l
266
267     static void iotkit_secctl_update_ppc_ap(IoTKitSecCtlPPC *ppc)
268     {
269         int i;
270
271         for (i = 0; i < ppc->numports; i++) {
272             bool v;
273
274             if (extract32(ppc->ns, i, 1)) {
275                 v = extract32(ppc->nsp, i, 1);
(gdb)
276             } else {
277                 v = extract32(ppc->sp, i, 1);
278             }
279             qemu_set_irq(ppc->ap[i], v);
280         }
281     }
282
283     static void iotkit_secctl_ppc_ns_write(IoTKitSecCtlPPC *ppc, uint32_t value)
284     {
285         int i;
(gdb) p ppc->ap
$8 = {0x5567c93b63e0, 0x5567c93b5f70, 0x5567c93b5f20, 0x0 <repeats 13 times>}
```

That's troublesome, I need to access port 4.

Let's put a breakpoint in the initialization and step through it to see
what's going going on there.
Well, it's not triggered by a `monitor system_reset` command, so we're going
to have to startup qemu while it's being debugged by gdb.
I wrote another gdb-script in my justfile for this purpose:

```
debug-qemu: (an547 debug-sample extra-config)
    #!/usr/bin/env -S gdb {{qemu-bin}} -q -x 
    break main
    run {{qemu-flags}} {{qemu-stdio}}
```

Debugging the startup led me nowhere.
Instead, I stepped back through the code and looked through the device
specific initialization code.
I found something interesting:

```c
    const PPCInfo an547_ppcs[] = { {
            .name = "apb_ppcexp0",
            .ports = {
                { "ssram-mpc", make_mpc, &mms->mpc[0], 0x57000000, 0x1000 },
                { "qspi-mpc", make_mpc, &mms->mpc[1], 0x57001000, 0x1000 },
                { "ddr-mpc", make_mpc, &mms->mpc[2], 0x57002000, 0x1000 },
            },
        }, {
            .name = "apb_ppcexp1",
            .ports = {
                { "i2c0", make_i2c, &mms->i2c[0], 0x49200000, 0x1000, {},
                  { .i2c_internal = true /* touchscreen */ } },
                { "i2c1", make_i2c, &mms->i2c[1], 0x49201000, 0x1000, {},
                  { .i2c_internal = true /* audio conf */ } },
                { "spi0", make_spi, &mms->spi[0], 0x49202000, 0x1000, { 53 } },
                { "spi1", make_spi, &mms->spi[1], 0x49203000, 0x1000, { 54 } },
                { "spi2", make_spi, &mms->spi[2], 0x49204000, 0x1000, { 55 } },
                { "i2c2", make_i2c, &mms->i2c[2], 0x49205000, 0x1000, {},
                  { .i2c_internal = false /* shield 0 */ } },
                { "i2c3", make_i2c, &mms->i2c[3], 0x49206000, 0x1000, {},
                  { .i2c_internal = false /* shield 1 */ } },
                { /* port 7 reserved */ },
                { "i2c4", make_i2c, &mms->i2c[4], 0x49208000, 0x1000, {},
                  { .i2c_internal = true /* DDR4 EEPROM */ } },
            },
        }, {
            .name = "apb_ppcexp2",
            .ports = {
                { "scc", make_scc, &mms->scc, 0x49300000, 0x1000 },
                { "i2s-audio", make_unimp_dev, &mms->i2s_audio, 0x49301000, 0x1000 },
                { "fpgaio", make_fpgaio, &mms->fpgaio, 0x49302000, 0x1000 },
                { "uart0", make_uart, &mms->uart[0], 0x49303000, 0x1000, { 33, 34, 43 } },
                { "uart1", make_uart, &mms->uart[1], 0x49304000, 0x1000, { 35, 36, 44 } },
                { "uart2", make_uart, &mms->uart[2], 0x49305000, 0x1000, { 37, 38, 45 } },
                { "uart3", make_uart, &mms->uart[3], 0x49306000, 0x1000, { 39, 40, 46 } },
                { "uart4", make_uart, &mms->uart[4], 0x49307000, 0x1000, { 41, 42, 47 } },
                { "uart5", make_uart, &mms->uart[5], 0x49308000, 0x1000, { 125, 126, 127 } },

                { /* port 9 reserved */ },
                { "clcd", make_unimp_dev, &mms->cldc, 0x4930a000, 0x1000 },
                { "rtc", make_rtc, &mms->rtc, 0x4930b000, 0x1000 },
            },
        }, {
            .name = "ahb_ppcexp0",
            .ports = {
                { "gpio0", make_unimp_dev, &mms->gpio[0], 0x41100000, 0x1000 },
                { "gpio1", make_unimp_dev, &mms->gpio[1], 0x41101000, 0x1000 },
                { "gpio2", make_unimp_dev, &mms->gpio[2], 0x41102000, 0x1000 },
                { "gpio3", make_unimp_dev, &mms->gpio[3], 0x41103000, 0x1000 },
                { "eth-usb", make_eth_usb, NULL, 0x41400000, 0x200000, { 49 } },
            },
        },
    };
```

The part I found interesting is that there are 3 aps in the registers
and it must be the first one.
However, the peripherals we're accessing are on the last one.
That seems incorrect.

I switched them, rebuilt qemu and re-ran the test.
No more SMSC911x failed to initialize messages!

The patch I applied is:

```diff
From bc9fe9c5bf6a3b90c96480e38f93a7eaba723905 Mon Sep 17 00:00:00 2001
From: Jimmy Brisson <jimmy.brisson@linaro.org>
Date: Mon, 31 Jan 2022 14:21:16 -0600
Subject: [PATCH] an547: Correct typo that swaps ahb and apb peripherals

Turns out that this manifests in being unable to configure
the ethernet access permissions, as the IotKitPPC looks
these up by name.

With this fix, eth is configurable
---
 hw/arm/mps2-tz.c | 4 ++--
 1 file changed, 2 insertions(+), 2 deletions(-)

diff --git a/hw/arm/mps2-tz.c b/hw/arm/mps2-tz.c
index f40e854dec..3c6456762a 100644
--- a/hw/arm/mps2-tz.c
+++ b/hw/arm/mps2-tz.c
@@ -1030,7 +1030,7 @@ static void mps2tz_common_init(MachineState *machine)
     };
 
     const PPCInfo an547_ppcs[] = { {
-            .name = "apb_ppcexp0",
+            .name = "ahb_ppcexp0",
             .ports = {
                 { "ssram-mpc", make_mpc, &mms->mpc[0], 0x57000000, 0x1000 },
                 { "qspi-mpc", make_mpc, &mms->mpc[1], 0x57001000, 0x1000 },
@@ -1072,7 +1072,7 @@ static void mps2tz_common_init(MachineState *machine)
                 { "rtc", make_rtc, &mms->rtc, 0x4930b000, 0x1000 },
             },
         }, {
-            .name = "ahb_ppcexp0",
+            .name = "apb_ppcexp0",
             .ports = {
                 { "gpio0", make_unimp_dev, &mms->gpio[0], 0x41100000, 0x1000 },
                 { "gpio1", make_unimp_dev, &mms->gpio[1], 0x41101000, 0x1000 },
-- 
2.33.1
```

Unlike last time, this is not fixed on master!
Further, it was probably a typo, and it feels like that was a lot of work
to fix a typo.