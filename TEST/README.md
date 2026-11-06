# C tests for the MPMC HLASM stack

Run these on z/OS after the assembler modules assemble and bind.
They are **AMODE 31 / ILP32 / NOXPLINK** Language Environment C programs.
They do not compile on Windows.

Assembler entries (`SINIT`, `SPUSH`, …) take **R1 -> a value parameter list**,
not LE C’s list-of-pointers. `mpmcs.c` builds the DSECT plist and calls
`MPMCSCLL` in `cglue.asm`, which tail-calls the HLASM entry with `R15` set
so `MPMCQ_ENTER` can `LR R12,R15`.

`GETVERSION` is a 10-character name: assemble GOFF and compile C with
`LONGNAME` (c89 does this by default).

## Programs (simple → harder)

| Program   | What it checks |
|-----------|----------------|
| `t01ver`  | `GETVERSION` copy + truncation RC=8 |
| `t02init` | `SINIT` eyecatcher `MPMCSTK `, `SCBSTOP` |
| `t03lifo` | Push A,B,C → pop C,B,A |
| `t04empty`| Pop empty → RC=4 |
| `t05trunc`| Short dest → RC=8, `outLen` = full length |
| `t06zero` | Zero-length message is valid |
| `t07stats`| `SSTATS` push/pop/empty/depth/payload31 |
| `t08twoq` | Two SCBs do not share nodes |
| `t09varlen` | Lengths 1..4096, bytes match on pop |
| `t10ecb`  | User ECB POSTed on push |
| `t11cb`   | Notifier TCB calls `TESTCB` |
| `t12conc` | 4×4 pthreads, 1000 messages, checksum |
| `t13pay64`| `MPMCS_OPT_PAYLOAD64` (IARV64; 1MB per push) |
| `t14add64`| `STATADD64` / `STATADD64S` / `STATMAX64` + SCB align |

Return codes: **0 = PASS**, **8 = FAIL**, **4 = SKIP** (`t13pay64` if IARV64 is denied).

## Upload

Copy to PDSs (8-character member names):

| Local file      | PDS member |
|-----------------|------------|
| `mpmcs.h`       | `Z72675.STACK.H(MPMCS)` |
| `mpmcs.c`       | `Z72675.STACK.C(MPMCS)` |
| `cglue.asm`     | `Z72675.STACK.ASM(CGLUE)` |
| `testcb.asm`    | `Z72675.STACK.ASM(TESTCB)` |
| `t01ver.c`      | `Z72675.STACK.C(T01VER)` |
| `t02init.c`     | `Z72675.STACK.C(T02INIT)` |
| `t03lifo.c`     | `Z72675.STACK.C(T03LIFO)` |
| `t04empty.c`    | `Z72675.STACK.C(T04EMPTY)` |
| `t05trunc.c`    | `Z72675.STACK.C(T05TRUNC)` |
| `t06zero.c`     | `Z72675.STACK.C(T06ZERO)` |
| `t07stats.c`    | `Z72675.STACK.C(T07STATS)` |
| `t08twoq.c`     | `Z72675.STACK.C(T08TWOQ)` |
| `t09varlen.c`   | `Z72675.STACK.C(T09VARLE)` (8-char name) |
| `t10ecb.c`      | `Z72675.STACK.C(T10ECB)` |
| `t11cb.c`       | `Z72675.STACK.C(T11CB)` |
| `t12conc.c`     | `Z72675.STACK.C(T12CONC)` |
| `t13pay64.c`    | `Z72675.STACK.C(T13PAY64)` |
| `t14add64.c`    | `Z72675.STACK.C(T14ADD64)` |
| `../src/stat64t.asm` | `Z72675.STACK.ASM(STAT64T)` |

`#include "mpmcs.h"` must resolve. In USS, keep `TEST/` as the working directory.

## USS build (recommended)

AMODE 31, no XPLINK, no LP64. Link **all** stack objects plus `cglue`.

```sh
# CGLUE / TESTCB have no COPY — do not pass -I (USS as concatenates
# -I onto CEE.SCEEMAC:SYS1.MACLIB:SYS1.MODGEN and fails if the
# first DSN cannot be allocated).
as -mgoff -o cglue.o "//'Z72675.STACK.ASM(CGLUE)'"
as -mgoff -o testcb.o "//'Z72675.STACK.ASM(TESTCB)'"

# Stack objects already in Z72675.STACK.OBJ — add those to the link.

c89 -o t01ver \
    -Wc,"NOXPLINK,RENT,LANGLVL(EXTENDED),FLOAT(IEEE)" \
    -Wl,"RENT,MAP,XREF" \
    -I. \
    t01ver.c mpmcs.c cglue.o \
    "//'Z72675.STACK.OBJ(MPMCQ)'" \
    "//'Z72675.STACK.OBJ(FREELIST)'" \
    "//'Z72675.STACK.OBJ(STORAGE)'" \
    "//'Z72675.STACK.OBJ(NOTIFY)'" \
    "//'Z72675.STACK.OBJ(STATS)'" \
    "//'Z72675.STACK.OBJ(VERSION)'"

./t01ver
```

Repeat with `t02init.c` … `t13pay64.c`. For `t11cb` also link `testcb.o`.
For `t12conc` add POSIX, for example:

```sh
c89 -o t12conc \
    -Wc,"NOXPLINK,RENT,LANGLVL(EXTENDED),FLOAT(IEEE)" \
    -Wl,"RENT" \
    -I. t12conc.c mpmcs.c cglue.o \
    "//'Z72675.STACK.OBJ(MPMCQ)'" \
    "//'Z72675.STACK.OBJ(FREELIST)'" \
    "//'Z72675.STACK.OBJ(STORAGE)'" \
    "//'Z72675.STACK.OBJ(NOTIFY)'" \
    "//'Z72675.STACK.OBJ(STATS)'" \
    "//'Z72675.STACK.OBJ(VERSION)'"
```

`t12conc.c` contains `#pragma runopts(POSIX(ON))`.

Adjust member names if your assemble job uses different ones (`MPMCQSTO`,
`MPMCQNT`, `MPMCQST`, `MPMCQVER`, …).

## Batch JCL

Submit `jcl/runtests.jcl` after the stack objects are in `Z72675.STACK.OBJ`
and the files above are uploaded (EBCDIC, FB 80).

The job assembles `CGLUE`/`TESTCB`/`STAT64T`, compiles every C module,
binds each test with the stack objects (entry **`CEESTART`**, not
`SINIT`), and runs T01VER through T14ADD64. `STAT64T` COPYs `ATOMICS`
and `REGEQUAT` from `&HLQ..STACK.MAC`.

Change the `SET` symbols at the top for HLQ, CBC/CEE dataset prefixes,
and stack OBJ member names if yours differ (`MPMCQSTO`, `MPMCQVER`, …).
You also need a PDSE load library `Z72675.STACK.LOAD`.

Look at each `GOnn.GO` step RC: **0 PASS**, **8 FAIL**, **4 SKIP** (T13
only, if IARV64 GETSTOR is denied).

## Notes

- SCB storage comes from `__malloc31` so it is below the bar.
- Default tests use **31-bit payload** (`STORAGE OBTAIN`). That is the
  warm path. `t13pay64` is separate because IARV64 GETSTOR rounds each
  payload up to 1MB.
- `t11cb` attaches a notifier TCB; always let `SCBSTOP` finish before
  freeing the SCB.
- Eyecatcher compare uses the EBCDIC literal `MPMCSTK ` produced by the
  z/OS C compiler.
