```templateinfo
title = "Notes from debugging the Zephyr string copy function"
description = "Debug notes, again"
style = "post.css"
template = "post.html"
time = "2022-01-24 10:56:09-06:00"
```

Today's bug is described in ussue 40874, and is described as:

> When I push this PR #40830 to validate string_alloc_copy() API with null parameter,
> CI got blocked. Test stucks at arch_user_string_nlen().
> It works fine on other platforms.

The platform in question is `mps2_an521_ns`, and that's something that I can setup
locally with qemu.

# Reproducing

I have some decent automation, so testing an individual test case like this is
a single command line

```bash
    ; j test-run mps2_an521_ns tests/kernel/mem_protect/syscalls/kernel.memory_protection.syscalls
python zephyr/scripts/twister -s tests/kernel/mem_protect/syscalls/kernel.memory_protection.syscalls -p mps2_an521_ns -c
ZEPHYR_BASE unset, using "/home/jimbri01/src/c/zephyr/zephyr"
Deleting output directory /home/jimbri01/src/c/zephyr/twister-out
INFO    - Zephyr version: v2.7.99-2049-g94e4a09752dc
INFO    - JOBS: 12
INFO    - Using 'zephyr' toolchain.
INFO    - Building initial testcase list...
INFO    - 1 test scenarios (1 configurations) selected, 0 configurations discarded due to filters.
INFO    - Adding tasks to the queue...
INFO    - Added initial list of jobs to queue

ERROR   - mps2_an521_ns             tests/kernel/mem_protect/syscalls/kernel.memory_protection.syscalls FAILED: Timeout
ERROR   - see: /home/jimbri01/src/c/zephyr/twister-out/mps2_an521_ns/tests/kernel/mem_protect/syscalls/kernel.memory_protection.syscalls/handler.log
INFO    - Total complete:    1/   1  100%  skipped:    0, failed:    1
INFO    - 0 of 1 test configurations passed (0.00%), 1 failed, 0 skipped with 0 warnings in 157.96 seconds
INFO    - In total 9 test cases were executed, 0 skipped on 1 out of total407 platforms (0.25%)
INFO    - 0 test configurations executed on platforms, 1 test configurations were only built.
INFO    - Saving reports...
INFO    - Writing xunit report /home/jimbri01/src/c/zephyr/twister-out/twister.xml...
INFO    - Writing xunit report /home/jimbri01/src/c/zephyr/twister-out/twister_report.xml...
INFO    - Run completed
error: Recipe `test-run` failed on line 16 with exit code 1
```

It seems to have reproduced, though it took 2.5 min :grimacing:, so now we setup
the debugger.
I also have some automation around this, so it's similarly simple:

```bash
    ; j test-dbg mps2_an521_ns tests/kernel/mem_protect/syscalls/kernel.memory_protection.syscalls
python zephyr/scripts/twister -b -c -s tests/kernel/mem_protect/syscalls/kernel.memory_protection.syscalls -p mps2_an521_ns && just _test-dbg mps2_an521_ns tests/kernel/mem_protect/syscalls/kernel.memory_protection.syscalls
ZEPHYR_BASE unset, using "/home/jimbri01/src/c/zephyr/zephyr"
Deleting output directory /home/jimbri01/src/c/zephyr/twister-out
INFO    - Zephyr version: v2.7.99-2049-g94e4a09752dc
INFO    - JOBS: 24
INFO    - Using 'zephyr' toolchain.
INFO    - Building initial testcase list...
INFO    - 1 test scenarios (1 configurations) selected, 0 configurations discarded due to filters.
INFO    - Adding tasks to the queue...
INFO    - Added initial list of jobs to queue
INFO    - Total complete:    1/   1  100%  skipped:    0, failed:    0
INFO    - 1 of 1 test configurations passed (100.00%), 0 failed, 0 skippedwith 0 warnings in 72.04 seconds
INFO    - 0 test configurations executed on platforms, 1 test configurations were only built.
INFO    - Saving reports...
INFO    - Writing xunit report /home/jimbri01/src/c/zephyr/twister-out/twister.xml...
INFO    - Writing xunit report /home/jimbri01/src/c/zephyr/twister-out/twister_report.xml...
INFO    - Run completed
The target architecture is set to "armv8.1-m.main".
add symbol table from file "twister-out/mps2_an521_ns/tests/kernel/mem_protect/syscalls/kernel.memory_protection.syscalls/zephyr/zephyr.elf"
add symbol table from file "twister-out/mps2_an521_ns/tests/kernel/mem_protect/syscalls/kernel.memory_protection.syscalls/tfm/bin/tfm_s.elf"
add symbol table from file "twister-out/mps2_an521_ns/tests/kernel/mem_protect/syscalls/kernel.memory_protection.syscalls/tfm/bin/bl2.elf"
CPU Reset (CPU 0)
R00=00000000 R01=00000000 R02=00000000 R03=00000000
R04=00000000 R05=00000000 R06=00000000 R07=00000000
R08=00000000 R09=00000000 R10=00000000 R11=00000000
R12=00000000 R13=00000000 R14=00000000 R15=00000000
XPSR=40000000 -Z-- A NS priv-thread
Invalid read at addr 0x10000000, size 4, region '(null)', reason: rejected
Invalid read at addr 0x10000004, size 4, region '(null)', reason: rejected
CPU Reset (CPU 1)
R00=00000000 R01=00000000 R02=00000000 R03=00000000
R04=00000000 R05=00000000 R06=00000000 R07=00000000
R08=00000000 R09=00000000 R10=00000000 R11=00000000
R12=00000000 R13=00000000 R14=00000000 R15=00000000
XPSR=40000000 -Z-- A NS priv-thread
Invalid read at addr 0x10000000, size 4, region '(null)', reason: rejected
Invalid read at addr 0x10000004, size 4, region '(null)', reason: rejected
qemu-system-arm: warning: nic lan9118.0 has no peer
CPU Reset (CPU 0)
R00=00000000 R01=00000000 R02=00000000 R03=00000000
R04=00000000 R05=00000000 R06=00000000 R07=00000000
R08=00000000 R09=00000000 R10=00000000 R11=00000000
R12=00000000 R13=00000000 R14=ffffffff R15=00000000
XPSR=40000000 -Z-- A S priv-thread

warning: No executable has been specified and target does not support
determining executable automatically.  Try using the "file" command.
0x10000510 in Reset_Handler ()
Breakpoint 1 at 0x1000051a (2 locations)
Breakpoint 2 at 0x1000057c (2 locations)
(gdb)
```

