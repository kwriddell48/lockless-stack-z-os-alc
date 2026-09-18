         TITLE 'MPMC stack - Lock-free MPMC LIFO stack (AMODE 31 callable)'
***********************************************************************
*  MPMCQ.ASM
*
*  Public entry points (AMODE 31, standard OS linkage, R1 -> parm list):
*    SINIT  - initialize one Stack Control Block (SCB) and optionally
*             ATTACH a notifier TCB when a callback EP is supplied
*    SPUSH  - push a variable-length record (copy-in semantics)
*    SPOP   - pop a variable-length record (copy-out; truncation OK)
*
*  Algorithm (Treiber lock-free LIFO):
*    - Shared head is a tagged pointer pair (ABA32, PTR31) in the SCB,
*      updated atomically with CDS (compare double and swap).
*    - ABA tags are derived per-field as (old ABA + 1) at the point of
*      each CDS attempt. Correctness only requires monotonicity within
*      a single field's own CDS history, so each of SCB_TOP_*,
*      SCB_FREE_*, and SCB_WORK_* mints its own tag independently —
*      there is no shared/global tag generator (see mpmcq_freelist.asm).
*    - Nodes are reused via a second Treiber stack (freelist) implemented
*      in src/mpmcq_freelist.asm; GETMAIN is only the empty-pool fallback.
*
*  Payload storage:
*    - Default: 31-bit GETMAIN BELOW (SCB_FLAGS bit 0 clear).
*    - Optional: 64-bit IARV64 via MPMCS_PAYGET/PAYFREE (bit 0 set at SINIT).
*    - Caller buffers need not remain valid after SPUSH/SPOP return;
*      bytes are copied into/out of node-owned storage.
*
*  Performance pools (prefer these over per-call GETMAIN):
*    - Node freelist: prefills at SINIT (count from OPTIONS high half,
*      or MPMCS_NODE_PREFILL default). SPUSH GETMAINs a node only on miss.
*    - Work-cell freelist: prefills MPMCS_WORK_PREFILL cells of size
*      MPMCS_WORK_CELL. SPUSH/SPOP use MPMCQ_ENTER_SCB / RETURN_SCB so the
*      warm path recycles cells with CDS (no FREEMAIN).
*    - PAYGET/PAYFREE are leaves that build IARV64 MF=E lists in the
*      caller's work cell (no nested GETMAIN).
*
*  Linkage / RENT (critical):
*    - Hot path: ENTER_SCB obtains a work cell, chains it as next SA.
*    - Nested BALRs (freelist/storage) STM into that next SA.
*    - RETURN_SCB recycles the cell and stores R15 into the caller's SA
*      so LM does not wipe the return code.
*    - Hot-path spills (src, dst, payload origin, RC) live past offset 72.
*    - SINIT bootstraps with GETMAIN ENTER (pool not ready yet).
*
*  Return codes:
*    SPUSH: 0 ok, 8 payload allocation failure
*    SPOP:  0 ok, 4 empty, 8 truncated (outLen still = full message len)
*
*  Register roles (see also src/reg_equates.inc):
*    Q_R (R2)       SCB base
*    NEWNODE_R (R5) node being built / recycled
*    NODE_R (R10)   node currently owned after a successful pop CDS
*    NEXTNODE_R (R3) successor pointer while swinging TOP
***********************************************************************

         PRINT GEN
         OPTABLE ZOP

         COPY  'src/reg_equates.inc'
         COPY  'src/mpmcq_dsects.inc'
         COPY  'src/mpmcq_atomics.mac'
         COPY  'src/mpmcq_copy64.mac'
         COPY  'src/mpmcq_save.mac'

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
         EXTRN MPMCS_WORKGET
         EXTRN MPMCS_WORKPUT

         USING MPMCQ,R15

