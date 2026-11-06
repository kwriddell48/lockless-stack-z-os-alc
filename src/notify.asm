         TITLE 'MPMC stack - Async notify (ATTACH notifier TCB + EC...'
***********************************************************************
*  NOTIFY.ASM
*
*  Asynchronous push notifications via ATTACH'd notifier TCB.
*  Version 2 Fixes:
*    - Checks SCB_PUSH_SEQ != SCB_CB_SEQ_SEEN before entering WAIT.
*    - Serializes SCB_CB_ECB clear with CS before reading SCB_PUSH_SEQ.
*    - Stores the exact SCB_PUSH_SEQ snapshot (R6) used to compute
*      delta into SCB_CB_SEQ_SEEN (prevents lost notifications).
*    - Lets MVS SVC 3 (EXIT) post ATTACHX ECB=(4) (SCB_STOP_ECB) upon
*      task termination rather than posting prematurely in user state.
***********************************************************************

         PRINT GEN

         COPY  REGEQUAT
         COPY  DSECTS
         COPY  ATOMICS
         COPY  TRACE
         COPY  SAVEMAC

MPMCQNT  CSECT
MPMCQNT  AMODE 31
MPMCQNT  RMODE ANY

         ENTRY MPMCS_NSTART
         ENTRY SCBSTOP
         ENTRY MPMCS_NOTIF
         ENTRY MPMCNOTF

         USING MPMCQNT,R15

QCBF_STOP    EQU X'80000000'

         EXTRN MPMCS_WORKGET
         EXTRN MPMCS_WORKPUT

***********************************************************************
* MPMCS_NSTART - leaf. In: Q_R=SCB
***********************************************************************
MPMCS_NSTART DS 0H
         STM   R14,R12,12(R13)
         LARL  R12,MPMCQNT
         DROP  R15
         USING MPMCQNT,R12
         USING MPMCS_SCB,Q_R

         LT    R3,SCB_CB_EP
         JZ    NSTART_DONE

         XR    R0,R0
         ST    R0,SCB_CB_ECB
         ST    R0,SCB_STOP_ECB
         ST    R0,SCB_CB_TCB

         LARL  R3,MPMCS_NOTIF
         IDENTIFY EP=MPMCNOTF,ENTRY=(R3)
         CFI   R15,4
         JH    NSTART_DONE                  RC>4: IDENTIFY failed
         LA    R4,MPMCS_WORK_CELL
         MPMCQ_GETSTG R4
         LTR   R15,R15
         JNZ   NSTART_DONE
         LR    R6,R1                       execute + user PARAM list
         ST    R6,SCB_ABA_SEQ
         XC    0(256,R6),0(R6)
         LA    R4,SCB_STOP_ECB
         OILH  R4,X'8000'                  31-bit ATTACH completion ECB
         ATTACHX EPLOC=NTFNAME,PARAM=((R2)),ECB=(4),                   X
               ERRET=NSTART_ATTF,MF=(E,(6))
         LTR   R15,R15
         JNZ   NSTART_ATTF
         ST    R1,SCB_CB_TCB
         J     NSTART_DONE
NSTART_ATTF DS 0H
         L     R3,SCB_ABA_SEQ
         LTR   R3,R3
         JZ    NSTART_DONE
         LA    R4,MPMCS_WORK_CELL
         MPMCQ_FRESTG R4,R3
         XR    R0,R0
         ST    R0,SCB_ABA_SEQ
NSTART_DONE DS 0H
         XR    R15,R15
         MPMCQ_LEAF_RETURN R15

***********************************************************************
* SCBSTOP(SCBaddr)
***********************************************************************
SCBSTOP  DS 0H
         MPMCQ_ENTER_SCB MPMCQNT
         USING MPMCQNT,R12
         USING MPMCS_SCB,Q_R

         MPMCQ_TRACE TRC_API,TRE_SSTOP
         LT    R4,SCB_CB_TCB
         JZ    STOP_NONE

         L     R0,SCB_FLAGS
STOP_LOOP DS 0H
         LR    R3,R0
         OILH  R3,X'8000'                  QCBF_STOP in 32-bit word
         CS    R0,R3,SCB_FLAGS
         JNE   STOP_LOOP

         LA    R1,SCB_CB_ECB
         OILH  R1,X'8000'                  wake WAIT LONG=YES
         POST  0(1)
         MPMCQ_TRACE TRC_NTF,TRE_STOP

* ATTACHX ECB=(4) posts SCB_STOP_ECB once subtask completes SVC 3.
         WAIT  ECB=SCB_STOP_ECB,LONG=YES

         LA    R3,SCB_CB_TCB
         DETACH (3)
         XR    R0,R0
         ST    R0,SCB_CB_TCB
         MPMCQ_TRACE TRC_NTF,TRE_DETACH

