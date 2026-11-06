         TITLE 'MPMC stack - Lock-free freelist (nodes + work cells)'
***********************************************************************
*  FREELIST.ASM
*
*  Two Treiber LIFO pools hang off the SCB:
*    SCB_FREE_*  - MPMCQ_NODE cells (SPUSH/SPOP)
*    SCB_WORK_*  - fixed MPMCS_WORK_CELL save/spill blocks (ENTER_SCB)
*
*  LM R0,R1 preloads the tagged head (word-concurrent only). Failed
*  CDS reloads (R0,R1) 8-byte atomically; retry uses that snapshot.
*  Uses AHI +1 instead of LA so bit 0 of the 32-bit ABA tag is kept.
***********************************************************************

         PRINT GEN

         COPY  REGEQUAT
         COPY  DSECTS
         COPY  ATOMICS
         COPY  TRACE
         COPY  SAVEMAC

MPMCQFL  CSECT
MPMCQFL  AMODE 31
MPMCQFL  RMODE ANY

         ENTRY MPMCS_POPNODE
         ENTRY MPMCS_PUSHNODE
         ENTRY MPMCS_WORKGET
         ENTRY MPMCS_WORKPUT

         USING MPMCQFL,R15

***********************************************************************
* MPMCS_POPNODE  -  In: Q_R=SCB  Out: R15=0 R1=node | R15=4 empty
***********************************************************************
MPMCS_POPNODE DS 0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         DROP  R15
         USING MPMCQFL,R12
         USING MPMCS_SCB,Q_R

POPN_RELOAD DS 0H
         LM    R0,R1,SCB_FREE_ABA          ABA then PTR; CDS is atomic
POPN_LOOP DS 0H
         LTR   R1,R1
         JZ    POPN_EMPTY

         USING MPMCQ_NODE,R1
         L     R7,NODE_NEXT_PTR            desired PTR
* Reject NEXT read while this node was no longer FREE head.
         CL    R0,SCB_FREE_ABA
         JNE   POPN_RELOAD
         LR    R6,R0
         AHI   R6,1                        full 32-bit ABA+1

         CDS   R0,R6,SCB_FREE_ABA          reloads R0,R1 on failure!
         JE    POPN_OK
         MPMCQ_STATINC Q_R,SCB_STAT_FREELIST_POP_RETRY
         LHI   R4,TRH_FREE
         MPMCQ_TRACE TRC_CDS,TRE_CDSRET,R0,R1,R4
         J     POPN_LOOP

POPN_OK  DS 0H
         LHI   R4,TRH_FREE
         MPMCQ_TRACE TRC_CDS,TRE_CDSOK,R6,R7,R4
         XR    R15,R15
         MPMCQ_LEAF_RETURN_R1 R15,R1

POPN_EMPTY DS 0H
         LA    R15,4
         MPMCQ_LEAF_RETURN R15
         DROP  R1

***********************************************************************
* MPMCS_PUSHNODE  -  In: Q_R=SCB, NEWNODE_R=node  Out: R15=0
***********************************************************************
MPMCS_PUSHNODE DS 0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         USING MPMCQFL,R12
         USING MPMCS_SCB,Q_R
         USING MPMCQ_NODE,NEWNODE_R

         LM    R0,R1,SCB_FREE_ABA          ABA then PTR; CDS is atomic
         LR    R11,NEWNODE_R
PUSHN_LOOP DS 0H
         STM   R0,R1,NODE_NEXT_ABA
         LR    R10,R0
         AHI   R10,1                       full 32-bit ABA+1

         CDS   R0,R10,SCB_FREE_ABA         reloads R0,R1 on failure!
         JE    PUSHN_OK
         MPMCQ_STATINC Q_R,SCB_STAT_FREELIST_PUSH_RETRY
         LHI   R4,TRH_FREE
         MPMCQ_TRACE TRC_CDS,TRE_CDSRET,R0,R1,R4
         J     PUSHN_LOOP

PUSHN_OK DS 0H
         LHI   R4,TRH_FREE
         MPMCQ_TRACE TRC_CDS,TRE_CDSOK,R10,R11,R4
         XR    R15,R15
         MPMCQ_LEAF_RETURN R15
         DROP  R5
         DROP  R12

***********************************************************************
* MPMCS_WORKGET  -  naked pop from SCB_WORK_* freelist
*   In:  Q_R = SCB, R14 = return
*   Out: R15=0, R1=cell  |  R15=4 empty
*   Clobbers: R0,R1,R4,R6,R7,R11,R15  (R12/R13/Q_R preserved)
***********************************************************************
MPMCS_WORKGET DS 0H
         LR    R11,R15
         USING MPMCQFL,R11
         USING MPMCS_SCB,Q_R

WGET_RELOAD DS 0H
         LM    R0,R1,SCB_WORK_ABA          ABA then PTR; CDS is atomic
WGET_LOOP DS 0H
         LTR   R1,R1
         JZ    WGET_EMPTY
         L     R7,4(R1)                    NEXT_PTR
* Reject NEXT read while this cell was no longer WORK head.
         CL    R0,SCB_WORK_ABA
         JNE   WGET_RELOAD
         LR    R6,R0
         AHI   R6,1                        full 32-bit ABA+1
         CDS   R0,R6,SCB_WORK_ABA          reloads R0,R1 on failure!
         JE    WGET_OK
         LHI   R4,TRH_WORK
         MPMCQ_TRACE TRC_CDS,TRE_CDSRET,R0,R1,R4
         J     WGET_LOOP
WGET_OK  DS 0H
         LHI   R4,TRH_WORK
         MPMCQ_TRACE TRC_CDS,TRE_CDSOK,R6,R7,R4
         XR    R15,R15
         BR    R14

WGET_EMPTY DS 0H
         LA    R15,4
         BR    R14
         DROP  R11

***********************************************************************
* MPMCS_WORKPUT  -  naked push onto SCB_WORK_* freelist
*   In:  Q_R = SCB, R1 = cell, R14 = return
*   Out: R15=0
*   Clobbers: R0,R1,R4,R5,R6,R7,R10,R15
*   (not R8/R9: SINIT keeps counts there)
***********************************************************************
MPMCS_WORKPUT DS 0H
         LR    R10,R15
         USING MPMCQFL,R10
         USING MPMCS_SCB,Q_R
         LR    R5,R1                       cell (keep off the CDS pair)
         LR    R7,R5                       desired PTR = this cell

         LM    R0,R1,SCB_WORK_ABA          ABA then PTR; CDS is atomic
WPUT_LOOP DS 0H
         STM   R0,R1,0(R5)                 cell NEXT_ABA, NEXT_PTR
         LR    R6,R0
         AHI   R6,1                        full 32-bit ABA+1

         CDS   R0,R6,SCB_WORK_ABA          reloads R0,R1 on failure!
         JE    WPUT_OK
         LHI   R4,TRH_WORK
         MPMCQ_TRACE TRC_CDS,TRE_CDSRET,R0,R1,R4
         J     WPUT_LOOP
WPUT_OK  DS 0H
         LHI   R4,TRH_WORK
         MPMCQ_TRACE TRC_CDS,TRE_CDSOK,R6,R7,R4
         XR    R15,R15
         BR    R14

         LTORG
         END   MPMCQFL
