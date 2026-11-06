         TITLE 'MPMC stack - Lock-free MPMC LIFO stack (AMODE 31 ca...'
***********************************************************************
*  MPMCQ.ASM
*
*  Public entry points (AMODE 31, standard OS linkage, R1 -> parm
*  list):
*    SINIT  - initialize one Stack Control Block (SCB) and optionally
*             ATTACH a notifier TCB when a callback EP is supplied
*    SPUSH  - push a variable-length record (copy-in semantics)
*    SPOP   - pop a variable-length record (copy-out; truncation OK)
*
*  Version 2 Optimizations & Fixes:
*    - Fixed 64-bit high-half S0C4 on 31-bit payloads (LLGTR before STG
*      and dedicated 31-bit copy path in SPOP).
*    - Added 256-byte inline node payload fast-path (NODE_INLINE) using
*      EXRL MVC to completely avoid STORAGE OBTAIN/RELEASE and MVCL on
*      messages <= 256 bytes.
*    - LM R0,R1 preloads TOP (word-concurrent only). Failed CDS
*      reloads the pair 8-byte atomically; retry uses that snapshot.
*    - Full 32-bit ABA increment via AHI instead of 31-bit LA.
***********************************************************************

         PRINT GEN

         COPY  REGEQUAT
         COPY  DSECTS
         COPY  ATOMICS
         COPY  COPY64
         COPY  TRACE
         COPY  SAVEMAC

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
***********************************************************************
WK_SA      EQU   0
WK_DST     EQU   72
WK_DSTMAX  EQU   76
WK_OUTLENA EQU   80
WK_SRCA    EQU   84
WK_SRCLEN  EQU   88
WK_PAYD    EQU   96
WK_ACTLEN  EQU   104
WK_RC      EQU   108
WK_INLINE  EQU   112
WK_TRCM    EQU   116
WK_IARV    EQU   128
WK_IARVMAX EQU   256
WK_SEG     EQU   384
WK_ORIG    EQU   392
WK_LEN     EQU   MPMCS_WORK_CELL

***********************************************************************
* SINIT(SCBaddr, options, CB_EP, CB_CTX, USER_ECB)
***********************************************************************
SINIT    DS    0H
         MPMCQ_ENTER WK_LEN,MPMCQ
         USING MPMCQ,R12
         USING MPMCS_SINIT_PLIST,R1

         L     Q_R,SINIT_SCBADDR           Q_R -> caller-owned SCB
         TMLL  Q_R,X'0007'                 CDS heads need 0D alignment
         JNZ   SINIT_ALIGN
         USING MPMCS_SCB,Q_R

         LLH   R8,SINIT_OPTIONS
         XR    R0,R0
         TM    SINIT_OPTIONS+3,X'01'       MPMCS_OPT_PAYLOAD64?
         JZ    SINIT_FLAGS_ST
         LA    R0,1
SINIT_FLAGS_ST DS 0H
         ST    R0,SCB_FLAGS

         MVC   SCB_EYECATCH,=CL8'MPMCSTK '
         MVC   SCB_NAME,=CL16'                '
         LA    R0,MPMCS_STATS_VERSION
         ST    R0,SCB_VERSION

         L     R3,SINIT_CB_EP
         ST    R3,SCB_CB_EP
         L     R3,SINIT_CB_CTX
         ST    R3,SCB_CB_CTX
         L     R3,SINIT_USER_ECB
         ST    R3,SCB_USER_ECB
         XR    R6,R6
         TM    SINIT_OPTIONS+3,X'02'       MPMCS_OPT_TRACE
         JZ    SINIT_TRCSAV
         LA    R6,TRC_ALL
