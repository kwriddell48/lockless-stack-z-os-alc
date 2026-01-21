         TITLE 'MPMC stack - Lock-free MPMC LIFO stack (AMODE 31 callable)'
***********************************************************************
*  MPMCQ.ASM
*
*  Entry points:
*    SINIT   - initialize stack control block and start notifier (optional)
*    SPUSH   - push variable-length record (payload handled in later module)
*    SPOP    - pop variable-length record (payload handled in later module)
*
*  This file implements the stack fast-path:
*    - Treiber MPMC stack using a tagged TOP pointer (ABA32, PTR31) updated with CDS
*    - Node reuse via a lock-free freelist (Treiber stack) in src/mpmcq_freelist.asm
*
*  Notes:
*    - Payload allocation/copy/free is wired in by calling helper routines
*      implemented in src/mpmcq_storage.asm and src/mpmcq_copy64.mac.
*    - This code assumes z/Architecture with CDS (doubleword CAS).
*
*  Reentrancy / RENT:
*    - No writable static storage in this CSECT (all mutable state is in QCB/nodes).
*    - Safe for concurrent callers provided each stack instance has its own SCB.
*
*  Counted-pointer layout:
*    - A counted pointer is stored as two adjacent fullwords:
*        [PTR31][EXTCOUNT32]
*      and updated atomically via CDS to reduce ABA risk when pointers move.
***********************************************************************

         PRINT GEN
         OPTABLE ZOP

         COPY  'src/reg_equates.inc'
         COPY  'src/mpmcq_dsects.inc'
         COPY  'src/mpmcq_atomics.mac'
         COPY  'src/mpmcq_copy64.mac'

MPMCQ    CSECT
MPMCQ    AMODE 31
MPMCQ    RMODE ANY

         ENTRY SINIT
         ENTRY SPUSH
         ENTRY SPOP

         EXTRN MPMCS_POPNODE
         EXTRN MPMCS_PUSHNODE
         EXTRN MPMCS_PAYGET
         EXTRN MPMCS_PAYFREE
         EXTRN MPMCS_NSTART

***********************************************************************
* Standard save area usage:
***********************************************************************
         USING MPMCQ,R15

***********************************************************************
* Internal helper prototypes (local labels only)
***********************************************************************

***********************************************************************
* SINIT(SCBaddr, options, CB_EP, CB_CTX, USER_ECB)
***********************************************************************
SINIT     DS    0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         USING MPMCQ,12

* R1 -> parm list (SINIT pl)
         L     Q_R,SINIT_SCBADDR(R1)        Q_R=SCB
         USING MPMCS_SCB,Q_R

* Eyecatcher + version (helps validate SCB in dumps)
         MVC   SCB_EYECATCH,=CL8'MPMCSTK '
         MVC   SCB_NAME,=CL16'                '
         MVC   SCB_VERSION,=F'MPMCS_STATS_VERSION'
         XR    R0,R0
         ST    R0,SCB_FLAGS

* SINIT_OPTIONS bit 0: payload storage mode (see src/mpmcq_dsects.inc equates)
*   MPMCS_OPT_PAYLOAD31 (default) or MPMCS_OPT_PAYLOAD64
         L     R0,SINIT_OPTIONS(R1)
         N     R0,=XL4'00000001'           * mask = MPMCQ_OPT_PAYLOAD64
         ST    R0,SCB_FLAGS

* Store callback configuration:
* - SCB_CB_EP: async callback entry point (invoked by notifier TCB)
* - SCB_CB_CTX: user context value passed to callback
* - SCB_USER_ECB: optional user ECB posted on each successful push
         L     R3,SINIT_CB_EP(R1)
         ST    R3,SCB_CB_EP
         L     R3,SINIT_CB_CTX(R1)
         ST    R3,SCB_CB_CTX
         L     R3,SINIT_USER_ECB(R1)
         ST    R3,SCB_USER_ECB

* Initialize internal notifier fields:
* - SCB_PUSH_SEQ increments on each push (monotonic best-effort)
* - SCB_CB_SEQ_SEEN is last PUSH_SEQ consumed by notifier
* - SCB_CB_ECB is an internal ECB used to wake notifier from WAIT
         XR    R0,R0
         ST    R0,SCB_CB_TCB
         ST    R0,SCB_PUSH_SEQ
         ST    R0,SCB_CB_SEQ_SEEN
         ST    R0,SCB_CB_ECB