***********************************************************************
* Work-cell layout (pooled cells are MPMCS_WORK_CELL bytes).
* First 72 bytes = standard OS save area; remainder = spills + IARV MF.
***********************************************************************
WK_SA      EQU   0                      18F standard SA (R13 points here)
WK_DST     EQU   72                     SPOP: caller destination address
WK_DSTMAX  EQU   76                     SPOP: max bytes to copy out
WK_OUTLENA EQU   80                     SPOP: addr of fullword for actual len
WK_SRCA    EQU   84                     SPUSH: caller source address
WK_SRCLEN  EQU   88                     SPUSH: source length
WK_PAYD    EQU   96                     D: payload storage origin (pre-MVCL)
WK_ACTLEN  EQU   104                    actual payload length (bytes)
WK_RC      EQU   108                    pending SPOP return code
WK_IARV    EQU   128                    IARV64 MF=E work (PAYGET/PAYFREE)
WK_IARVMAX EQU   256                    bytes reserved for MF list
* Bootstrap SINIT GETMAIN size (must be <= MPMCS_WORK_CELL)
WK_LEN     EQU   MPMCS_WORK_CELL

***********************************************************************
* SINIT(SCBaddr, options, CB_EP, CB_CTX, USER_ECB)
*
* Caller must provide an SCB buffer of size SCB_SIZE that remains
* allocated for the life of the stack. Prefer doubleword alignment so
* SCB_TOP_* / SCB_FREE_* / SCB_WORK_* are safe for CDS.
*
* OPTIONS:
*   bit 31       = MPMCS_OPT_PAYLOAD64 (X'00000001'; else 31-bit payload)
*   bits 0-15    = node prefill count in the high half (0 => MPMCS_NODE_PREFILL)
*                 e.g. (64)*65536 + MPMCS_OPT_PAYLOAD64
*
* Prefills work cells + nodes so SPUSH/SPOP avoid GETMAIN on the warm path.
* If CB_EP != 0, MPMCS_NSTART ATTACHes the notifier TCB.
***********************************************************************
SINIT    DS    0H
         MPMCQ_ENTER WK_LEN
         USING MPMCQ,12

         L     Q_R,SINIT_SCBADDR(R1)       Q_R -> caller-owned SCB
         USING MPMCS_SCB,Q_R

* Capture OPTIONS fields before GETMAIN/prefill clobbers R1.
* High half = node prefill count; low bit = payload mode.
         LLH   R8,SINIT_OPTIONS(R1)        R8 = prefill count (0 => default)
         XR    R0,R0
         TM    SINIT_OPTIONS+3(R1),X'01'   MPMCS_OPT_PAYLOAD64?
         JZ    SINIT_FLAGS_ST
         LA    R0,1
SINIT_FLAGS_ST DS 0H
         ST    R0,SCB_FLAGS

         MVC   SCB_EYECATCH,=CL8'MPMCSTK '
         MVC   SCB_NAME,=CL16'                '
         MVC   SCB_VERSION,=F'MPMCS_STATS_VERSION'

         L     R3,SINIT_CB_EP(R1)
         ST    R3,SCB_CB_EP
         L     R3,SINIT_CB_CTX(R1)
         ST    R3,SCB_CB_CTX
         L     R3,SINIT_USER_ECB(R1)
         ST    R3,SCB_USER_ECB

         XR    R0,R0
         ST    R0,SCB_CB_TCB
         ST    R0,SCB_PUSH_SEQ
         ST    R0,SCB_CB_SEQ_SEEN
         ST    R0,SCB_CB_ECB
         ST    R0,SCB_STOP_ECB

         XC    SCB_STAT_PUSH_OK(SCB_SIZE-SCB_STAT_PUSH_OK),SCB_STAT_PUSH_OK

         XR    R0,R0
         ST    R0,SCB_TOP_ABA
         ST    R0,SCB_TOP_PTR
         ST    R0,SCB_FREE_ABA
         ST    R0,SCB_FREE_PTR
         ST    R0,SCB_WORK_ABA
         ST    R0,SCB_WORK_PTR
* SCB_ABA_SEQ is no longer read by any pool (each field mints its own
* tag as old+1 at CDS time — see mpmcq_freelist.asm and SPUSH/SPOP
* below). Field is left zeroed for layout/compat only.
         ST    R0,SCB_ABA_SEQ

***********************************************************************
* Prefill work-cell pool (fixed-size SA/spill blocks for ENTER_SCB).
***********************************************************************
         LA    R9,MPMCS_WORK_PREFILL