SINIT_TRCSAV DS 0H
         ST    R6,WK_TRCM(R13)
         DROP  R1

         XR    R0,R0
         ST    R0,SCB_CB_TCB
         ST    R0,SCB_PUSH_SEQ
         ST    R0,SCB_CB_SEQ_SEEN
         ST    R0,SCB_CB_ECB
         ST    R0,SCB_STOP_ECB

         XC    SCB_STAT_PUSH_OK(STCLR),SCB_STAT_PUSH_OK

         XR    R0,R0
         ST    R0,SCB_TOP_ABA
         ST    R0,SCB_TOP_PTR
         ST    R0,SCB_FREE_ABA
         ST    R0,SCB_FREE_PTR
         ST    R0,SCB_WORK_ABA
         ST    R0,SCB_WORK_PTR
         ST    R0,SCB_ABA_SEQ
         ST    R0,SCB_TRC_MASK
         ST    R0,SCB_TRC_BASE
         ST    R0,SCB_TRC_N
         ST    R0,SCB_TRC_NMSK
         ST    R0,SCB_TRC_NEXT
         ST    R0,SCB_TRC_LOST
         LHI   R4,MPMCS_TRC_BYTES          8192; LA disp max is 4095
         MPMCQ_GETSTG R4
         LTR   R15,R15
         JNZ   SINIT_NORING
         ST    R1,SCB_TRC_BASE
         LA    R0,MPMCS_TRC_SLOTS
         ST    R0,SCB_TRC_N
         BCTR  R0,0
         ST    R0,SCB_TRC_NMSK
         L     R6,WK_TRCM(R13)
         ST    R6,SCB_TRC_MASK
SINIT_NORING DS 0H
         MPMCQ_TRACE TRC_API,TRE_SINIT

***********************************************************************
* Prefill work-cell pool (fixed-size SA/spill blocks for ENTER_SCB).
* Shortage stops the prefill; SPUSH obtains on demand.
***********************************************************************
         LA    R9,MPMCS_WORK_PREFILL
SINIT_WPF DS 0H
         LTR   R9,R9
         JZ    SINIT_WPF_DONE
         LA    R4,MPMCS_WORK_CELL
         MPMCQ_GETSTG R4
         LTR   R15,R15
         JNZ   SINIT_WPF_DONE
         L     R15,=V(MPMCS_WORKPUT)
         BALR  R14,R15                     R1=cell, Q_R=SCB
         BCT   R9,SINIT_WPF
SINIT_WPF_DONE DS 0H

***********************************************************************
* Prefill node freelist (OPTIONS high half, or default).
***********************************************************************
         LR    R9,R8
         LTR   R9,R9
         JNZ   SINIT_NPF_HAVE
         LA    R9,MPMCS_NODE_PREFILL
SINIT_NPF_HAVE DS 0H
SINIT_NPF DS 0H
         LTR   R9,R9
         JZ    SINIT_NPF_DONE
         LA    R4,NODE_SIZE
         MPMCQ_GETSTG R4
         LTR   R15,R15
         JNZ   SINIT_NPF_DONE
         LR    NEWNODE_R,R1
         USING MPMCQ_NODE,NEWNODE_R
         XC    0(NODE_HDR_SIZE,NEWNODE_R),0(NEWNODE_R)
         L     R15,=V(MPMCS_PUSHNODE)
         BALR  R14,R15
         BCT   R9,SINIT_NPF
SINIT_NPF_DONE DS 0H

         L     R15,=V(MPMCS_NSTART)
         BALR  R14,R15

         XR    R4,R4
         MPMCQ_TRACE TRC_API,TRE_SINITX,R4
         XR    R15,R15
         MPMCQ_RETURN R15,WK_LEN

SINIT_ALIGN DS 0H
         LA    R15,8
         MPMCQ_RETURN R15,WK_LEN
         DROP  R5

***********************************************************************
* SPUSH(SCBaddr, srcAddr, srcLen)
***********************************************************************
SPUSH    DS    0H
         MPMCQ_ENTER_SCB MPMCQ
         USING MPMCQ,R12
         USING MPMCS_SCB,Q_R
         USING MPMCS_SPUSH_PLIST,R1
         L     R6,SPU_SRCADDR
         L     R7,SPU_SRCLEN
         DROP  R1
         CLFI  R7,MPMCS_MAX_COPY           one MVCL; reject longer
         JNH   SPU_LEN_OK
         LA    R4,8
         MPMCQ_TRACE TRC_API,TRE_SPUSHX,R4
         LA    R15,8
         MPMCQ_RETURN_SCB R15