* Zero stats area (approximate counters; see SSTATS)
         XC    SCB_STAT_PUSH_OK(SCB_SIZE-SCB_STAT_PUSH_OK),SCB_STAT_PUSH_OK

* Initialize TOP and freelist heads to NULL.
         XR    R0,R0
         ST    R0,SCB_TOP_ABA
         ST    R0,SCB_TOP_PTR
         ST    R0,SCB_FREE_ABA
         ST    R0,SCB_FREE_PTR

* Initialize ABA tag generator (separate from PUSH_SEQ used for notifier PendingCount)
         ST    R0,SCB_ABA_SEQ

* Start notifier TCB (if callback EP provided).
* Notifier lives in src/mpmcq_notify.asm; producers wake it via POST.
         L     R15,=V(MPMCS_NSTART)
         BALR  R14,R15

         XR    R15,R15
         LM    R14,R12,12(R13)
         BR    R14

***********************************************************************
* Internal helper: INC_EXT_COUNT
*
* Increase the external count on a counted pointer (PTR,CNT) stored as
* adjacent fullwords suitable for CDS.
*
* Inputs:
*   R2 = address of counted pointer (points at PTR field)
* Outputs:
*   R6/R7 = resulting (PTR,CNT) after successful increment
* Clobbers:
*   R0,R1,R6,R7,R8,R9
***********************************************************************
INC_EXT_COUNT DS 0H
INCX_LOOP  DS 0H
         L     R6,0(R2)                   ptr
         L     R7,4(R2)                   cnt
         LR    R8,R6
         LR    R9,R7
         LA    R9,1(R9)
* CAS doubleword at (R2): expected=(R6,R7), new=(R8,R9)
         LR    R0,R6
         LR    R1,R7
* Use CDS: compare regs 0/1 with mem, store regs 8/9 if equal
         CDS   R0,R8,0(R2)
         JNE   INCX_LOOP
* Return updated values in R6/R7
         LR    R6,R8
         LR    R7,R9
         BR    R14

***********************************************************************
* Internal helper: NODE_ADJUST_COUNTS
*
* Atomically update node counters (CNT_INT,CNT_EXT) using CDS.
*
* Inputs:
*   R5 = node addr (NODE_CNT_INT at 0(R5))
*   R6 = add_to_internal (signed)
*   R7 = add_to_external (signed)  (typically -1 when dropping an external)
* Output:
*   R0/R1 = new (int,ext) after update
***********************************************************************
NODE_ADJUST_COUNTS DS 0H
NAC_LOOP DS 0H
         L     R0,NODE_CNT_INT(R5)
         L     R1,NODE_CNT_EXT(R5)
         LR    R8,R0
         LR    R9,R1
         AR    R8,R6
         AR    R9,R7
         CDS   R0,R8,NODE_CNT_INT(R5)
         JNE   NAC_LOOP
         LR    R0,R8
         LR    R1,R9
         BR    R14

***********************************************************************
* SPUSH(SCBaddr, srcAddr, srcLen)
*
* Push a record:
* - Allocates a node (from freelist or GETMAIN fallback)
* - Allocates payload storage and copies bytes in
* - Pushes node onto the lock-free Treiber stack
* - Updates best-effort stats
* - Posts internal ECB (for notifier TCB) and user ECB (optional)
***********************************************************************
SPUSH    DS    0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         USING MPMCQ,12

         L     Q_R,SPU_SCBADDR(R1)
         USING MPMCS_SCB,Q_R
         L     R6,SPU_SRCADDR(R1)
         L     R7,SPU_SRCLEN(R1)

* Allocate/reuse node:
* - Try lock-free freelist pop first (fast, lock-free)
* - If empty, GETMAIN a new node (slow path; system service)
         L     R15,=V(MPMCS_POPNODE)
         BALR  R14,R15
         LTR   R15,R15
         JNZ   SPU_GETMAIN
         LR    NEWNODE_R,R1
         J     SPU_HAVE_NODE

