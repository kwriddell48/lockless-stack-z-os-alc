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

## Current design summary (matches the implemented code)

This project provides a **lock-free MPMC LIFO stack** callable from **AMODE 31** callers.

- **Caller-owned control block**: each stack instance is defined by its own **SCB** (Stack Control Block) in 31-bit addressable storage.
- **Variable-length payloads**: `SPUSH` copies bytes into internal storage; `SPOP` copies bytes out, supports truncation, and always reports the actual length.
- **Async notification**: optional user ECB POST on each successful push, and optional notifier TCB that calls a user callback EP.
- **Statistics**: low-overhead approximate counters retrievable via `SSTATS`.

## Core algorithm

- Public data structure: **Treiber MPMC stack** with a tagged **TOP** pointer `(ABA,PTR)` updated via `CDS`.
- Node reuse: internal Treiber freelist (nodes recycled; not returned to the system).
- ABA mitigation: fresh tags generated from `SCB_ABA_SEQ` (CS loop) for pointer swings.

## Public entry points and return codes

- `SINIT(SCBaddr, options, CB_EP, CB_CTX, USER_ECB)` → `RC=0`
- `SPUSH(SCBaddr, srcAddr, srcLen)` → `RC=0` success, `RC=8` allocation failure
- `SPOP(SCBaddr, dstAddr, dstMaxLen, outLenAddr)` → `RC=4` empty, `RC=0` success, `RC=8` truncated
- `SSTATS(SCBaddr, outStatsAddr, outStatsLen)` → `RC=0`
- `SCBSTOP(SCBaddr)` → `RC=0`
- `GETVERSION(outAddr, outMaxLen, outActLenAddr)` → `RC=0` or `RC=8` truncated

## Caller constraints (important)

- **SCB lifetime**: the SCB is caller-owned control-block storage and must remain allocated/valid for the full lifetime of the stack instance (from `SINIT` until you stop using that SCB with `SPUSH/SPOP/SSTATS/SCBSTOP`).
- **Multiple stacks**: you can run multiple independent stacks concurrently by allocating/initializing multiple SCBs (one SCB per stack instance).
- **Addressability**: SCB and all caller buffers/pointers passed in parm lists must be 31-bit addressable.

## Notification semantics

- **User ECB**: if `USER_ECB` is non-zero and addressable, each successful `SPUSH` does `POST ECB=(USER_ECB)`.
- **Notifier TCB**: if `CB_EP` is non-zero in `SINIT`, a notifier task is ATTACHed. Producers POST an internal ECB; the notifier WAITs and calls the callback EP with parm list `(CB_CTX, SCBaddr, PendingCount)` where `PendingCount` is computed from a sequence delta.

## Stats semantics

- Stats are approximate under concurrency; updates use CS/CDS retry loops.
- `SSTATS` copies a versioned snapshot to a caller buffer (copy length is `min(outStatsLen, statsSize)`).

## User include / headers

- `user_api.inc`: single-file user include with entry points, equates, SCB/parm-list layouts, and call examples.
- `include/mpmcs_user.h`: C header with prototypes and example call patterns.
- `include/mpmcs_user.inc`: assembler include exposing entry points and layouts (caller-facing).

