         TITLE 'MPMC stack - Async notify (ATTACH notifier TCB + ECB POST)'
***********************************************************************
*  MPMCQ_NOTIFY.ASM
*
*  Asynchronous push notifications via ATTACH'd notifier TCB.
*  See file header history in repo docs for coalescing / ECB protocol.
*
*  Performance:
*    MPMCS_NSTART is a leaf (no GETMAIN) — called from SINIT with a
*    work cell already chained.
*    SCBSTOP uses ENTER_SCB / RETURN_SCB (work-cell pool).
*    Notifier keeps a long-lived plist buffer (one GETMAIN for TCB life).
*
*  ATTACH parameter passing:
*    ATTACH PARM=(value) builds a parameter area containing that value
*    and gives the new task R1 -> that area (an indirect pointer), not
*    the value itself in R1. MPMCS_NSTART passes PARM=(Q_R) (the SCB
*    address, in the current Q_R) and MPMCS_NOTIF dereferences it with
*    L Q_R,0(R1) — do not "simplify" this to LR Q_R,R1, and do not pass
*    a literal constant; either would leave Q_R pointing at the wrong
*    storage entirely.
*
*  Shutdown synchronization:
*    SCBSTOP sets the stop flag and POSTs SCB_CB_ECB to wake a WAITing
*    notifier, then WAITs on SCB_STOP_ECB before returning. MPMCS_NOTIF
*    POSTs SCB_STOP_ECB at the very end of NOTIF_DONE, once it has
*    finished all cleanup and will no longer touch the SCB. This closes
*    the window where a caller could free/reuse the SCB immediately
*    after SCBSTOP returns while the subtask was still mid-cleanup.
*    If no notifier was ever attached (SCB_CB_TCB still zero), SCBSTOP
*    skips the WAIT entirely — nothing would ever post SCB_STOP_ECB.
***********************************************************************

         PRINT GEN
         OPTABLE ZOP

         COPY  'src/reg_equates.inc'
         COPY  'src/mpmcq_dsects.inc'
         COPY  'src/mpmcq_atomics.mac'
         COPY  'src/mpmcq_save.mac'

MPMCQNT  CSECT
MPMCQNT  AMODE 31
MPMCQNT  RMODE ANY

         ENTRY MPMCS_NSTART
         ENTRY SCBSTOP
         ENTRY MPMCS_NOTIF

         USING MPMCQNT,R15

QCBF_STOP    EQU X'80000000'

         EXTRN MPMCS_WORKGET
         EXTRN MPMCS_WORKPUT

***********************************************************************
* MPMCS_NSTART — leaf; In: Q_R=SCB (SINIT already has a next SA in R13)
*
* On ATTACH failure (R15 non-zero from ATTACH), SCB_CB_TCB is left
* zero rather than storing whatever ATTACH happened to leave in R1.
* SCBSTOP already treats a zero SCB_CB_TCB as "no notifier running"
* and skips its shutdown WAIT accordingly, so a failed attach here
* degrades to "no async notifications" rather than a bad pointer.
***********************************************************************
MPMCS_NSTART DS 0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         USING MPMCQNT,12
         USING MPMCS_SCB,Q_R

         LT    R3,SCB_CB_EP
         JZ    NSTART_DONE

         XR    R0,R0
         ST    R0,SCB_CB_ECB
         ST    R0,SCB_STOP_ECB
         ST    R0,SCB_CB_TCB

* Pass the SCB address itself (Q_R), not a literal. The subtask
* dereferences it with L Q_R,0(R1) — see file header.
         ATTACH EP=MPMCS_NOTIF,PARM=(Q_R)
         LTR   R15,R15
         JNZ   NSTART_DONE                  failed: SCB_CB_TCB stays 0
         ST    R1,SCB_CB_TCB

NSTART_DONE DS 0H
         XR    R15,R15
         MPMCQ_LEAF_RETURN R15

***********************************************************************
* SCBSTOP(SCBaddr)
***********************************************************************
SCBSTOP  DS 0H
         MPMCQ_ENTER_SCB
         USING MPMCQNT,12
         USING MPMCS_SCB,Q_R

* Nothing to stop (and nothing will ever POST SCB_STOP_ECB) if no
* notifier TCB was ever successfully attached.
         LT    R4,SCB_CB_TCB
         JZ    STOP_NONE