SPU_GETMAIN DS 0H
         LA    R4,NODE_SIZE
         GETMAIN RU,LV=(R4),LOC=BELOW
         LR    NEWNODE_R,R1

SPU_HAVE_NODE DS 0H
         USING MPMCQ_NODE,NEWNODE_R
* Clear node: important when reusing from freelist (old NEXT/payload must not leak)
         XC    0(NODE_SIZE,NEWNODE_R),0(NEWNODE_R)
         XR    R0,R0
         ST    R0,NODE_CNT_INT
         ST    R0,NODE_CNT_EXT
         ST    R0,NODE_NEXT_ABA
         ST    R0,NODE_NEXT_PTR

* Allocate payload and copy in (variable length).
* Default mode is 31-bit payload (below 2G). Optional 64-bit mode uses IARV64.
         LTR   R7,R7
         JZ    SPU_PAYLOAD_SET
* Decide payload mode based on SCB_FLAGS bit 0 (MPMCS_OPT_PAYLOAD64)
         L     R0,SCB_FLAGS
         N     R0,=XL4'00000001'           * mask = MPMCS_OPT_PAYLOAD64
         LTR   R0,R0
         JNZ   SPU_PAYLOAD_64

* 31-bit payload: GETMAIN BELOW
         GETMAIN RU,LV=(R7),LOC=BELOW
         LR    R4,R1                       save payload ptr
         LR    R8,R4                       dest addr
         LR    R9,R7                       dest len
         LR    R10,R6                      src addr
         LR    R11,R7                      src len
         MVCL  R8,R10
         LR    R8,R4                       restore payload ptr for STG
         STG   R8,NODE_PAYLOAD64
         ST    R7,NODE_PAYLOAD_LEN

* Update payload31 stats
         MPMCQ_STATADD64 Q_R,SCB_STAT_PAYLOAD31_CUR_HI,SCB_STAT_PAYLOAD31_CUR_LO,R7,R0,R8
         L     R4,SCB_STAT_PAYLOAD31_CUR_HI
         L     R6,SCB_STAT_PAYLOAD31_CUR_LO
         MPMCQ_STATMAX64 Q_R,SCB_STAT_PAYLOAD31_MAX_HI,SCB_STAT_PAYLOAD31_MAX_LO,R4,R6,R0,R8
         J     SPU_PAYLOAD_DONE

SPU_PAYLOAD_64 DS 0H
* 64-bit payload: IARV64 via MPMCS_PAYGET + SAM64 copy macro
         L     R15,=V(MPMCS_PAYGET)
         BALR  R14,R15                    in: R7=len, out: R8=addr64, R15=rc
         LTR   R15,R15
         JZ    SPU_PAYLOAD_COPY
* Allocation failed: stats + recycle node
         MPMCQ_STATINC Q_R,SCB_STAT_PUSH_ALLOC_FAIL,R8,R9
         L     R15,=V(MPMCS_PUSHNODE)
         BALR  R14,R15
         LA    R15,8
         LM    R14,R12,12(R13)
         BR    R14

SPU_PAYLOAD_COPY DS 0H
* Copy from src (31-bit in R6) to payload (64-bit in R8), length R7.
* This is safe for AMODE 31 callers because the copy is wrapped with SAM64/SAM31.
         MPMCQ_COPY_31_TO_64 R6,R8,R7,R8,R10,R11

* Record payload in node
         STG   R8,NODE_PAYLOAD64
         ST    R7,NODE_PAYLOAD_LEN

* Update 64-bit payload usage stats (cur += len; max = max(max,cur)).
         MPMCQ_STATADD64 Q_R,SCB_STAT_PAYLOAD64_CUR_HI,SCB_STAT_PAYLOAD64_CUR_LO,R7,R0,R8
         L     R4,SCB_STAT_PAYLOAD64_CUR_HI
         L     R6,SCB_STAT_PAYLOAD64_CUR_LO
         MPMCQ_STATMAX64 Q_R,SCB_STAT_PAYLOAD64_MAX_HI,SCB_STAT_PAYLOAD64_MAX_LO,R4,R6,R0,R8
         J     SPU_PAYLOAD_SET

SPU_PAYLOAD_SET DS 0H
         LTR   R7,R7
         JNZ   SPU_PAYLOAD_DONE
         XR    R0,R0
         STG   R0,NODE_PAYLOAD64
         ST    R0,NODE_PAYLOAD_LEN