SPU_LEN_OK DS 0H
         ST    R6,WK_SRCA(R13)
         ST    R7,WK_SRCLEN(R13)
         MPMCQ_TRACE TRC_API,TRE_SPUSH,R7

         L     R15,=V(MPMCS_POPNODE)
         BALR  R14,R15
         LTR   R15,R15
         JNZ   SPU_GETMAIN
         LR    NEWNODE_R,R1
         J     SPU_HAVE_NODE

SPU_GETMAIN DS 0H
         LA    R4,NODE_SIZE
         MPMCQ_GETSTG R4
         LTR   R15,R15
         JZ    SPU_GOT_NODE
         MPMCQ_STATINC Q_R,SCB_STAT_PUSH_ALLOC_FAIL
         LA    R4,8
         MPMCQ_TRACE TRC_ALC,TRE_NGET,R4
         LA    R15,8
         MPMCQ_RETURN_SCB R15
SPU_GOT_NODE DS 0H
         LR    NEWNODE_R,R1
         XC    0(NODE_HDR_SIZE,NEWNODE_R),0(NEWNODE_R)
         MPMCQ_TRACE TRC_ALC,TRE_NGET,NEWNODE_R

SPU_HAVE_NODE DS 0H
         USING MPMCQ_NODE,NEWNODE_R
         XR    R0,R0
         ST    R0,NODE_RSVD                default: external or 0-len

         L     R6,WK_SRCA(R13)
         LT    R7,WK_SRCLEN(R13)
         JZ    SPU_PAYLOAD_SET             zero-length message is valid

         TM    SCB_FLAGS+3,X'01'           test MPMCS_OPT_PAYLOAD64
         JO    SPU_PAYLOAD_64

*----- 31-bit payload path (fast inline if <= 256B, else OBTAIN) ------
         CLFI  R7,NODE_INLINE_MAX
         JH    SPU_OBTAIN_31

* Fast inline path: no STORAGE OBTAIN, copy with EXRL MVC!
         LA    R4,NODE_INLINE
         LLGTR R4,R4                       ensure high half of R4 is 0
         STG   R4,NODE_PAYLOAD64
         ST    R7,NODE_PAYLOAD_LEN
         LA    R0,1
         ST    R0,NODE_RSVD                mark inline (skip RELEASE)
         LR    R8,R7
         BCTR  R8,0
         EXRL  R8,SPU_MVC_INLINE
         MPMCQ_TRACE TRC_ALC,TRE_INLINE,R7
         J     SPU_STAT_31

SPU_MVC_INLINE MVC 0(0,R4),0(R6)

SPU_OBTAIN_31 DS 0H
         MPMCQ_GETSTG R7
         LTR   R15,R15
         JZ    SPU_HAVE_PAY31
         L     R15,=V(MPMCS_PUSHNODE)
         BALR  R14,R15
         MPMCQ_STATINC Q_R,SCB_STAT_PUSH_ALLOC_FAIL
         LA    R4,8
         MPMCQ_TRACE TRC_ALC,TRE_PAYFAIL,R4
         LA    R15,8
         MPMCQ_RETURN_SCB R15
SPU_HAVE_PAY31 DS 0H
         LLGTR R4,R1                       clear bits 0-32 before STG!
         STG   R4,WK_PAYD(R13)
         STG   R4,NODE_PAYLOAD64
         ST    R7,NODE_PAYLOAD_LEN
         LR    R8,R4                       dest addr
         LR    R9,R7                       dest len
         LR    R10,R6                      src addr
         LR    R11,R7                      src len
         MVCL  R8,R10
         MPMCQ_TRACE TRC_ALC,TRE_OB31,R7