SINIT_WPF DS 0H
         LTR   R9,R9
         JZ    SINIT_WPF_DONE
         LA    R0,MPMCS_WORK_CELL
         GETMAIN RU,LV=(R0),LOC=BELOW
         L     R15,=V(MPMCS_WORKPUT)
         BALR  R14,R15                     R1=cell, Q_R=SCB
         BCT   R9,SINIT_WPF
SINIT_WPF_DONE DS 0H

***********************************************************************
* Prefill node freelist (OPTIONS high half, or default).
***********************************************************************
         LR    R9,R8                       count saved at entry (LLH)
         LTR   R9,R9
         JNZ   SINIT_NPF_HAVE
         LA    R9,MPMCS_NODE_PREFILL
SINIT_NPF_HAVE DS 0H
SINIT_NPF DS 0H
         LTR   R9,R9
         JZ    SINIT_NPF_DONE
         LA    R4,NODE_SIZE
         GETMAIN RU,LV=(R4),LOC=BELOW
         LR    NEWNODE_R,R1
         USING MPMCQ_NODE,NEWNODE_R
         XC    0(NODE_SIZE,NEWNODE_R),0(NEWNODE_R)
         L     R15,=V(MPMCS_PUSHNODE)
         BALR  R14,R15
         BCT   R9,SINIT_NPF
SINIT_NPF_DONE DS 0H

         L     R15,=V(MPMCS_NSTART)
         BALR  R14,R15

         XR    R15,R15
         MPMCQ_RETURN R15,WK_LEN

***********************************************************************
* SPUSH(SCBaddr, srcAddr, srcLen)
*
* Steps:
*  1) Obtain a node (freelist pop, else GETMAIN NODE_SIZE)
*  2) Allocate payload (len bytes) and copy from caller src
*  3) CDS TOP from (oldABA,oldPtr) to (newABA,newNode)
*  4) Update approx stats; bump PUSH_SEQ; POST ECB(s) as configured
*
* Linearization point = successful CDS on SCB_TOP_ABA.
***********************************************************************
SPUSH    DS    0H
         MPMCQ_ENTER_SCB
         USING MPMCQ,12
         USING MPMCS_SCB,Q_R
         L     R6,SPU_SRCADDR(R1)
         L     R7,SPU_SRCLEN(R1)
* Spill src early: freelist/CDS/stat macros clobber many GPRs including R1.
         ST    R6,WK_SRCA(R13)
         ST    R7,WK_SRCLEN(R13)

* Prefer freelist reuse (lock-free). RC!=0 means empty -> GETMAIN fallback.
         L     R15,=V(MPMCS_POPNODE)
         BALR  R14,R15                     in: Q_R; out: R1=node, R15=rc
         LTR   R15,R15
         JNZ   SPU_GETMAIN
         LR    NEWNODE_R,R1
         J     SPU_HAVE_NODE

SPU_GETMAIN DS 0H
* Slow path: brand-new node below the bar (AMODE 31 addressable).
* No explicit clear needed: NODE_NEXT_ABA/PTR are stored by the retry
* loop below, and NODE_PAYLOAD64/LEN are set on every branch of the
* payload-setup code that follows (including the zero-length case).
* NODE_CNT_INT/EXT and NODE_RSVD are unused by any code in this stack
* (see mpmcq_stats.asm) so they are intentionally left as-is.
         LA    R4,NODE_SIZE
         GETMAIN RU,LV=(R4),LOC=BELOW
         LR    NEWNODE_R,R1

SPU_HAVE_NODE DS 0H
         USING MPMCQ_NODE,NEWNODE_R

         L     R6,WK_SRCA(R13)
         LT    R7,WK_SRCLEN(R13)           load+test length; zero => no payload
         JZ    SPU_PAYLOAD_SET             zero-length message is valid

* Payload mode is fixed at SINIT (low bit of SCB_FLAGS = MPMCS_OPT_PAYLOAD64).
         TM    SCB_FLAGS+3,X'01'           test low-order bit of FLAGS
         JO    SPU_PAYLOAD_64              branch if bit is set

