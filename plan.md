---
name: IBMZ_lockfree_stack_full_feature_stats
overview: Implement an AMODE-31-callable lock-free MPMC LIFO stack with variable-length messages stored in 64-bit storage, async ATTACH callback + user ECB posting on push, and a low-overhead statistics subsystem retrievable via SSTATS.
todos:
  - id: dsects-api-stats
    content: Define SCB/node/stats DSECTs, finalize calling conventions for SINIT/SPUSH/SPOP/SSTATS, and document approximate-stat semantics.
    status: completed
  - id: atomics-stack
    content: Implement DCAS/tagged-pointer stack + freelist, and add retry counters in CAS loops.
    status: completed
  - id: payload64-copy
    content: Implement IARV64 allocation/free and SAM64-wrapped copies; update 64-bit byte-usage stats (cur/max).
    status: completed
  - id: notify
    content: Implement notifier TCB + callback invocation with context; post internal/user ECBs; add notification stats.
    status: completed
  - id: qstats
    content: Implement SSTATS snapshot routine and versioned stats layout.
    status: completed
  - id: docs-jcl
    content: Write README and sample JCL build steps including how to use monitoring stats.
    status: completed
---

# Lock-free MPMC LIFO stack + async notify + stats (HLASM, callable AMODE 31)

## Goal

Deliver a **lock-free MPMC FIFO** in **z/OS HLASM** that:

- Is **callable from AMODE 31**
- **Copies variable-length data into the stack**; message bytes are stored in **64-bit virtual storage**
- `SPOP` **copies out** into caller buffer and frees payload storage
- Provides async notification:
- **ATTACHed notifier TCB** calls a user callback asynchronously
- Optional **user-provided ECB** is POSTed on every successful push
- Exposes **low-overhead (approximate) runtime statistics** via a `SSTATS` snapshot routine

## Core stack algorithm

- Michael-Scott MPMC FIFO with counted pointers updated via **`CDS`** (doubleword CAS) and refcount-based reclamation so nodes can be safely reused without thread registration.
- **QCB + nodes in 31-bit storage**, payload bytes in **64-bit storage** via `IARV64`.

## Variable-length payload semantics

- `SPUSH(SCB, srcAddr, srcLen)`: allocates payload (`IARV64` in 64-bit mode), copies in, and pushes node containing `(payload64Addr, payloadLen)`.
- `SPOP(SCB, dstAddr, dstMaxLen, outLenAddr)`:
- RC=4 empty
- RC=0 copied full message
- RC=8 truncated (copied `dstMaxLen`, but `*outLen=actualLen`)
- frees 64-bit payload + recycles node.

## Notifications

### Async callback on separate TCB

- One notifier TCB is created once (via `ATTACH`). Producers never run user code.
- Callback parm list order (R1->list): **`(CB_CTX, QCBaddr, PendingCount)`**.
- `SPUSH` increments `PUSH_SEQ` and `POST`s internal ECB to wake notifier.

### User ECB notify

- Optional `USER_ECB` in SCB; `SPUSH` does `POST USER_ECB` on every successful push.

## Statistics (approximate, low overhead)

### Principles

- Stats are **approximate** under concurrency (monotonic counters; current-size is best-effort).
- Updates use **`CS` loops** (fullword) or **`CDS`** for paired updates only where needed.
- `SSTATS` provides a consistent-enough snapshot by copying fields (no global lock).

### Stats to maintain (QCB fields)

Counters are suggested as **fullword** unless noted.

- **Push/pop activity**
- `STAT_PUSH_OK`
- `STAT_POP_OK`
- `STAT_POP_EMPTY` (how often consumers found empty)
- `STAT_PUSH_ALLOC_FAIL` (IARV64 obtain failed)
- **Retry/contended-path visibility**
- `STAT_PUSH_RETRY` (CAS loops / retry visibility)
- `STAT_POP_RETRY`
- `STAT_FREELIST_POP_RETRY` / `STAT_FREELIST_PUSH_RETRY`
- **Depth (best-effort)**
- `STAT_DEPTH_CUR` (signed fullword; increment after successful push, decrement after successful pop)
- `STAT_QDEPTH_MAX` (max observed; update via CS loop when `CUR` exceeds)
- **64-bit storage usage** (doubleword counters)
- `STAT_PAYLOAD64_CUR` (bytes currently allocated for pushed payloads)
- `STAT_PAYLOAD64_MAX` (max observed)
- Optional: `STAT_PAYLOAD64_ALLOC` (total bytes ever obtained) / `STAT_PAYLOAD64_FREE`
- **Notification activity**
- `STAT_POST_INTERNAL` (internal ECB posts)
- `STAT_POST_USERECB`
- `STAT_CB_CALLS`
- `STAT_CB_PENDING_MAX` (largest `PendingCount` ever delivered)

### Stats retrieval API

- `SSTATS(SCBaddr, outStatsAddr, outStatsLen)`
- Copies a packed stats DSECT to caller.
- `outStatsLen` allows versioning/forward compatibility.

## Entry points

- `SINIT(SCBaddr, options, CB_EP, CB_CTX, USER_ECB)`
- `SPUSH(SCBaddr, srcAddr, srcLen)`
- `SPOP(SCBaddr, dstAddr, dstMaxLen, outLenAddr)`
- `SSTATS(SCBaddr, outStatsAddr, outStatsLen)`
- `SCBSTOP(SCBaddr)` optional

## Files to add

- [README.md](README.md)
- [src/mpmcq_dsects.inc](src/mpmcq_dsects.inc) (QCB/node + stats DSECT)
- [src/mpmcq_atomics.mac](src/mpmcq_atomics.mac)
- [src/mpmcq_copy64.mac](src/mpmcq_copy64.mac)
- [src/mpmcq_storage.asm](src/mpmcq_storage.asm)
- [src/mpmcq_notify.asm](src/mpmcq_notify.asm)
- [src/mpmcq_stats.asm](src/mpmcq_stats.asm) (`SSTATS`, helper macros for counter increments/max)
- [src/mpmcq.asm](src/mpmcq.asm)
- [jcl/asm_lked.jcl](jcl/asm_lked.jcl)

## Acceptance criteria

- FIFO correctness under MPMC.
- Varlen copy-in/out correctness, including truncation return codes.
- Async callback executes on notifier TCB and receives correct `(CB_CTX, QCB, PendingCount)`.
- User ECB POSTed on every push.
- Stats counters move as expected; `SSTATS` returns a coherent snapshot suitable for monitoring.