SPU_STAT_31 DS 0H
         MPMCQ_STATADD64 Q_R,SCB_STAT_PAYLOAD31_CUR_HI,                X
               SCB_STAT_PAYLOAD31_CUR_LO,R7,R0,R8
         LR    R4,R8                       new CUR from CDS, not a torn L
         LR    R6,R9
         MPMCQ_STATMAX64 Q_R,SCB_STAT_PAYLOAD31_MAX_HI,                X
               SCB_STAT_PAYLOAD31_MAX_LO,R4,R6,R0,R8
         J     SPU_PAYLOAD_DONE

*----- 64-bit payload path (IARV64) ----------------------------------
SPU_PAYLOAD_64 DS 0H
         L     R15,=V(MPMCS_PAYGET)
         BALR  R14,R15
         LTR   R15,R15
         JZ    SPU_PAYLOAD_COPY
         MPMCQ_STATINC Q_R,SCB_STAT_PUSH_ALLOC_FAIL
         MPMCQ_TRACE TRC_ALC,TRE_PAYFAIL
         L     R15,=V(MPMCS_PUSHNODE)
         BALR  R14,R15
         LA    R4,8
         MPMCQ_TRACE TRC_API,TRE_SPUSHX,R4
         LA    R15,8
         MPMCQ_RETURN_SCB R15

SPU_PAYLOAD_COPY DS 0H
         STG   R8,WK_PAYD(R13)
         STG   R8,NODE_PAYLOAD64
         L     R6,WK_SRCA(R13)
         L     R7,WK_SRCLEN(R13)
         ST    R7,NODE_PAYLOAD_LEN
         MPMCQ_COPY_31_TO_64 R6,R8,R7,R8,R10
         MPMCQ_TRACE TRC_ALC,TRE_PAYOK,R7

         MPMCQ_STATADD64 Q_R,SCB_STAT_PAYLOAD64_CUR_HI,                X
               SCB_STAT_PAYLOAD64_CUR_LO,R7,R0,R8
         LR    R4,R8                       new CUR from CDS, not a torn L
         LR    R6,R9
         MPMCQ_STATMAX64 Q_R,SCB_STAT_PAYLOAD64_MAX_HI,                X
               SCB_STAT_PAYLOAD64_MAX_LO,R4,R6,R0,R8
         J     SPU_PAYLOAD_DONE

SPU_PAYLOAD_SET DS 0H
         XGR   R0,R0
         STG   R0,NODE_PAYLOAD64
         ST    R0,NODE_PAYLOAD_LEN
SPU_PAYLOAD_DONE DS 0H

***********************************************************************
* Treiber push onto SCB_TOP_*.
***********************************************************************
         LM    R0,R1,SCB_TOP_ABA           ABA then PTR; CDS is atomic
         LR    R9,NEWNODE_R                desired PTR
SPU_RETRY_LOOP DS 0H
         STM   R0,R1,NODE_NEXT_ABA         link before publishing node
         LR    R8,R0
         AHI   R8,1                        full 32-bit ABA+1

         CDS   R0,R8,SCB_TOP_ABA           reloads R0,R1 on failure!
         JE    SPU_PUSH_OK
         MPMCQ_STATINC Q_R,SCB_STAT_PUSH_RETRY
         LHI   R4,TRH_TOP
         MPMCQ_TRACE TRC_CDS,TRE_CDSRET,R0,R1,R4
         J     SPU_RETRY_LOOP

SPU_PUSH_OK DS 0H
         LHI   R4,TRH_TOP
         MPMCQ_TRACE TRC_CDS,TRE_CDSOK,R8,R9,R4
         LHI   R8,1
         LAAL  R8,R8,SCB_STAT_DEPTH_CUR    R8 = old depth
         LR    R9,R8
         AHI   R9,1                        R9 = new depth (old + 1)
         MPMCQ_STATMAX Q_R,SCB_STAT_DEPTH_MAX,R9,R8,R11

         LHI   R0,1
         LAAL  R0,R0,SCB_PUSH_SEQ

         LT    R4,SCB_CB_EP
         JZ    SPU_NO_INTPOST