STOP_NONE DS 0H
* Drop CB_EP so a late SPUSH after SCBSTOP does not POST SCB_CB_ECB.
         XR    R0,R0
         ST    R0,SCB_CB_EP
         XR    R4,R4
         MPMCQ_TRACE TRC_API,TRE_SSTOPX,R4
         XR    R15,R15
         MPMCQ_RETURN_SCB R15

***********************************************************************
* MPMCS_NOTIF  -  ATTACH'd notifier TCB body
***********************************************************************
MPMCNOTF DS 0H
MPMCS_NOTIF DS 0H
         STM   R14,R12,12(R13)
         LARL  R12,MPMCQNT
         DROP  R15
         USING MPMCQNT,R12

         LR    Q_R,R1
         CLC   0(8,Q_R),=CL8'MPMCSTK '
         JE    NOTIF_HAVEQ
         L     Q_R,0(R1)
NOTIF_HAVEQ DS 0H
         USING MPMCS_SCB,Q_R

         LA    R4,32
         MPMCQ_GETSTG R4
         LTR   R15,R15
         JNZ   NOTIF_NOCB
         LR    R11,R1

NOTIF_LOOP DS 0H
         TM    SCB_FLAGS,X'80'
         JO    NOTIF_DONE

* Check if work is already pending before entering WAIT
         L     R6,SCB_PUSH_SEQ
         L     R5,SCB_CB_SEQ_SEEN
         CLR   R6,R5
         JNE   NOTIF_CLEAR_ECB

         MPMCQ_TRACE TRC_NTF,TRE_WAIT
         WAIT  ECB=SCB_CB_ECB,LONG=YES

NOTIF_CLEAR_ECB DS 0H
* Clear ECB with CS (serialize before re-reading PUSH_SEQ).
* SPUSH does LAAL PUSH_SEQ then POST. Clearing a coalesced post
* bit here cannot lose events: any later push bumps PUSH_SEQ
* before POST, so the snapshot below still sees delta > 0.
         L     R0,SCB_CB_ECB
NOTIF_CLR_LOOP DS 0H
         XR    R3,R3
         CS    R0,R3,SCB_CB_ECB
         JNE   NOTIF_CLR_LOOP

         TM    SCB_FLAGS,X'80'
         JO    NOTIF_DONE

         L     R6,SCB_PUSH_SEQ             snapshot current seq once
         L     R5,SCB_CB_SEQ_SEEN
         LR    R4,R6
         SR    R4,R5                       delta = R6 - R5
         LTR   R4,R4
         JZ    NOTIF_LOOP

         ST    R6,SCB_CB_SEQ_SEEN          record exact snapshot seen!

         MPMCQ_STATINC Q_R,SCB_STAT_CB_CALLS
         MPMCQ_STATMAX Q_R,SCB_STAT_CB_PENDING_MAX,R4,R8,R9
         MPMCQ_TRACE TRC_NTF,TRE_CB,R4

         LT    R7,SCB_CB_EP
         JZ    NOTIF_LOOP

         LR    R1,R11
         USING MPMCQ_CB_PLIST,R1
         L     R0,SCB_CB_CTX
         ST    R0,CBP_CTX
         ST    Q_R,CBP_SCB
         ST    R4,CBP_PENDING
         DROP  R1

         LR    R3,R1
         L     R15,=V(MPMCS_WORKGET)
         BALR  R14,R15
         LTR   R15,R15
         JZ    NOTIF_HAVE_SA
         LA    R4,72
         MPMCQ_GETSTG R4
         LTR   R15,R15
         JNZ   NOTIF_LOOP
         XR    R5,R5
         J     NOTIF_CHAIN_SA
NOTIF_HAVE_SA DS 0H
         LA    R5,1
NOTIF_CHAIN_SA DS 0H
         ST    R13,4(R1)
         ST    R1,8(R13)
         LR    R13,R1
         LR    R1,R3
         LR    R11,R3
         L     R7,SCB_CB_EP
         BALR  R14,R7
         LR    R1,R13
         L     R13,4(R13)
         LTR   R5,R5
         JZ    NOTIF_FREE_SA
         L     R15,=V(MPMCS_WORKPUT)
         BALR  R14,R15
         J     NOTIF_LOOP
NOTIF_FREE_SA DS 0H
         LA    R4,72
         LR    R3,R1
         MPMCQ_FRESTG R4,R3
         J     NOTIF_LOOP

NOTIF_DONE DS 0H
         LA    R4,32
         MPMCQ_FRESTG R4,R11
NOTIF_NOCB DS 0H
         L     R3,SCB_ABA_SEQ
         LTR   R3,R3
         JZ    NOTIF_NOPARM
         LA    R4,MPMCS_WORK_CELL
         MPMCQ_FRESTG R4,R3
         XR    R0,R0
         ST    R0,SCB_ABA_SEQ
NOTIF_NOPARM DS 0H
* MVS EXIT (SVC 3) posts ATTACHX's ECB=(4) (SCB_STOP_ECB) automatically
         XR    R15,R15
         SVC   3

NTFNAME  DC    CL8'MPMCNOTF'
         LTORG
         END   MPMCQNT