*----- 31-bit payload path (default) ---------------------------------
* GETMAIN BELOW, MVCL from caller src, stash origin in node as 64-bit
* address with high half zero (STG of 31-bit ptr).
         GETMAIN RU,LV=(R7),LOC=BELOW
         LR    R4,R1                       R4 = payload origin (stable)
         STG   R4,WK_PAYD(R13)             MVCL will advance R8/R9
         LR    R8,R4                       dest addr
         LR    R9,R7                       dest len
         LR    R10,R6                      src addr
         LR    R11,R7                      src len (equal => no pad)
         MVCL  R8,R10
         LG    R8,WK_PAYD(R13)             restore origin (not advanced)
         STG   R8,NODE_PAYLOAD64
         ST    R7,NODE_PAYLOAD_LEN

* Approx byte accounting (CDS loop inside macro; R0/R8 scratch).
         MPMCQ_STATADD64 Q_R,SCB_STAT_PAYLOAD31_CUR_HI,SCB_STAT_PAYLOAD31_CUR_LO,R7,R0,R8
         L     R4,SCB_STAT_PAYLOAD31_CUR_HI
         L     R6,SCB_STAT_PAYLOAD31_CUR_LO
         MPMCQ_STATMAX64 Q_R,SCB_STAT_PAYLOAD31_MAX_HI,SCB_STAT_PAYLOAD31_MAX_LO,R4,R6,R0,R8
         J     SPU_PAYLOAD_DONE

*----- 64-bit payload path (IARV64) ----------------------------------
SPU_PAYLOAD_64 DS 0H
         L     R15,=V(MPMCS_PAYGET)
         BALR  R14,R15                     in: R7=len; out: R8=addr64, R15=rc
         LTR   R15,R15
         JZ    SPU_PAYLOAD_COPY
* Alloc failed: recycle the node we already obtained, return RC=8.
         MPMCQ_STATINC Q_R,SCB_STAT_PUSH_ALLOC_FAIL
         L     R15,=V(MPMCS_PUSHNODE)
         BALR  R14,R15                     in: Q_R, NEWNODE_R
         LA    R15,8
         MPMCQ_RETURN_SCB R15

SPU_PAYLOAD_COPY DS 0H
* COPY macro uses MVCL under SAM64; address regs advance — save origin.
         STG   R8,WK_PAYD(R13)
         L     R6,WK_SRCA(R13)
         L     R7,WK_SRCLEN(R13)
         MPMCQ_COPY_31_TO_64 R6,R8,R7,R8,R10,R11
         LG    R8,WK_PAYD(R13)
         STG   R8,NODE_PAYLOAD64
         ST    R7,NODE_PAYLOAD_LEN

         MPMCQ_STATADD64 Q_R,SCB_STAT_PAYLOAD64_CUR_HI,SCB_STAT_PAYLOAD64_CUR_LO,R7,R0,R8
         L     R4,SCB_STAT_PAYLOAD64_CUR_HI
         L     R6,SCB_STAT_PAYLOAD64_CUR_LO
         MPMCQ_STATMAX64 Q_R,SCB_STAT_PAYLOAD64_MAX_HI,SCB_STAT_PAYLOAD64_MAX_LO,R4,R6,R0,R8
         J     SPU_PAYLOAD_DONE

SPU_PAYLOAD_SET DS 0H
* Zero-length: node carries a null payload pointer and len 0.
         XR    R0,R0
         STG   R0,NODE_PAYLOAD64
         ST    R0,NODE_PAYLOAD_LEN
SPU_PAYLOAD_DONE DS 0H

***********************************************************************
* Treiber push onto SCB_TOP_*.
* Publish node->NEXT = observed TOP, then CDS TOP to (freshABA, newNode).
* freshABA = old TOP ABA + 1 (per-field tag; see file header). On CDS
* failure another producer/consumer won; rebuild NEXT and retry.
***********************************************************************
SPU_RETRY_LOOP DS 0H
         L     R0,SCB_TOP_ABA              expected ABA
         L     R1,SCB_TOP_PTR              expected PTR (may be 0)
         ST    R0,NODE_NEXT_ABA            link before publishing node
         ST    R1,NODE_NEXT_PTR

         LA    R8,1(R0)                    desired ABA = old+1
         LR    R9,NEWNODE_R                desired PTR

         CDS   R0,R8,SCB_TOP_ABA(Q_R)      compare (R0,R1) store (R8,R9)
         JE    SPU_PUSH_OK
         MPMCQ_STATINC Q_R,SCB_STAT_PUSH_RETRY   count contention only
         J     SPU_RETRY_LOOP