* WAIT LONG=YES needs POST with bit 0 of the ECB address on.
* X'80' in the ECB is the wait bit: skipping on that hung the
* notifier. POST every successful push; ECB coalesces duplicates.
         LA    R1,SCB_CB_ECB
         OILH  R1,X'8000'
         POST  0(1)
         MPMCQ_STATINC Q_R,SCB_STAT_POST_INTERNAL
         MPMCQ_TRACE TRC_NTF,TRE_POSTI
SPU_NO_INTPOST DS 0H

         LT    R4,SCB_USER_ECB
         JZ    SPU_NO_USERECB
         LR    R1,R4
         OILH  R1,X'8000'
         POST  0(1)
         MPMCQ_STATINC Q_R,SCB_STAT_POST_USERECB
         MPMCQ_TRACE TRC_NTF,TRE_POSTU

SPU_NO_USERECB DS 0H
         XR    R4,R4
         MPMCQ_TRACE TRC_API,TRE_SPUSHX,R4
         XR    R15,R15
         MPMCQ_RETURN_SCB R15

***********************************************************************
* SPOP(SCBaddr, dstAddr, dstMaxLen, outLenAddr)
***********************************************************************
         DROP  R5
SPOP     DS    0H
         MPMCQ_ENTER_SCB MPMCQ
         USING MPMCQ,R12
         USING MPMCS_SCB,Q_R
         USING MPMCS_SPOP_PLIST,R1
         L     R6,SPO_DSTADDR
         L     R7,SPO_DSTMAX
         L     R4,SPO_OUTLENADDR
         DROP  R1
         ST    R6,WK_DST(R13)
         ST    R7,WK_DSTMAX(R13)
         ST    R4,WK_OUTLENA(R13)
         XR    R0,R0
         ST    R0,WK_RC(R13)
         MPMCQ_TRACE TRC_API,TRE_SPOP,R7

SPO_RELOAD DS 0H
         LM    R0,R1,SCB_TOP_ABA           ABA then PTR; CDS is atomic
SPO_RETRY_LOOP DS 0H
         LTR   R1,R1
         JZ    SPO_EMPTY

         LR    NODE_R,R1
         USING MPMCQ_NODE,NODE_R
         L     NEXTNODE_R,NODE_NEXT_PTR
* Reject NEXT read while this node was no longer TOP (recycled).
         CL    R0,SCB_TOP_ABA
         JNE   SPO_RELOAD

         LR    R8,R0
         AHI   R8,1                        full 32-bit ABA+1
         LR    R9,NEXTNODE_R

         CDS   R0,R8,SCB_TOP_ABA           reloads R0,R1 on failure!
         JE    SPO_HAVE_NODE
         MPMCQ_STATINC Q_R,SCB_STAT_POP_RETRY
         LHI   R4,TRH_TOP
         MPMCQ_TRACE TRC_CDS,TRE_CDSRET,R0,R1,R4
         J     SPO_RETRY_LOOP

SPO_HAVE_NODE DS 0H
         LHI   R4,TRH_TOP
         MPMCQ_TRACE TRC_CDS,TRE_CDSOK,R8,R9,R4
         L     R9,NODE_PAYLOAD_LEN
         L     R0,NODE_RSVD
         MVC   WK_PAYD(8,R13),NODE_PAYLOAD64
         ST    R9,WK_ACTLEN(R13)
         ST    R0,WK_INLINE(R13)

         LT    R4,WK_OUTLENA(R13)
         JZ    SPO_OUTLEN_DONE
         ST    R9,0(R4)
SPO_OUTLEN_DONE DS 0H

