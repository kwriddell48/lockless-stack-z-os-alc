### Overview

This project implements a **multi-producer / multi-consumer (MPMC), lock-free LIFO stack** in **z/OS HLASM**, callable from **AMODE 31** callers while storing variable-length payloads in **64-bit virtual storage**.

High-level properties:

- **Producers** call `SPUSH` to copy variable-length data into the stack.
- **Consumers** call `SPOP` to copy data out (with truncation support).
- **Nodes** live in **31-bit storage** (fast pointer/CAS operations).
- **Payload bytes** live in **31-bit storage by default**, with an **optional 64-bit storage mode**.
- **Asynchronous notification** is supported:
  - internal notifier ECB + optional notifier TCB callback
  - optional user-provided ECB posted on each successful push
- **Statistics** are maintained (approximate under concurrency) and returned via `SSTATS`.
- Code is intended to be **RENT/reentrant** (no writable static work areas).
- Modules are constrained to z/Architecture via `OPTABLE ZOP`.

---

### File / module map

- **`src/mpmcq.asm`**
  - **Public**: `SINIT`, `SPUSH`, `SPOP`
  - Treiber stack operations + notification posts.

- **`src/mpmcq_freelist.asm`**
  - **Internal**: `MPMCS_POPNODE`, `MPMCS_PUSHNODE`
  - Treiber stack used as a node pool (nodes are recycled, not returned to the system).

- **`src/mpmcq_storage.asm`**
  - **Internal**: `MPMCS_PAYGET`, `MPMCS_PAYFREE`
  - 64-bit payload allocation/free via `IARV64` using per-call MF=(E,workarea) parameter lists.

- **`src/mpmcq_copy64.mac`**
  - Macros that wrap `SAM64`/`SAM31` around `MVCL` for 31↔64 copies.

- **`src/mpmcq_notify.asm`**
  - **Public**: `SCBSTOP`
  - **Internal**: `MPMCS_NSTART`, `MPMCS_NOTIF`
  - Optional notifier TCB that `WAIT`s on an internal ECB and calls a user callback asynchronously.

- **`src/mpmcq_stats.asm`**
  - **Public**: `SSTATS`
  - Copies a versioned stats snapshot into a caller buffer.

- **`src/mpmcq_version.asm`**
  - **Public**: `GETVERSION`
  - Returns an assemble-time-stamped build string using `&SYSDATE` and `&SYSTIME`.

- **`src/mpmcq_dsects.inc`**
  - DSECT layouts: SCB, node, stats, parm lists.

- **`src/mpmcq_atomics.mac`**
  - CS/CDS retry-loop helper macros for atomic counters/max updates.

- **`src/reg_equates.inc`**
  - Register equates `R0..R15` and role aliases used throughout this project.

- **`jcl/asm_lked.jcl`**
  - Sample assemble/link job skeleton.

---

### Register conventions (readability)

The implementation uses internal register aliases for readability. **Callers do not need any register-alias definitions**; only the entry points and parameter lists matter (see `user_api.inc` or `include/mpmcs_user.h`).

---

### Data structures

All layouts are in `src/mpmcq_dsects.inc`.

#### SCB (Stack Control Block)

Key fields:

- **Identification**
  - `SCB_EYECATCH` (`CL8`): `'MPMCSTK '`
  - `SCB_NAME` (`CL16`): user-assigned name (for logs/messages)
  - `SCB_VERSION` (`F`): structure/version marker

- **Tagged pointers**
  - `SCB_TOP_(ABA,PTR)`: top tagged pointer to nodes
  - `SCB_FREE_(ABA,PTR)`: freelist head tagged pointer

- **ABA tag generator**
  - `SCB_ABA_SEQ`: monotonic counter used to generate new ABA tags for pointer updates

- **Async notification**
  - `SCB_CB_EP`: callback entry point (optional)
  - `SCB_CB_CTX`: user context passed to callback
  - `SCB_CB_ECB`: internal ECB posted by `SPUSH` to wake notifier
  - `SCB_PUSH_SEQ`: monotonic push sequence used for notifier `PendingCount`
  - `SCB_CB_SEQ_SEEN`: last processed push sequence by notifier
  - `SCB_USER_ECB`: optional user ECB posted on each successful push

- **Stats**
  - `SCB_STAT_*` fields (see stats section)

#### Node

Nodes live in 31-bit storage; key fields:

- `NODE_NEXT_(ABA,PTR)`: next pointer in the linked list
- `NODE_PAYLOAD64` (doubleword): 64-bit address of payload bytes
- `NODE_PAYLOAD_LEN` (fullword): payload length in bytes

---

### Public API and calling conventions

All routines use standard z/OS linkage with **R1 -> parameter list**.

Parameter list DSECTs (see `src/mpmcq_dsects.inc`):

- `MPMCS_SINIT_PLIST`
- `MPMCS_SPUSH_PLIST`
- `MPMCS_SPOP_PLIST`
- `MPMCS_SSTATS_PLIST`
- `MPMCS_GETVER_PLIST`
- `MPMCQ_CB_PLIST` (callback parameters: `(CB_CTX, SCBaddr, PendingCount)`)

#### `SINIT(SCBaddr, options, CB_EP, CB_CTX, USER_ECB)`

- Initializes the caller-provided SCB.
- Initializes the TOP pointer to empty.
- Starts the notifier TCB if `CB_EP != 0`.
- Stores `USER_ECB` into `SCB_USER_ECB` for push-time `POST`.