# Initial inspection

Let's examine the bug:

```
...really SecureFault with SFSR.AUVIOL
...taking pending secure exception 7

^C
Program received signal SIGINT, Interrupt.
0x10085e7e in SecureFault_Handler ()
(gdb) bt
Invalid read at addr 0xFFFFFFBC, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFB8, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFB8, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 2, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBA, size 2, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFB8, size 2, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 2, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBA, size 2, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFB8, size 2, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFB8, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFB8, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 4, region '(null)', reason: rejected
warning: no PSP thread stack unwinding supported.
#0  0x10085e7e in SecureFault_Handler ()
#1  <signal handler called>
Invalid read at addr 0xFFFFFFBC, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFB8, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFB8, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 2, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBA, size 2, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFB8, size 2, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 2, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBA, size 2, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFB8, size 2, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFB8, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFB8, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 4, region '(null)', reason: rejected
Invalid read at addr 0xFFFFFFBC, size 4, region '(null)', reason: rejected
warning: no PSP thread stack unwinding supported.
Backtrace stopped: previous frame identical to this frame (corrupt stack?)
(gdb)
```

Ah gdb, you seem to be failing to understand the armv8-m fault handling again.
Looks like we end up in a secure fault during this test.

## Decode the fault

Since we have a secure fault, we can decode the relevant registers to get more
details about exactly what failed.
The secure fault is not platform-specific, so we can lookup the details in
the armv8-m architecture refrence manual (arm).

In particular we look at the Secure Fault Status & Attribute Registers.

```
(gdb) x/2wt 0xe000ede4
0xe000ede4:     00000000000000000000000000001000        00000000000000000000000000000000
```

So it looks to me like we have a Attribution Unit violation fault (bit 3, set),
and the fault address is not valid (bit 6, clear).
That's less helpful that I had hoped.

# Dive deaper into the code

Let's take a break from the fault handler and narrow down the location of the
fault by stepping over and resetting.
We'll start with the test case's main:

  1) main
  2) test_main
  3) z_ztest_run_test_suite
  4) 5th involcation of run_test

Now we get to thread dispatch, which would be troublesome to step through so we
could take a look at the code that spawns the thread to find something to
put a breakpoint on that will put us in the context of the new thread:

```C
static int run_test(struct unit_test *test)
{
	int ret = TC_PASS;

	TC_START(test->name);

	if (IS_ENABLED(CONFIG_MULTITHREADING)) {
		k_thread_create(&ztest_thread, ztest_thread_stack,
				K_THREAD_STACK_SIZEOF(ztest_thread_stack),
				(k_thread_entry_t) test_cb, (struct unit_test *)test,
				NULL, NULL, CONFIG_ZTEST_THREAD_PRIORITY,
				test->thread_options | K_INHERIT_PERMS,
					K_FOREVER);

		if (test->name != NULL) {
			k_thread_name_set(&ztest_thread, test->name);
		}
		k_thread_start(&ztest_thread);
		k_thread_join(&ztest_thread, K_FOREVER);

	} else {
		test_result = 1;
		run_test_functions(test);
	}
...
```

