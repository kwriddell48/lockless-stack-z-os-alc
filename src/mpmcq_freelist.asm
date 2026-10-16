         TITLE 'MPMC stack - Lock-free freelist (nodes + work cells)'
***********************************************************************
*  MPMCQ_FREELIST.ASM
*
*  Two Treiber LIFO pools hang off the SCB:
*    SCB_FREE_*  — MPMCQ_NODE cells (SPUSH/SPOP)
*    SCB_WORK_*  — fixed MPMCS_WORK_CELL save/spill blocks (ENTER_SCB)
*
*  MPMCS_POPNODE / MPMCS_PUSHNODE:
*    Leaf with STM into caller's next SA (standard).
*
*  MPMCS_WORKGET / MPMCS_WORKPUT:
*    Naked helpers (no STM) for use from ENTER_SCB/RETURN_SCB macros.
*    When a work cell is free, words 0/4 hold (NEXT_ABA, NEXT_PTR).
*    While in use those words are the OS save-area header.
*
*  ABA tags are minted per-field as (old ABA + 1) at CDS time — each of
*  SCB_FREE_ABA and SCB_WORK_ABA is tagged independently of the other
*  and independently of SCB_TOP_ABA in MPMCQ.ASM. There is no shared
*  tag generator: correctness only requires monotonicity within a
*  single field's own CDS history, so a global counter was unnecessary
*  contention (every pool was serializing through one cache line for
*  no correctness benefit). SCB_ABA_SEQ is retained in the DSECT for
*  layout/compat but is no longer read or written here.
***********************************************************************

         PRINT GEN
         OPTABLE ZOP

         COPY  'src/reg_equates.inc'
         COPY  'src/mpmcq_dsects.inc'
         COPY  'src/mpmcq_atomics.mac'
         COPY  'src/mpmcq_save.mac'

MPMCQFL  CSECT
MPMCQFL  AMODE 31
MPMCQFL  RMODE ANY

         ENTRY MPMCS_POPNODE
         ENTRY MPMCS_PUSHNODE
         ENTRY MPMCS_WORKGET
         ENTRY MPMCS_WORKPUT

         USING MPMCQFL,R15

***********************************************************************
* MPMCS_POPNODE — In: Q_R=SCB  Out: R15=0 R1=node | R15=4 empty
***********************************************************************
MPMCS_POPNODE DS 0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         USING MPMCQFL,12
         USING MPMCS_SCB,Q_R

POPN_LOOP DS 0H
         LT    R1,SCB_FREE_PTR             R1 = PTR for CDS odd + node base
         JZ    POPN_EMPTY
         L     R0,SCB_FREE_ABA             expected ABA (CDS even)

         USING MPMCQ_NODE,R1               node is already in R1
         L     R7,NODE_NEXT_PTR            desired PTR

         LA    R6,1(R0)                    desired ABA = old+1
         CDS   R0,R6,SCB_FREE_ABA(Q_R)     compare (R0,R1) store (R6,R7)
         JE    POPN_OK
         MPMCQ_STATINC Q_R,SCB_STAT_FREELIST_POP_RETRY
         J     POPN_LOOP

POPN_OK  DS 0H
* R1 = popped node, but LM would restore entry R1 — stash it in the SA.
         XR    R15,R15
         MPMCQ_LEAF_RETURN_R1 R15,R1

POPN_EMPTY DS 0H
         LA    R15,4
         MPMCQ_LEAF_RETURN R15

***********************************************************************
* MPMCS_PUSHNODE — In: Q_R=SCB, NEWNODE_R=node  Out: R15=0
***********************************************************************
MPMCS_PUSHNODE DS 0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         USING MPMCQFL,12
         USING MPMCS_SCB,Q_R
         USING MPMCQ_NODE,NEWNODE_R

PUSHN_LOOP DS 0H
         L     R0,SCB_FREE_ABA
         L     R1,SCB_FREE_PTR
         ST    R0,NODE_NEXT_ABA
         ST    R1,NODE_NEXT_PTR

         LA    R10,1(R0)                  desired ABA = old+1
         LR    R11,NEWNODE_R

         CDS   R0,R10,SCB_FREE_ABA(Q_R)
         JE    PUSHN_OK
         MPMCQ_STATINC Q_R,SCB_STAT_FREELIST_PUSH_RETRY
         J     PUSHN_LOOP

PUSHN_OK DS 0H
         XR    R15,R15
         MPMCQ_LEAF_RETURN R15

***********************************************************************
* MPMCS_WORKGET — naked pop from SCB_WORK_* freelist
*   In:  Q_R = SCB, R14 = return
*   Out: R15=0, R1=cell  |  R15=4 empty
*   Clobbers: R0,R1,R6,R7  (R12/R13/Q_R preserved)
***********************************************************************
MPMCS_WORKGET DS 0H
         LR    R11,R15
         USING MPMCQFL,R11
         USING MPMCS_SCB,Q_R

WGET_LOOP DS 0H
         LT    R1,SCB_WORK_PTR             empty check first (skip ABA load)
         JZ    WGET_EMPTY
         L     R0,SCB_WORK_ABA
* Cell link while free: +0 ABA, +4 PTR (same layout as node NEXT)
         L     R7,4(R1)                    NEXT_PTR

         LA    R6,1(R0)                    desired ABA = old+1
         CDS   R0,R6,SCB_WORK_ABA(Q_R)
         JNE   WGET_LOOP
         XR    R15,R15                     R1 = cell
         BR    R14

WGET_EMPTY DS 0H
         LA    R15,4
         BR    R14

***********************************************************************
* MPMCS_WORKPUT — naked push onto SCB_WORK_* freelist
*   In:  Q_R = SCB, R1 = cell, R14 = return
*   Out: R15=0
*   Clobbers: R0,R1,R6,R8,R9  (preserves cell contents via R1, Q_R, R12-R14)
***********************************************************************
MPMCS_WORKPUT DS 0H
         LR    R10,R15
         USING MPMCQFL,R10
         USING MPMCS_SCB,Q_R

WPUT_LOOP DS 0H
         L     R0,SCB_WORK_ABA
         L     R6,SCB_WORK_PTR
         ST    R0,0(R1)                    cell NEXT_ABA while free
         ST    R6,4(R1)                    cell NEXT_PTR

         LA    R8,1(R0)                    desired ABA = old+1
         LR    R9,R1                       desired PTR = this cell

         CDS   R0,R8,SCB_WORK_ABA(Q_R)
         JNE   WPUT_LOOP

         XR    R15,R15
         BR    R14

         END   MPMCQFL