* Truncation still consumes the node (RC=8). Remainder is
* discarded. outLen is the full payload length. No peek.
         L     R7,WK_DSTMAX(R13)
         LR    R5,R9
         CLR   R9,R7
         JNH   SPO_COPY_FULL
         LR    R5,R7
         LA    R15,8
         ST    R15,WK_RC(R13)
         J     SPO_DO_COPY
SPO_COPY_FULL DS 0H
         XR    R15,R15
         ST    R15,WK_RC(R13)

SPO_DO_COPY DS 0H
         LTR   R5,R5
         JZ    SPO_SKIP_COPY
         L     R6,WK_DST(R13)
         TM    SCB_FLAGS+3,X'01'
         JO    SPO_COPY_64

* 31-bit copy path (no SAM64 needed; EXRL MVC if <= 256B)
         L     R8,WK_PAYD+4(R13)           low 32-bit payload address
         CLFI  R5,256
         JH    SPO_MVCL_31
         LR    R4,R5
         BCTR  R4,0
         EXRL  R4,SPO_MVC_INST
         J     SPO_SKIP_COPY

SPO_MVC_INST MVC 0(0,R6),0(R8)

SPO_MVCL_31 DS 0H
         LR    R4,R6                       dest addr (R5 = dst len)
         LR    R9,R5                       src len   (R8 = src addr)
         MVCL  R4,R8
         J     SPO_SKIP_COPY

SPO_COPY_64 DS 0H
         LG    R8,WK_PAYD(R13)
         MPMCQ_COPY_64_TO_31 R8,R6,R5,R4,R8
SPO_SKIP_COPY DS 0H

* Free payload using the SAME mode bit that was set at SINIT.
         LT    R9,WK_ACTLEN(R13)
         JZ    SPO_SKIP_FREE

         TM    SCB_FLAGS+3,X'01'
         JO    SPO_FREE_64

* If payload was inline in NODE_INLINE, skip STORAGE RELEASE!
         LT    R0,WK_INLINE(R13)
         JNZ   SPO_STAT_SUB31

         LR    R7,R9
         L     R8,WK_PAYD+4(R13)
         MPMCQ_FRESTG R7,R8

SPO_STAT_SUB31 DS 0H
         LCR   R7,R9
         MPMCQ_STATADD64S Q_R,SCB_STAT_PAYLOAD31_CUR_HI,               X
               SCB_STAT_PAYLOAD31_CUR_LO,R7,R0,R8
         J     SPO_SKIP_FREE

SPO_FREE_64 DS 0H
         L     R7,WK_ACTLEN(R13)
         LG    R8,WK_PAYD(R13)
         L     R15,=V(MPMCS_PAYFREE)
         BALR  R14,R15
         LLGFR R8,R8
         L     R7,WK_ACTLEN(R13)
         LCR   R7,R7
         MPMCQ_STATADD64S Q_R,SCB_STAT_PAYLOAD64_CUR_HI,               X
               SCB_STAT_PAYLOAD64_CUR_LO,R7,R0,R8

SPO_SKIP_FREE DS 0H
         XGR   R0,R0
         STG   R0,NODE_PAYLOAD64
         ST    R0,NODE_PAYLOAD_LEN
         ST    R0,NODE_RSVD

         LR    NEWNODE_R,NODE_R
         L     R15,=V(MPMCS_PUSHNODE)
         BALR  R14,R15

         MPMCQ_STATINC Q_R,SCB_STAT_POP_OK
         LHI   R8,-1
         LAAL  R8,R8,SCB_STAT_DEPTH_CUR

         L     R4,WK_RC(R13)
         MPMCQ_TRACE TRC_API,TRE_SPOPX,R4
         L     R15,WK_RC(R13)
         MPMCQ_RETURN_SCB R15

SPO_EMPTY DS 0H
         MPMCQ_STATINC Q_R,SCB_STAT_POP_EMPTY
         LA    R4,4
         MPMCQ_TRACE TRC_API,TRE_SPOPX,R4
         LA    R15,4
         MPMCQ_RETURN_SCB R15

         LTORG
         END   MPMCQ