So it looks like we could set a breakpoint at `test_cb` and get there.
However, looking at test_cb, I think we can be more specific if we are able
to decode the `struct unit_test` that we last saw before a fault.

```
(gdb)
z_ztest_run_test_suite (suite=0x28100050 <_syscalls.12+80>,
    name=0x10e414 "syscalls")
    at /home/jimbri01/src/c/zephyr/zephyr/subsys/testsuite/ztest/src/ztest.c:421
421                     fail += run_test(suite);
(gdb) n

Breakpoint 3, 0x10085e7e in SecureFault_Handler ()
(gdb) p *((struct unit_test*) 0x28100050)
$2 = {name = 0x10e451 "test_user_string_alloc_copy",
  test = 0x100d99 <test_user_string_alloc_copy>,
  setup = 0x10b64b <unit_test_noop>,
  teardown = 0x10b64b <unit_test_noop>, thread_options = 4}
(gdb)
```

so we can put a breakpoint in `test_user_string_alloc_copy`, which matches
the description of the bug.

Looks like it worked:

```
Breakpoint 7, test_user_string_alloc_copy () at /home/jimbri01/src/c/zephyr/zephyr/tests/kernel/mem_protect/syscalls/src/main.c:249
249             ret = string_alloc_copy("asdkajshdazskjdh");
(gdb) n
250             zassert_equal(ret, -2, "got %d", ret);
(gdb)
252             ret = string_alloc_copy(
(gdb)
254             zassert_equal(ret, -1, "got %d", ret);
(gdb)
256             ret = string_alloc_copy(kernel_string);
(gdb)
257             zassert_equal(ret, -1, "got %d", ret);
(gdb)
259             ret = string_alloc_copy("this is a kernel string");
(gdb)
260             zassert_equal(ret, 0, "string should have matched");
(gdb)
262             ret = string_alloc_copy(src);
(gdb)

Breakpoint 3, 0x10085e7e in SecureFault_Handler ()
(gdb) i
```

(Note: a newline without any command repeats the last command in gdb)

So it looks like we can confirm the description that the bug happens when
you try to pass an invalid pointer to `string_alloc_copy`:

```
(gdb)
262             ret = string_alloc_copy(src);
(gdb) p src
$3 = 0xffffffff <error: Cannot access memory at address 0xffffffff>
```

So let's see what happens in `string_alloc_copy`.
It's a stub, se we pass through the systemcall interface:

```
(gdb) s
string_alloc_copy (src=0xffffffff <error: Cannot access memory at address 0xffffffff>) at /home/jimbri01/src/c/zephyr/zephyr/include/syscall.h:103
103             ret = arch_is_user_context();
(gdb)
38              if (z_syscall_trap()) {
(gdb)
0x0010b6ae in z_syscall_trap ()
    at /home/jimbri01/src/c/zephyr/zephyr/include/syscall.h:103
103             ret = arch_is_user_context();
(gdb)
arch_is_user_context () at /home/jimbri01/src/c/zephyr/zephyr/include/arch/arm/aarch32/syscall.h:172
172             __asm__ volatile("mrs %0, IPSR\n\t" : "=r"(value));
(gdb)
173             if (value) {
(gdb)
178             return z_arm_thread_is_in_user_mode();
(gdb)
z_arm_thread_is_in_user_mode () at /home/jimbri01/src/c/zephyr/zephyr/arch/arm/core/aarch32/cortex_m/thread.c:15
15              value = __get_CONTROL();
(gdb)
__get_CONTROL ()
    at /home/jimbri01/src/c/zephyr/modules/hal/cmsis/CMSIS/Core/Include/cmsis_gcc.h:975
975       __ASM volatile ("MRS %0, control" : "=r" (result) );
(gdb)
z_arm_thread_is_in_user_mode () at /home/jimbri01/src/c/zephyr/zephyr/arch/arm/core/aarch32/cortex_m/thread.c:16
16              return (value & CONTROL_nPRIV_Msk) != 0;
(gdb)
string_alloc_copy (src=0xffffffff <error: Cannot access memory at address 0xffffffff>) at /home/jimbri01/src/c/zephyr/zephyr/include/syscall.h:106
106             return ret;
(gdb)
35      static inline int string_alloc_copy(char * src)
(gdb) s
string_alloc_copy (
    src=0xffffffff <error: Cannot access memory at address 0xffffffff>)
    at /home/jimbri01/src/c/zephyr/twister-out/mps2_an521_ns/tests/kernel/mem_protect/syscalls/kernel.memory_protection.syscalls/zephyr/include/generated/syscalls/test_syscalls.h:40
40                      return (int) arch_syscall_invoke1(*(uintptr_t *)&src, K_SYSCALL_STRING_ALLOC_COPY);
(gdb)
arch_syscall_invoke1 (call_id=278, arg1=4294967295)
    at /home/jimbri01/src/c/zephyr/zephyr/include/arch/arm/aarch32/syscall.h:141
141             register uint32_t ret __asm__("r0") = arg1;
(gdb)
142             register uint32_t r6 __asm__("r6") = call_id;
(gdb)
144             __asm__ volatile("svc %[svid]\n"
(gdb)
Taking exception 2 [SVC]
...taking pending nonsecure exception 11
warning: no PSP thread stack unwinding supported.
z_arm_svc () at /home/jimbri01/src/c/zephyr/zephyr/arch/arm/core/aarch32/swap_helper.S:433
```