#### `SPUSH(SCBaddr, srcAddr, srcLen)`

- Allocates a node (freelist pop else `GETMAIN BELOW`).
- Allocates payload storage and copies bytes in.
- Pushes onto TOP using `CDS` (linearization point).
- Posts:
  - internal `SCB_CB_ECB` (always)
  - user-provided ECB `SCB_USER_ECB` if non-zero (and addressable)

Return:

- `R15=0` success
- `R15=8` allocation failure (payload allocation path)

#### `SPOP(SCBaddr, dstAddr, dstMaxLen, outLenAddr)`

- If empty, returns `R15=4`.
- Otherwise pops TOP using `CDS` (linearization point), extracts payload,
  copies to the caller buffer (truncation supported), frees payload, and recycles
  the popped node into the freelist.

Return:

- `R15=4` empty
- `R15=0` full message copied
- `R15=8` truncated (copied `dstMaxLen`, but `*outLenAddr` receives actual length)

#### `SSTATS(SCBaddr, outStatsAddr, outStatsLen)`

- Copies a snapshot of stats to `outStatsAddr`.
- `outStatsLen` provides forward compatibility (copy min(outStatsLen, statsSize)).
- Snapshot is **best-effort** under concurrency (no global lock).

Return:

- `R15=0`

#### `SCBSTOP(SCBaddr)`

- Sets a stop flag and POSTs the internal ECB so the notifier can exit.

#### `GETVERSION(outAddr, outMaxLen, outActLenAddr)`

Returns an assemble-time stamped string (see `src/mpmcq_version.asm`).

- If `outAddr==0`: returns `R1=ptr`, `R0=len`, `R15=0`.
- Else copies and returns `R15=0` or `R15=8` if truncated.

---

### Stack algorithm (how PUSH/POP work)

This is a Treiber style linked stack with a tagged TOP pointer:

- `TOP` points to the most recently pushed node.
- Nodes are linked via `NODE_NEXT_(ABA,PTR)`.

#### Linearization points (the important atomics)

- **Push linearization**: the `CDS` that changes `SCB_TOP_(ABA,PTR)` from `oldTop` to `(newABA,newNode)`.
- **Pop linearization**: the `CDS` that changes `SCB_TOP_(ABA,PTR)` from `oldTop` to `(newABA,oldTop->NEXT)`.

#### ABA tagging

All key pointers are stored as `(ABA,PTR)` pairs and updated with `CDS`.

- New ABA tags are obtained by incrementing `SCB_ABA_SEQ` (CS loop).
- ABA tags help reduce the classic ABA problem on TOP swings.

---

### Notifications (ECB + async callback)

#### User ECB (POST on push)

- Caller passes an ECB address in `SINIT` as `USER_ECB`.
- Each successful `SPUSH` does `POST ECB=(userECB)`.
- ECB posts can coalesce (standard z/OS behavior).

#### Notifier TCB callback (asynchronous)

If `CB_EP != 0` in `SINIT`:

- `MPMCS_NSTART` ATTACHes a notifier TCB (`MPMCS_NOTIF`).
- Producers always `POST ECB=SCB_CB_ECB`.
- Notifier:
  - WAITs on `SCB_CB_ECB`
  - computes `PendingCount = PUSH_SEQ - CB_SEQ_SEEN`
  - calls user callback EP with parm list `(CB_CTX, SCBaddr, PendingCount)`

This yields “every push” semantics without ATTACH-per-push overhead.

---

### Statistics

Stats are stored in the SCB (`SCB_STAT_*`) and exposed via `SSTATS`.

Key counters include:

- Stack activity: `PUSH_OK`, `POP_OK`, `POP_EMPTY`, `PUSH_ALLOC_FAIL`
- Retry visibility: `PUSH_RETRY`, `POP_RETRY`, freelist retry counters
- Depth: `DEPTH_CUR`, `DEPTH_MAX` (best-effort)
- 31-bit payload bytes: `PAYLOAD31_CUR`, `PAYLOAD31_MAX` (HI/LO -> D)
- 64-bit payload bytes: `PAYLOAD64_CUR`, `PAYLOAD64_MAX` (HI/LO -> D)
- Notification: `POST_INTERNAL`, `POST_USERECB`, `CB_CALLS`, `CB_PENDING_MAX`

All are **approximate under concurrency** by design.

---

### Storage model (31-bit nodes + optional 31-bit or 64-bit payload)

- **Nodes**: always `GETMAIN BELOW` and recycled through `src/mpmcq_freelist.asm`.

- **Payload bytes**: configurable per stack instance (default: 31-bit)

  - **31-bit payload mode (default)**:
    - allocation: `GETMAIN BELOW`
    - free: `FREEMAIN`
    - accounting: `SCB_STAT_PAYLOAD31_*`

  - **64-bit payload mode (optional)**:
    - allocation: `MPMCS_PAYGET` (`IARV64 REQUEST=GETSTOR`)
    - free: `MPMCS_PAYFREE` (`IARV64 REQUEST=FREESTOR`)
    - accounting: `SCB_STAT_PAYLOAD64_*`

  - **Copying**:
    - 64-bit payload mode uses `SAM64`/`SAM31` wrapped `MVCL` helpers (`src/mpmcq_copy64.mac`).

Reentrancy note: `src/mpmcq_storage.asm` uses MF=L templates copied into per-call
work areas to avoid shared writable IARV64 parameter lists.