SPU_PAYLOAD_DONE DS 0H

* Treiber push:
*  - write newNode->NEXT = oldTop
*  - CDS TOP from expected oldTop to desired (newABA,newNode)
SPU_RETRY_LOOP DS 0H
         MPMCQ_STATINC Q_R,SCB_STAT_PUSH_RETRY,R8,R9

* Snapshot TOP tagged pointer
         L     R0,SCB_TOP_ABA
         L     R1,SCB_TOP_PTR

* Link new node to the observed top
         ST    R0,NODE_NEXT_ABA
         ST    R1,NODE_NEXT_PTR

* Get a fresh ABA tag for the TOP pointer
SPU_TOP_ABA_LOOP DS 0H
         L     R8,SCB_ABA_SEQ
         LA    R9,1(R8)
         CS    R8,R9,SCB_ABA_SEQ
         JNE   SPU_TOP_ABA_LOOP
         LR    R8,R9                       desired ABA
         LR    R9,NEWNODE_R                desired PTR

* CAS TOP from expected (R0,R1) to desired (ABA,PTR)
         CDS   R0,R8,SCB_TOP_ABA(Q_R)
         JNE   SPU_RETRY_LOOP

* Update stats for success (approx)
         MPMCQ_STATINC Q_R,SCB_STAT_PUSH_OK,R8,R9
* depth++
         L     R8,SCB_STAT_DEPTH_CUR
         LA    R9,1(R8)
SPU_DEPTHCAS DS 0H
         CS    R8,R9,SCB_STAT_DEPTH_CUR
         JNE   SPU_DEPTHCAS
         MPMCQ_STATMAX Q_R,SCB_STAT_DEPTH_MAX,R9,R8,R11

* PUSH notifications:
* - increment PUSH_SEQ (used by notifier to compute PendingCount)
* - POST internal ECB (wakes notifier TCB; posts may coalesce)
* - POST user ECB if provided (posts may coalesce)
SPU_SEQ_LOOP DS 0H
         L     R0,SCB_PUSH_SEQ
         LA    R3,1(R0)
         CS    R0,R3,SCB_PUSH_SEQ
         JNE   SPU_SEQ_LOOP
         POST  ECB=SCB_CB_ECB
         MPMCQ_STATINC Q_R,SCB_STAT_POST_INTERNAL,R8,R9

         LT    R4,SCB_USER_ECB
         JZ    SPU_NO_USERECB
* Validate user ECB addressability
         LRA   R1,SCB_USER_ECB
         JZ    SPU_NO_USERECB

         POST  ECB=(R4)
         MPMCQ_STATINC Q_R,SCB_STAT_POST_USERECB,R8,R9

SPU_NO_USERECB DS 0H
         XR    R15,R15
         LM    R14,R12,12(R13)
         BR    R14

***********************************************************************
* SPOP(SCBaddr, dstAddr, dstMaxLen, outLenAddr)
*
* Pop a record:
* - Swings TOP forward (CDS on (ABA,PTR)); this is the POP linearization point
* - Copies payload out to caller buffer (truncation supported)
* - Frees payload storage and updates byte-usage stats
* - Recycles the popped node into the freelist
***********************************************************************
SPOP     DS    0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         USING MPMCQ,12

         L     Q_R,SPO_SCBADDR(R1)
         USING MPMCS_SCB,Q_R
         L     R6,SPO_DSTADDR(R1)
         L     R7,SPO_DSTMAX(R1)

SPO_RETRY_LOOP DS 0H
         MPMCQ_STATINC Q_R,SCB_STAT_POP_RETRY,R8,R9

* Snapshot TOP; if PTR is zero then empty.
         LT    R1,SCB_TOP_PTR
         JZ    SPO_EMPTY
         L     R0,SCB_TOP_ABA

         LR    NODE_R,R1
         USING MPMCQ_NODE,NODE_R

* Read next pointer from the node we want to pop.
         L     R6,NODE_NEXT_ABA
         L     NEXTNODE_R,NODE_NEXT_PTR