SPU_PUSH_OK DS 0H
* Success path: approximate depth + push counter (not exact under races).
         LHI   R8,1
         LAAL  R8,SCB_STAT_DEPTH_CUR(Q_R)  atomic depth++
         L     R9,SCB_STAT_DEPTH_CUR
         MPMCQ_STATMAX Q_R,SCB_STAT_DEPTH_MAX,R9,R8,R11

* Notifier coalescing key: each successful push advances PUSH_SEQ.
* This is also now the push-ok stat reported by SSTATS (see
* mpmcq_stats.asm) — SCB_STAT_PUSH_OK was a redundant second counter
* for the same event and has been retired.
         LHI   R0,1
         LAAL  R0,SCB_PUSH_SEQ(Q_R)

* Internal ECB: POST if addressable.
         LA    R4,SCB_CB_ECB
         LRA   R1,0(R4)                    must be a valid/addressable ECB
         JNZ   SPU_NO_INTERNAL
         POST  ECB=(R4)
         MPMCQ_STATINC Q_R,SCB_STAT_POST_INTERNAL
SPU_NO_INTERNAL DS 0H

* Optional user ECB: LRA is a best-effort addressability check.
* Skip POST if already posted (ECB bit 0 set) — POSTs coalesce anyway,
* but avoiding the SVC is cheaper under bursty producers.
         LT    R4,SCB_USER_ECB
         JZ    SPU_NO_USERECB
         LRA   R1,0(R4)
         JNZ   SPU_NO_USERECB              translation failed -> skip POST
         TM    0(R4),X'80'                 already posted?
         JO    SPU_NO_USERECB
         POST  ECB=(R4)
         MPMCQ_STATINC Q_R,SCB_STAT_POST_USERECB

SPU_NO_USERECB DS 0H
         XR    R15,R15                     RC=0
         MPMCQ_RETURN_SCB R15

***********************************************************************
* SPOP(SCBaddr, dstAddr, dstMaxLen, outLenAddr)
*
* Steps:
*  1) CDS TOP forward to node->NEXT (empty if TOP.PTR == 0)
*  2) Store full message length at *outLenAddr (even if truncated)
*  3) Copy min(actual, dstMax) bytes to caller dst
*  4) Free payload storage; recycle node onto freelist
*
* Ownership: after a winning CDS, only this CP touches the node's payload.
* Spill dst/outLen before the retry loop — R1 is reused as TOP.PTR.
***********************************************************************
SPOP     DS    0H
         MPMCQ_ENTER_SCB
         USING MPMCQ,12
         USING MPMCS_SCB,Q_R
         L     R6,SPO_DSTADDR(R1)
         L     R7,SPO_DSTMAX(R1)
         L     R4,SPO_OUTLENADDR(R1)
         ST    R6,WK_DST(R13)
         ST    R7,WK_DSTMAX(R13)
         ST    R4,WK_OUTLENA(R13)
         XR    R0,R0
         ST    R0,WK_RC(R13)               default RC=0 until truncation

SPO_RETRY_LOOP DS 0H
         LT    R1,SCB_TOP_PTR              R1 = expected PTR (also CDS odd)
         JZ    SPO_EMPTY
         L     R0,SCB_TOP_ABA              R0 = expected ABA (CDS even)

         LR    NODE_R,R1                   candidate top node
         USING MPMCQ_NODE,NODE_R

* Only need NEXT.PTR for the desired head; do not load NEXT.ABA into R6
* (R6 is the spilled destination address role).
         L     NEXTNODE_R,NODE_NEXT_PTR

         LA    R8,1(R0)                    desired ABA for new TOP = old+1
         LR    R9,NEXTNODE_R               desired PTR (may be 0)

         CDS   R0,R8,SCB_TOP_ABA(Q_R)      pop linearization point
         JE    SPO_HAVE_NODE
         MPMCQ_STATINC Q_R,SCB_STAT_POP_RETRY
         J     SPO_RETRY_LOOP