I'm stepping one line at a time, to be sure we hit the line that causes a
fault.
I'm omitting the rest of the gdb log until I hit something relevant for
brevity.


```
z_vrfy_string_alloc_copy (
    src=0xffffffff <error: Cannot access memory at address 0xffffffff>)
    at /home/jimbri01/src/c/zephyr/zephyr/tests/kernel/mem_protect/syscalls/src/main.c:69
69              src_copy = z_user_string_alloc_copy((char *)src, BUF_SIZE);
(gdb)
z_user_string_alloc_copy (src=0xffffffff <error: Cannot access memory at address 0xffffffff>, maxlen=maxlen@entry=32) at /home/jimbri01/src/c/zephyr/zephyr/kernel/userspace.c:789

789             actual_len = z_user_string_nlen(src, maxlen, &err);
(gdb)
0x00109ce6 in z_user_string_nlen (err=<optimized out>, maxlen=<optimized out>, src=<optimized out>) at /home/jimbri01/src/c/zephyr/zephyr/include/syscall_handler.h:207
207             return arch_user_string_nlen(src, maxlen, err);
(gdb)
789             actual_len = z_user_string_nlen(src, maxlen, &err);
(gdb)
z_user_string_nlen (err=0x28104368 <priv_stacks+5064>, maxlen=32,
    src=0xffffffff <error: Cannot access memory at address 0xffffffff>)
    at /home/jimbri01/src/c/zephyr/zephyr/include/syscall_handler.h:207
207             return arch_user_string_nlen(src, maxlen, err);
(gdb)
arch_user_string_nlen () at /home/jimbri01/src/c/zephyr/zephyr/arch/arm/core/aarch32/userspace.S:695
695         push {r0, r1, r2, r4, r5, lr}
(gdb)
702         mov.w r3, #-1
(gdb)
704         str r3, [sp, #4]
(gdb)
707         movs r3, #0         /* r3 is the counter */
(gdb)
z_arm_user_string_nlen_fault_start () at /home/jimbri01/src/c/zephyr/zephyr/arch/arm/core/aarch32/userspace.S:712
712         ldrb r5, [r0, r3]
(gdb)
Taking exception 4 [Data Abort]
...really SecureFault with SFSR.AUVIOL
...taking pending secure exception 7

Breakpoint 3, 0x10085e7e in SecureFault_Handler ()
```

Alright, so we expect that faults will catch any invalid pointers here, at
the faulting line of asm:

```
strlen_loop:
z_arm_user_string_nlen_fault_start:
    /* r0 contains the string. r5 = *(r0 + r3]). This could fault. */
    ldrb r5, [r0, r3]
```

Well, that'll cause faults when passed an invalid pointer.
My hypothesis is that Zepyhr expects to be able to handle this exception,
but TF-M gets the exception.

# Testing the Hypothesis

This should be easy enough to test, as we can falsify the hypothesis by
inspecting the address of the TF-M and Zephyr fault handlers and compare
with the fault handler address.
I'm going to use nm piped to rg to handle this task:

```bash
    ; fd zephyr.elf | xargs arm-none-eabi-nm | rg SecureFault
# Nothing
```

Right, Zephyr does not have a secure fault handler, and if it did, it would
be called something like `z_arm_secure_fault`.
So we hit something called `SecureFault_Handler` at `0x10085e7e`.
Searching the tfm firmware for that symbol yeilds a hit:

```bash
    ; fd tfm_s.elf | xargs arm-none-eabi-nm | rg SecureFault
10085e7e T SecureFault_Handler
10085e7e T SecureFault_Handler
```

So it's the TF-M handler that we're hitting, which explains why we don't
have file and line number information.

# Conclusion

I think this is a much more complex problem to resolve than could be covered
in a short period of time, as correcting this would involve setting something
up to ensure that Zephyr can handle these sorts of faults.

Instead, I'm recomending that we mark all armv8-M Non-Secure, `_ns` suffix,
targets as not supporting the null checking to unblock the current PR.
Further, we should mark that this test suite should remove all targets that
have `CONFIG_NULL_POINTER_EXCEPTION_DETECTION_NONE=y`.