* Get a fresh ABA tag for the TOP pointer
SPO_TOP_ABA_LOOP DS 0H
         L     R8,SCB_ABA_SEQ
         LA    R9,1(R8)
         CS    R8,R9,SCB_ABA_SEQ
         JNE   SPO_TOP_ABA_LOOP
         LR    R8,R9                       desired ABA
         LR    R9,NEXTNODE_R               desired PTR

* CAS TOP from expected (R0,R1) to desired (ABA,PTR)
         CDS   R0,R8,SCB_TOP_ABA(Q_R)
         JNE   SPO_RETRY_LOOP

* We popped NODE_R; extract its payload.
         L     R9,NODE_PAYLOAD_LEN
         LG    R8,NODE_PAYLOAD64

* Store actual length to *outLenAddr (always actual, even if truncated)
         LT    R4,SPO_OUTLENADDR(R1)
         JZ    SPO_OUTLEN_DONE
         ST    R9,0(R4)
SPO_OUTLEN_DONE DS 0H

* Determine copy length and return code:
* - RC=0 if full message copied
* - RC=8 if truncated (outLen still reports actual message length)
         LR    R5,R9                       actual
         CR    R9,R7                       actual vs dstMax
         JNH   SPO_COPY_FULL
* Truncated
         LR    R5,R7                       copyLen = dstMax
         LA    R15,8                       RC=8
         J     SPO_DO_COPY
SPO_COPY_FULL DS 0H
         XR    R15,R15                     RC=0

SPO_DO_COPY DS 0H
         LTR   R5,R5
         JZ    SPO_SKIP_COPY
         MPMCQ_COPY_64_TO_31 R8,R6,R5,R10,R8,R11
SPO_SKIP_COPY DS 0H

* Free payload storage and adjust payload usage stats (cur -= actualLen)
         LTR   R9,R9
         JZ    SPO_SKIP_FREE
* Decide payload mode based on SCB_FLAGS bit 0 (MPMCS_OPT_PAYLOAD64)
         L     R0,SCB_FLAGS
         N     R0,=XL4'00000001'           * mask = MPMCS_OPT_PAYLOAD64
         LTR   R0,R0
         JNZ   SPO_FREE_64

* 31-bit payload free: FREEMAIN BELOW
         LR    R7,R9                       length
         LR    R1,R8                       address (low 31 bits)
         FREEMAIN RU,A=(R1),LV=(R7)
* Update payload31 current usage: cur -= len
         LCR   R7,R7                        signed -len
         MPMCQ_STATADD64S Q_R,SCB_STAT_PAYLOAD31_CUR_HI,SCB_STAT_PAYLOAD31_CUR_LO,R7,R0,R8
         J     SPO_SKIP_FREE

SPO_FREE_64 DS 0H
         LR    R7,R9                       pass actual length to PAYFREE
         L     R15,=V(MPMCS_PAYFREE)
         BALR  R14,R15                     in: R8=addr64, R7=len
* Update payload64 current usage: cur -= len
         LCR   R7,R7                        signed -len
         MPMCQ_STATADD64S Q_R,SCB_STAT_PAYLOAD64_CUR_HI,SCB_STAT_PAYLOAD64_CUR_LO,R7,R0,R8

SPO_SKIP_FREE DS 0H

* Clear payload fields in the popped node before recycling.
         XR    R0,R0
         STG   R0,NODE_PAYLOAD64
         ST    R0,NODE_PAYLOAD_LEN

* Recycle popped node into freelist for reuse by producers.
         LR    NEWNODE_R,NODE_R
         L     R15,=V(MPMCS_PUSHNODE)
         BALR  R14,R15

* stats: pop ok, depth--
         MPMCQ_STATINC Q_R,SCB_STAT_POP_OK,R8,R9
SPO_DEC_LOOP DS 0H
         L     R8,SCB_STAT_DEPTH_CUR
         LR    R9,R8
         BCTR  R9,0
         CS    R8,R9,SCB_STAT_DEPTH_CUR
         JNE   SPO_DEC_LOOP

         LM    R14,R12,12(R13)
         BR    R14

SPO_EMPTY DS 0H
         MPMCQ_STATINC Q_R,SCB_STAT_POP_EMPTY,R8,R9
         LA    R15,4
         LM    R14,R12,12(R13)
         BR    R14

         END   MPMCQ