SPO_HAVE_NODE DS 0H
* We uniquely own NODE_R. Snapshot payload before any free/recycle.
         L     R9,NODE_PAYLOAD_LEN
         LG    R8,NODE_PAYLOAD64
         ST    R9,WK_ACTLEN(R13)
         STG   R8,WK_PAYD(R13)

* Always report the true message length; truncation only affects copy RC.
         LT    R4,WK_OUTLENA(R13)
         JZ    SPO_OUTLEN_DONE
         ST    R9,0(R4)
SPO_OUTLEN_DONE DS 0H

         L     R7,WK_DSTMAX(R13)
         LR    R5,R9                       R5 = copyLen candidate (actual)
         CR    R9,R7                       actual vs dstMax
         JNH   SPO_COPY_FULL
         LR    R5,R7                       truncate copy to dstMax
         LA    R15,8                       RC=truncated
         ST    R15,WK_RC(R13)
         J     SPO_DO_COPY
SPO_COPY_FULL DS 0H
         XR    R15,R15                     RC=0
         ST    R15,WK_RC(R13)

SPO_DO_COPY DS 0H
         LTR   R5,R5
         JZ    SPO_SKIP_COPY
* Dest pair R4/R5, src pair R8/R9 — avoids clobbering NODE_R (R10).
         L     R6,WK_DST(R13)
         LG    R8,WK_PAYD(R13)
         MPMCQ_COPY_64_TO_31 R8,R6,R5,R4,R8,R11
         LG    R8,WK_PAYD(R13)             MVCL advanced R8; restore origin
SPO_SKIP_COPY DS 0H

* Free payload using the SAME mode bit that was set at SINIT.
         LT    R9,WK_ACTLEN(R13)           load+test actual length
         JZ    SPO_SKIP_FREE

         TM    SCB_FLAGS+3,X'01'           MPMCS_OPT_PAYLOAD64?
         JO    SPO_FREE_64

* 31-bit FREEMAIN of the original payload address (not MVCL-advanced).
         LR    R7,R9
         LG    R8,WK_PAYD(R13)
         LR    R1,R8
         FREEMAIN RU,A=(R1),LV=(R7)
         LCR   R7,R7                       signed -len for stat subtract
         MPMCQ_STATADD64S Q_R,SCB_STAT_PAYLOAD31_CUR_HI,SCB_STAT_PAYLOAD31_CUR_LO,R7,R0,R8
         J     SPO_SKIP_FREE

SPO_FREE_64 DS 0H
         L     R7,WK_ACTLEN(R13)
         LG    R8,WK_PAYD(R13)
         L     R15,=V(MPMCS_PAYFREE)
         BALR  R14,R15                     in: R8=origin64, R7=len
         L     R7,WK_ACTLEN(R13)
         LCR   R7,R7
         MPMCQ_STATADD64S Q_R,SCB_STAT_PAYLOAD64_CUR_HI,SCB_STAT_PAYLOAD64_CUR_LO,R7,R0,R8

SPO_SKIP_FREE DS 0H
* Clear payload fields before publishing the node on the freelist.
         XR    R0,R0
         STG   R0,NODE_PAYLOAD64
         ST    R0,NODE_PAYLOAD_LEN

         LR    NEWNODE_R,NODE_R
         L     R15,=V(MPMCS_PUSHNODE)
         BALR  R14,R15                     recycle node for future SPUSH

         MPMCQ_STATINC Q_R,SCB_STAT_POP_OK
         LHI   R8,-1
         LAAL  R8,SCB_STAT_DEPTH_CUR(Q_R)  atomic depth--

         L     R15,WK_RC(R13)              0 or 8 (trunc)
         MPMCQ_RETURN_SCB R15

SPO_EMPTY DS 0H
         MPMCQ_STATINC Q_R,SCB_STAT_POP_EMPTY
         LA    R15,4                       RC=empty
         MPMCQ_RETURN_SCB R15

         END   MPMCQ