STOP_LOOP DS 0H
         L     R0,SCB_FLAGS
         LR    R3,R0
         O     R3,=XL4'80000000'
         CS    R0,R3,SCB_FLAGS
         JNE   STOP_LOOP

         POST  ECB=SCB_CB_ECB               wake the notifier if it's WAITing

* Block until MPMCS_NOTIF's NOTIF_DONE has fully finished cleanup, so
* the caller cannot free/reuse the SCB while the subtask still holds
* Q_R pointed at it.
         WAIT  ECB=SCB_STOP_ECB

STOP_NONE DS 0H
         XR    R15,R15
         MPMCQ_RETURN_SCB R15

***********************************************************************
* MPMCS_NOTIF — ATTACH'd notifier TCB body
*   Entry: R1 -> fullword containing the SCB address (see ATTACH
*   parameter-passing note in file header). NOT the SCB address itself.
***********************************************************************
MPMCS_NOTIF DS 0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         USING MPMCQNT,12

         L     Q_R,0(R1)                    R1 -> word holding SCB addr
         USING MPMCS_SCB,Q_R

* One plist buffer for the life of this TCB (not per-callback GETMAIN).
         LA    R4,32
         GETMAIN RU,LV=(R4),LOC=BELOW
         LR    R11,R1

NOTIF_LOOP DS 0H
         WAIT  ECB=SCB_CB_ECB
         XR    R0,R0
         ST    R0,SCB_CB_ECB               clear or next WAIT busy-spins

         TM    SCB_FLAGS,X'80'             QCBF_STOP (high bit of FLAGS)
         JO    NOTIF_DONE

         L     R4,SCB_PUSH_SEQ
         L     R5,SCB_CB_SEQ_SEEN
         SR    R4,R5
         LTR   R4,R4
         JZ    NOTIF_LOOP

         L     R6,SCB_PUSH_SEQ
         ST    R6,SCB_CB_SEQ_SEEN

         MPMCQ_STATINC Q_R,SCB_STAT_CB_CALLS
         MPMCQ_STATMAX Q_R,SCB_STAT_CB_PENDING_MAX,R4,R8,R9

         LT    R7,SCB_CB_EP
         JZ    NOTIF_LOOP
         LRA   R0,0(R7)
         JNZ   NOTIF_LOOP

         LR    R1,R11
         L     R0,SCB_CB_CTX
         ST    R0,CBP_CTX(R1)
         ST    Q_R,CBP_SCB(R1)
         ST    R4,CBP_PENDING(R1)

* Callback needs a next SA; try work pool first, else GETMAIN 72.
         LR    R3,R1                       save plist
         L     R15,=V(MPMCS_WORKGET)
         BALR  R14,R15
         LTR   R15,R15
         JZ    NOTIF_HAVE_SA
         LA    R0,72
         GETMAIN RU,LV=(R0),LOC=BELOW
         XR    R5,R5                       R5=0 => FREEMAIN after call
         J     NOTIF_CHAIN_SA
NOTIF_HAVE_SA DS 0H
         LA    R5,1                        R5=1 => WORKPUT after call
NOTIF_CHAIN_SA DS 0H
         ST    R13,4(R1)
         ST    R1,8(R13)
         LR    R13,R1
         LR    R1,R3                       plist for callback
         BALR  R14,R7
         LR    R1,R13
         L     R13,4(R13)
         LTR   R5,R5
         JZ    NOTIF_FREE_SA
         L     R15,=V(MPMCS_WORKPUT)
         BALR  R14,R15
         J     NOTIF_LOOP
NOTIF_FREE_SA DS 0H
         LA    R0,72
         FREEMAIN RU,A=(R1),LV=(R0)
         J     NOTIF_LOOP

NOTIF_DONE DS 0H
         LA    R4,32
         LR    R1,R11
         FREEMAIN RU,A=(R1),LV=(R4)
         XR    R0,R0
         ST    R0,SCB_CB_TCB
* Signal SCBSTOP that cleanup is complete and it is now safe for the
* caller to free/reuse the SCB. Must be the last touch of Q_R/the SCB.
         POST  ECB=SCB_STOP_ECB
         LM    R14,R12,12(R13)
         BR    R14

         END   MPMCQNT
