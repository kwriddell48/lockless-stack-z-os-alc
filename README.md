# Lock-free MPMC LIFO stack for z/OS (HLASM)

This repository contains a **multi-producer / multi-consumer, lock-free LIFO stack** written in **IBM z/OS High Level Assembler (HLASM)**.

It is designed to meet these requirements:

- **Callable from AMODE 31** callers (standard z/OS linkage).
- **Variable-length records** are **copied into the stack** at push time.
- Stack stores record bytes in **64-bit virtual storage** (obtained/freed with `IARV64`).
- `SPOP` **copies out** to caller buffer and returns actual length; truncation is supported.
- **Asynchronous notification** on push:
  - A single **ATTACH**ed notifier TCB calls a user exit asynchronously.
  - A user-supplied **ECB** may also be **POST**ed on each push.
  - Callback parm list is: `(CB_CTX, SCBaddr, PendingCount)`.
- **Statistics** are maintained (approximate/low-overhead) and returned via `SSTATS`.

## Entry points (planned)

- `SINIT(SCBaddr, options, CB_EP, CB_CTX, USER_ECB)`
- `SPUSH(SCBaddr, srcAddr, srcLen)`
- `SPOP(SCBaddr, dstAddr, dstMaxLen, outLenAddr)`
- `SSTATS(SCBaddr, outStatsAddr, outStatsLen)`
- `GETVERSION(outAddr, outMaxLen, outActLenAddr)` (returns assemble-time stamped build string)
- `SCBSTOP(SCBaddr)` (optional): stop notifier TCB.

## Caller includes (how to call)

- **Assembler callers**:
  - `COPY 'user_api.inc'`
  - Allocate an SCB buffer of size `SCB_SIZE` (must be 31-bit addressable).
  - Build the appropriate parameter list in 31-bit storage and call the entry point with `R1 -> parm list`.

- **C callers**:
  - Include `include/mpmcs_user.h` for prototypes and example call patterns.
  - SCB storage must still be 31-bit addressable; allocate it using your site standard.
  - The SCB is **caller-owned control-block storage** and must remain allocated/valid for the full lifetime of the stack instance (from `SINIT` until you stop using that SCB with `SPUSH/SPOP/SSTATS/SCBSTOP`).
  - Multiple independent stacks can be used concurrently by allocating/initializing **multiple SCBs** (one SCB per stack instance).

Return codes:

- `SPUSH`: `RC=0` success, `RC=8` allocation failure.
- `SPOP`: `RC=4` empty, `RC=0` success, `RC=8` truncated.

## Source layout

- `src/mpmcq_save.mac`: standard save-area enter/return helpers (RENT).
- `src/mpmcq_dsects.inc`: DSECTs for SCB, node, stats, parm lists.
- `src/mpmcq_atomics.mac`: `CS`/`CDS` retry-loop macros.
- `src/mpmcq_copy64.mac`: `SAM64`/`SAM31` wrapped copy helpers (31<->64).
- `src/mpmcq_storage.asm`: wrappers for `IARV64` obtain/free (payload) and 31-bit node storage.
- `src/mpmcq_notify.asm`: notifier TCB body + callback invocation.
- `src/mpmcq_stats.asm`: `SSTATS` implementation.
- `src/mpmcq.asm`: `SINIT/SPUSH/SPOP` core.
- `jcl/asm_lked.jcl`: sample assemble/link JCL.

## Notes

- This code assumes a z/Architecture environment where `CDS` (doubleword compare-and-swap) is available.
- Statistics are **approximate** under concurrency to keep the stack lock-free and fast.
- **Performance pools** (filled at `SINIT`): a node freelist and a fixed-size work-cell freelist so warm-path `SPUSH`/`SPOP` avoid `GETMAIN`/`FREEMAIN`. Override node prefill via `SINIT` OPTIONS **high half** (bits 0–15; 0 = default 64). Payload mode is OPTIONS bit 31 (`MPMCS_OPT_PAYLOAD64`).
- `src/mpmcq_storage.asm` contains `IARV64` macro usage; you may need to adjust the macro operands to match your z/OS level/policy (key, guard pages, etc.).

## Using the async notification

- **User callback (async execution)**:
  - Provide `CB_EP` to `SINIT` to request a notifier subtask.
  - The notifier subtask `WAIT`s on an internal ECB and calls your exit with:
    - `(CB_CTX, SCBaddr, PendingCount)`
  - `PendingCount` is computed from a sequence delta, so multiple pushes can be coalesced into one callback with `PendingCount > 1`.

- **User ECB (POST)**:
  - Provide `USER_ECB` to `SINIT`.
  - Each successful `SPUSH` will `POST` that ECB (ECB posts may naturally coalesce if already posted).

## Statistics

Call `SSTATS(SCBaddr, outStatsAddr, outStatsLen)` to copy a snapshot (see `src/mpmcq_dsects.inc` `MPMCS_STATS` DSECT).

Included counters:

- `PUSH_OK`, `POP_OK`, `POP_EMPTY`, `PUSH_ALLOC_FAIL`
- `PUSH_RETRY`, `POP_RETRY`, freelist retry counters
- `DEPTH_CUR`, `DEPTH_MAX` (best-effort)
- `PAYLOAD31_CUR`, `PAYLOAD31_MAX` (bytes in 31-bit storage)
- `PAYLOAD64_CUR`, `PAYLOAD64_MAX` (bytes in 64-bit storage)
- `POST_INTERNAL`, `POST_USERECB`, `CB_CALLS`, `CB_PENDING_MAX`

## Building on z/OS

Use the sample job in `jcl/asm_lked.jcl` as a starting point:

- Put the `.asm` modules into a source PDS (members named e.g. `MPMCQ`, `MPMCQFL`, `MPMCQSTO`, `MPMCQNT`, `MPMCQST`).
- Put the `.inc`/`.mac` files where your assembler can `COPY`/`MACRO` them (or inline them per your standards).
- Assemble each module with `ASMA90`, then link-edit with `HEWL` (RENT recommended).

